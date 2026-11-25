import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/errors/app_error.dart';
import 'package:replica_detector/services/auth_service.dart';
import 'package:replica_detector/services/revenue_cat_service.dart';
import 'package:replica_detector/services/storage_service.dart';
import 'package:replica_detector/views/scan/ai_consent_sheet.dart';
import 'package:replica_detector/widgets/common/legal_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_kit/ui_test_utils.dart';

/// Opens the consent sheet from a button and records what ensure() returned.
class _Harness extends StatefulWidget {
  const _Harness(this.storage);
  final StorageService storage;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool? result;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await AiConsent.ensure(context, widget.storage);
              setState(() => result = r);
            },
            child: const Text('scan'),
          ),
        ),
      );
}

Future<StorageService> _storage([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  // With prefs passed in, StorageService hydrates synchronously.
  return StorageService(prefs: prefs);
}

void main() {
  setUpAll(loadNunito);

  group('AI photo consent (5.1.2(i))', () {
    testWidgets('names Gemini and Cloudinary; Allow is remembered', (tester) async {
      final storage = await _storage();
      await tester.pumpWidget(MaterialApp(home: _Harness(storage)));
      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();

      expect(find.text('Allow photo analysis?'), findsOneWidget);
      expect(find.textContaining('Google Gemini'), findsOneWidget);
      expect(find.textContaining('Cloudinary'), findsOneWidget);
      expect(find.byType(LegalLinksText), findsOneWidget);

      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(state.result, isTrue);
      expect(AiConsent.isGiven(storage), isTrue);

      // Second scan: no sheet, straight through.
      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      expect(find.text('Allow photo analysis?'), findsNothing);
      expect(state.result, isTrue);
    });

    testWidgets('Not now blocks the scan and asks again next time', (tester) async {
      final storage = await _storage();
      await tester.pumpWidget(MaterialApp(home: _Harness(storage)));
      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(state.result, isFalse);
      expect(AiConsent.isGiven(storage), isFalse);

      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      expect(find.text('Allow photo analysis?'), findsOneWidget);
    });

    testWidgets('consent persisted earlier is loaded on launch', (tester) async {
      final storage = await _storage({AiConsent.kAiConsentKey: true});
      expect(AiConsent.isGiven(storage), isTrue);
    });

    testWidgets('fits a 320pt-wide phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = await _storage();
      await tester.pumpWidget(MaterialApp(home: _Harness(storage)));
      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Allow'), findsOneWidget);
    });
  });

  group('plan label', () {
    tearDown(() => RevenueCatService.activePlanNotifier.value = null);

    test('the neutral server name never becomes "Monthly Pro"', () {
      RevenueCatService.activePlanNotifier.value = null;
      expect(RevenueCatService.proPlanLabel('Lenz Pro'), 'Lenz Pro');
      expect(RevenueCatService.proPlanLabel('Yearly Pro'), 'Yearly Pro');
      expect(RevenueCatService.proPlanLabel('Monthly Pro'), 'Monthly Pro');
    });

    test('the live store plan wins', () {
      RevenueCatService.activePlanNotifier.value = 'Yearly Pro';
      expect(RevenueCatService.proPlanLabel('Lenz Pro'), 'Yearly Pro');
    });
  });

  group('Sign in with Apple nonce', () {
    test('nonce is random, 32 chars, and hashed with SHA-256', () {
      final a = AuthService.generateNonce();
      final b = AuthService.generateNonce();
      expect(a.length, 32);
      expect(a, isNot(b));
      expect(
        AuthService.sha256ofString('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('daily fair-use limit', () {
    test('is its own non-retryable error with no "upgrade" advice', () {
      final e = AppError.dailyLimit();
      expect(e.type, AppErrorType.quotaLimit);
      expect(e.isDailyLimit, isTrue);
      expect(e.message.toLowerCase(), isNot(contains('upgrade')));
      expect(e.recoveryAction!.toLowerCase(), isNot(contains('upgrade')));
      expect(AppError.quotaLimit().isDailyLimit, isFalse);
    });
  });
}
