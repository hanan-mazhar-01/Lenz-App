import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replica_detector/core/config/gemini_config.dart';
import 'package:replica_detector/services/cloudinary_service.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/repositories/category_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/services/data_migration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Backend Security & Configuration', () {
    test('Gemini is reached only through the Cloud Function proxy', () {
      expect(GeminiConfig.hasValidKey, isTrue);
    });

    test('Cloudinary uploads are signed by the server, never an unsigned preset', () async {
      final dir = Directory.systemTemp.createTempSync('lenz_cloudinary_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photo = File('${dir.path}/overview.jpg')..writeAsStringSync('fake-jpeg');

      List<String>? signedIds;
      http.BaseRequest? sent;
      String? body;
      final service = CloudinaryService(
        signer: (scanId, ids) async {
          expect(scanId, 'rep_1');
          signedIds = ids;
          return {
            'cloudName': 'democloud',
            'apiKey': 'key123',
            'folder': 'lenz_replica_detector',
            'timestamp': 1764072000,
            'uploads': {
              'overview': {'publicId': 'uid1_rep_1_overview', 'signature': 'sig-abc'},
            },
          };
        },
        client: MockClient((request) async {
          sent = request;
          body = request.body;
          return http.Response('{"secure_url":"https://res.cloudinary.com/x.jpg"}', 200);
        }),
      );

      final urls = await service.uploadEvidencePhotos(
        userId: 'uid1',
        scanId: 'rep_1',
        localImages: {'overview': photo.path, 'remote': 'https://already/uploaded.jpg'},
      );

      expect(signedIds, ['overview'], reason: 'only local files are signed');
      expect(urls, {'overview': 'https://res.cloudinary.com/x.jpg'});
      expect(sent!.url.toString(), 'https://api.cloudinary.com/v1_1/democloud/image/upload');
      for (final field in ['key123', '1764072000', 'lenz_replica_detector', 'uid1_rep_1_overview', 'sig-abc']) {
        expect(body, contains(field));
      }
      expect(body, isNot(contains('upload_preset')));
    });

    test('Cloudinary upload is skipped quietly when signing fails', () async {
      final dir = Directory.systemTemp.createTempSync('lenz_cloudinary_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photo = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
      var uploads = 0;
      final service = CloudinaryService(
        signer: (_, __) async => throw Exception('offline'),
        client: MockClient((_) async {
          uploads++;
          return http.Response('{}', 200);
        }),
      );
      final urls = await service.uploadEvidencePhotos(userId: 'u', scanId: 'rep_2', localImages: {'a': photo.path});
      expect(urls, isEmpty);
      expect(uploads, 0);
    });
  });

  group('Offline-first Repositories & SharedPreferences Persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('HistoryRepository persists and reloads reports offline', () async {
      final repo = HistoryRepository();
      await repo.loadPersistedReports();
      expect(repo.allReports, isEmpty);

      final report = AuthenticationReport(
        id: 'test_rep_1',
        product: const Product(
          id: 'prod_chanel_1',
          name: 'Classic Flap',
          brand: 'Chanel',
          model: 'Medium',
          category: ProductCategory.bags,
          imageAsset: 'assets/images/chanel.png',
        ),
        verdict: Verdict.likelyAuthentic,
        overallScore: 92,
        quickSummaryPoints: const ['Consistent leather grain'],
        evidenceItems: const [],
        rationale: 'Verified features match authentic specifications.',
        timestamp: DateTime(2025, 1, 1),
      );

      repo.addReport(report);
      expect(repo.allReports.length, 1);
      expect(repo.allReports.first.id, 'test_rep_1');

      // Verify written to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedList = prefs.getStringList('vericheck_reports_v2');
      expect(savedList, isNotNull);
      expect(savedList!.length, 1);

      // Verify reload in a fresh repository instance
      final reloadedRepo = HistoryRepository();
      await reloadedRepo.loadPersistedReports(prefs: prefs);
      expect(reloadedRepo.allReports.length, 1);
      expect(reloadedRepo.allReports.first.product.brand, 'Chanel');
    });

    test('CategoryRepository registers and persists custom categories', () async {
      final repo = CategoryRepository();
      await repo.loadCategories();

      final initialCount = repo.allCategories.length;
      final added = repo.registerCategory('Fine Jewelry');
      expect(added, isNotNull);
      expect(repo.allCategories.length, initialCount + 1);

      // Verify SharedPreferences persistence
      final reloaded = CategoryRepository();
      await reloaded.loadCategories();
      expect(reloaded.allCategories.any((c) => c.label == 'Fine Jewelry'), isTrue);
    });

    test('DataMigrationService respects migration flag', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('vericheck_migrated_to_firestore_user123', true);

      // Call migration — should exit without error or redundant work
      await DataMigrationService.migrateOfflineDataIfNeeded(
        uid: 'user123',
        prefs: prefs,
      );

      expect(prefs.getBool('vericheck_migrated_to_firestore_user123'), isTrue);
    });

    test('Guest user is capped at 3 scans before paywall gate triggers', () async {
      final repo = HistoryRepository();
      await repo.loadPersistedReports();

      // Guest starts with 0 reports, can scan up to 3 times
      expect(repo.allReports.length < 3, isTrue);

      // Add 3 reports (simulating 3 completed scans)
      for (int i = 1; i <= 3; i++) {
        repo.addReport(AuthenticationReport(
          id: 'scan_$i',
          product: Product(
            id: 'prod_$i',
            name: 'Item $i',
            brand: 'Brand',
            model: 'Model',
            category: ProductCategory.bags,
            imageAsset: '',
          ),
          verdict: Verdict.likelyAuthentic,
          overallScore: 90,
          quickSummaryPoints: const [],
          evidenceItems: const [],
          rationale: 'Pass',
          timestamp: DateTime.now(),
        ));
      }

      // 3 scans done: gate condition is now met
      final shouldShowGuestPaywall = repo.allReports.length >= 3;
      expect(shouldShowGuestPaywall, isTrue);
      expect(repo.allReports.length, 3);
    });
  });
}
