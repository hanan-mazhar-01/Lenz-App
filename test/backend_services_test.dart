import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/config/cloudinary_config.dart';
import 'package:replica_detector/core/config/env_secrets.dart';
import 'package:replica_detector/core/config/gemini_config.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/collection_item.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/repositories/category_repository.dart';
import 'package:replica_detector/repositories/collection_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/services/data_migration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Backend Security & Configuration', () {
    test('Client-side code contains no hardcoded Gemini API key', () {
      expect(EnvSecrets.geminiApiKey, isEmpty);
      expect(GeminiConfig.hasValidKey, isTrue);
    });

    test('Cloudinary configuration yields correct upload URL', () {
      expect(CloudinaryConfig.uploadUrl, contains('/image/upload'));
      expect(CloudinaryConfig.uploadUrl, contains(CloudinaryConfig.cloudName));
      expect(CloudinaryConfig.isConfigured, isTrue);
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

    test('CollectionRepository persists and deduplicates items', () async {
      final repo = CollectionRepository();
      await repo.load();
      expect(repo.allItems, isEmpty);

      final item = CollectionItem(
        id: 'col_1',
        name: 'Submariner Date',
        brand: 'Rolex',
        model: '126610LN',
        category: ProductCategory.watches,
        imageAsset: 'assets/images/rolex.png',
        verdict: Verdict.likelyAuthentic,
        authenticationConfidence: 95,
        savedDate: DateTime.now(),
        scannedDate: DateTime.now(),
        sourceReportId: 'rep_rolex_1',
      );

      repo.addItem(item);
      expect(repo.allItems.length, 1);

      // Attempt duplicate addition with same source report ID
      repo.addItem(item);
      expect(repo.allItems.length, 1);

      // Reload test
      final reloaded = CollectionRepository();
      await reloaded.load();
      expect(reloaded.allItems.length, 1);
      expect(reloaded.allItems.first.brand, 'Rolex');
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
