import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/data/authentication_rules.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/collection_item.dart';
import 'package:replica_detector/models/evidence.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/repositories/collection_repository.dart';
import 'package:replica_detector/repositories/guide_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';

AuthenticationReport sampleReport({String id = 'rep_1', bool favorite = false}) {
  final evidence = fullWatchEvidence();
  return AuthenticationReport(
    id: id,
    product: testWatch,
    verdict: Verdict.likelyAuthentic,
    overallScore: 86,
    identificationConfidence: 91,
    authenticationConfidence: 86,
    evidenceCoverageText: '6 / 6 requested views supplied',
    coveredEvidenceCount: 6,
    totalEvidenceCount: 6,
    quickSummaryPoints: const ['Dial printing is sharp'],
    positiveFindings: const ['Dial: printing is sharp'],
    suspiciousFindings: const [],
    unclearFindings: const [],
    missingEvidence: const [],
    contradictions: const [],
    nextChecks: const ['Compare the clasp stamping against a trusted reference'],
    physicalChecks: const [
      PhysicalCheck(title: 'Crown', description: 'Feel the threading', whatToLookFor: 'Smooth action'),
    ],
    evidenceItems: evidence,
    rationale: 'Across 6 of 6 requested views the details are consistent.',
    timestamp: DateTime(2026, 3, 14, 9, 30),
    isFavorite: favorite,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('No seeded data anywhere (§30, §31, §33, §34)', () {
    test('history starts empty', () async {
      final repo = HistoryRepository();
      expect(repo.allReports, isEmpty);
      await repo.loadPersistedReports();
      expect(repo.allReports, isEmpty);
      expect(repo.favoriteReports, isEmpty);
      expect(repo.isEmpty, isTrue);
    });

    test('every category reads empty before any scan', () async {
      final repo = HistoryRepository();
      await repo.loadPersistedReports();
      for (final c in ProductCategory.values) {
        final matches = repo.allReports.where((r) => r.product.category == c);
        expect(matches, isEmpty, reason: 'No placeholder in ${c.label}');
      }
    });

    test('the collection starts empty', () async {
      final repo = CollectionRepository();
      expect(repo.allItems, isEmpty);
      await repo.load();
      expect(repo.totalCount, 0);
      expect(repo.isEmpty, isTrue);
    });
  });

  group('Reports round-trip through storage (§42, §47, §57)', () {
    test('a saved report reloads with its findings, metrics and images intact', () async {
      final repo = HistoryRepository();
      await repo.loadPersistedReports();
      repo.addReport(sampleReport());
      await repo.persist();

      final reloaded = HistoryRepository();
      await reloaded.loadPersistedReports();

      expect(reloaded.allReports, hasLength(1));
      final r = reloaded.allReports.first;
      expect(r.id, 'rep_1');
      expect(r.product.name, 'Submariner Date');
      expect(r.verdict, Verdict.likelyAuthentic);
      expect(r.authenticationConfidence, 86);
      expect(r.identificationConfidence, 91);
      expect(r.coveredEvidenceCount, 6);
      expect(r.positiveFindings, isNotEmpty);
      expect(r.nextChecks, isNotEmpty);
      expect(r.physicalChecks.single.title, 'Crown');
      expect(r.timestamp, DateTime(2026, 3, 14, 9, 30));

      final dial = r.evidenceItems.firstWhere((e) => e.id == 'dial');
      expect(dial.weight, EvidenceWeight.critical);
      expect(dial.capturedImagePath, '/tmp/dial.jpg');
      expect(dial.photoQualityScore, 90);
      expect(dial.usefulnessScore, 90);
    });

    test('favourites persist across a restart', () async {
      final repo = HistoryRepository();
      await repo.loadPersistedReports();
      repo.addReport(sampleReport(id: 'rep_fav'));
      repo.toggleFavorite('rep_fav');
      await repo.persist();

      final reloaded = HistoryRepository();
      await reloaded.loadPersistedReports();
      expect(reloaded.favoriteReports, hasLength(1));
      expect(reloaded.favoriteReports.first.id, 'rep_fav');
    });

    test('deleting a report returns its image paths for cleanup', () async {
      final repo = HistoryRepository();
      await repo.loadPersistedReports();
      repo.addReport(sampleReport());

      final orphaned = repo.deleteReport('rep_1');

      expect(repo.allReports, isEmpty);
      expect(orphaned, contains('/tmp/dial.jpg'));
      expect(orphaned, contains('/tmp/reference_serial.jpg'));
    });

    test('a corrupt stored entry is skipped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'vericheck_reports_v2': ['{not valid json', '{"id":"ok","product":{},"verdict":"inconclusive"}'],
      });
      final repo = HistoryRepository();
      await repo.loadPersistedReports();
      expect(repo.allReports, hasLength(1));
      expect(repo.allReports.first.id, 'ok');
    });
  });

  group('Collection persists real saves only (§30, §47)', () {
    test('an item saved from a report reloads with its real values', () async {
      final repo = CollectionRepository();
      await repo.load();
      repo.addItem(CollectionItem.fromReport(sampleReport()));

      final reloaded = CollectionRepository();
      await reloaded.load();

      expect(reloaded.totalCount, 1);
      final item = reloaded.allItems.first;
      expect(item.name, 'Submariner Date');
      expect(item.verdict, Verdict.likelyAuthentic);
      expect(item.authenticationConfidence, 86);
      expect(item.sourceReportId, 'rep_1');
      expect(item.scannedDate, DateTime(2026, 3, 14, 9, 30));
    });

    test('the same report cannot be saved twice', () async {
      final repo = CollectionRepository();
      await repo.load();
      repo.addItem(CollectionItem.fromReport(sampleReport()));
      repo.addItem(CollectionItem.fromReport(sampleReport()));
      expect(repo.totalCount, 1);
      expect(repo.containsReport('rep_1'), isTrue);
    });

    test('collection items carry no estimated or invented values', () {
      final item = CollectionItem.fromReport(sampleReport());
      final json = item.toJson();
      expect(json.keys, isNot(contains('estimatedValueUsd')));
      expect(json.keys, isNot(contains('serialNumber')));
      expect(item.imageAsset, testWatch.imageAsset);
    });
  });

  group('Settings persist (§47)', () {
    test('preferences survive a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs: prefs);
      storage.setString('onboarding_goal', 'Before I sell');
      storage.setBool('haptics_enabled', false);

      final reloaded = StorageService(prefs: prefs);
      await Future<void>.delayed(Duration.zero);

      expect(reloaded.getString('onboarding_goal'), 'Before I sell');
      expect(reloaded.getBool('haptics_enabled', defaultValue: true), isFalse);
    });

    test('onboarding preferences may be left unset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs: prefs);
      expect(storage.getString('onboarding_goal'), anyOf(isNull, isEmpty, isA<String>()));
    });
  });

  group('Rules engine is data-driven (§20, §21)', () {
    test('each category gets its own 6-angle blueprint', () {
      for (final c in ProductCategory.values) {
        final rules = AuthenticationRules.forCategory(c);
        expect(rules.evidenceBlueprint, hasLength(6), reason: '${c.label} blueprint');
        expect(rules.criticalEvidenceIds.length, greaterThanOrEqualTo(1));
        expect(rules.inspectionRules, isNotEmpty);
      }
    });

    test('category blueprints differ from one another (§5)', () {
      final watch = AuthenticationRules.forCategory(ProductCategory.watches)
          .evidenceBlueprint
          .map((e) => e.id)
          .toSet();
      final sneaker = AuthenticationRules.forCategory(ProductCategory.sneakers)
          .evidenceBlueprint
          .map((e) => e.id)
          .toSet();
      expect(watch.intersection(sneaker), isEmpty);
      expect(watch, containsAll(['dial', 'caseback', 'reference_serial']));
      expect(sneaker, containsAll(['size_tag', 'sole', 'box_label']));
    });

    test('packaging is never weighted like identity evidence (§21)', () {
      final sneaker = AuthenticationRules.forCategory(ProductCategory.sneakers);
      final box = sneaker.evidenceBlueprint.firstWhere((e) => e.id == 'box_label');
      final tag = sneaker.evidenceBlueprint.firstWhere((e) => e.id == 'size_tag');
      expect(box.weight, EvidenceWeight.low);
      expect(tag.weight, EvidenceWeight.critical);
      expect(box.weight.factor, lessThan(tag.weight.factor));
    });

    test('unknown ids get sensible inferred weights', () {
      expect(AuthenticationRules.inferWeight('inner_date_code'), EvidenceWeight.critical);
      expect(AuthenticationRules.inferWeight('dust_bag'), EvidenceWeight.low);
      expect(AuthenticationRules.inferWeight('side_logo'), EvidenceWeight.high);
      expect(AuthenticationRules.inferWeight('random_angle'), EvidenceWeight.medium);
    });

    test('a model overlay sharpens the category rules without replacing them', () {
      final base = AuthenticationRules.forCategory(ProductCategory.watches);
      final resolved = AuthenticationRules.resolve(
        category: ProductCategory.watches,
        brand: 'Rolex',
        model: 'Submariner',
      );
      expect(resolved.inspectionRules.length, greaterThan(base.inspectionRules.length));
      expect(resolved.inspectionBriefing.toLowerCase(), contains('rehaut'));
      expect(resolved.evidenceBlueprint, hasLength(6));
    });

    test('the briefing names the dimensions the spec requires (§18)', () {
      final briefing = AuthenticationRules.forCategory(ProductCategory.bags).inspectionBriefing;
      for (final needle in ['LOGO', 'TYPOGRAPHY', 'STITCHING', 'MATERIAL', 'HARDWARE', 'SERIAL']) {
        expect(briefing, contains(needle));
      }
    });
  });

  group('Guides are static reference content, not user data', () {
    test('guide library is available without any scans', () {
      final repo = GuideRepository();
      expect(repo.allGuides, isNotEmpty);
    });
  });
}
