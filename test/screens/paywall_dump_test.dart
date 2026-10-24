// Premium paywall in every state (offerings loaded with a faked package list,
// loading, retry/unavailable, premium active), rendered at 390x844 and at
// 320x640 with text scale 1.3 (overflow = test failure). With
// LENZ_SCREEN_DUMP_DIR set, every frame is also written as a PNG:
//
//   LENZ_SCREEN_DUMP_DIR=/tmp/lenz_screens flutter test test/screens/paywall_dump_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:replica_detector/core/theme/app_theme.dart';
import 'package:replica_detector/services/revenue_cat_service.dart';
import 'package:replica_detector/viewmodels/profile_viewmodel.dart';
import 'package:replica_detector/views/paywall/premium_paywall_screen.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';
import 'package:shared_preferences/shared_preferences.dart';

final String? _dir = Platform.environment['LENZ_SCREEN_DUMP_DIR'];

Future<void> _loadFonts() async {
  final loader = FontLoader('Nunito');
  for (final f in const ['SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    final bytes = File('assets/fonts/Nunito-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

const _ctx = PresentedOfferingContext('default', null, null);

Package _pkg(String id, PackageType type, String price, double value, {IntroductoryPrice? intro}) {
  return Package(
    id,
    type,
    StoreProduct('lenz_$id', 'Lenz Pro', 'Lenz Pro', value, price, 'USD', introductoryPrice: intro),
    _ctx,
  );
}

Offerings _fakeOfferings({bool weekly = false, bool trialOnMonthly = false}) {
  const trial = IntroductoryPrice(0, '\$0.00', 'P3D', 1, PeriodUnit.day, 3);
  final annual = _pkg(
    '\$rc_annual',
    PackageType.annual,
    '\$49.99',
    49.99,
    intro: trialOnMonthly ? null : trial,
  );
  final monthly = _pkg('\$rc_monthly', PackageType.monthly, '\$9.99', 9.99, intro: trialOnMonthly ? trial : null);
  final week = _pkg('\$rc_weekly', PackageType.weekly, '\$3.99', 3.99);
  final offering = Offering(
    'default',
    'Default',
    const {},
    [annual, monthly, if (weekly) week],
    annual: annual,
    monthly: monthly,
  );
  return Offerings({'default': offering}, current: offering);
}

class _Size {
  const _Size(this.w, this.h, this.scale, this.tag);
  final double w, h, scale;
  final String tag;
}

const _sizes = [
  _Size(320, 568, 1, '_320x568'),
  _Size(375, 667, 1, '_375x667'),
  _Size(390, 844, 1, '_390x844'),
  _Size(430, 932, 1, '_430x932'),
  _Size(320, 568, 1.3, '_320x568_x13'),
];

Future<GlobalKey> _pump(
  WidgetTester tester,
  _Size s, {
  required Future<Offerings?> Function() loader,
  bool premium = false,
  bool eligible = true,
  String plan = 'Yearly Pro',
  String trialProduct = 'lenz_\$rc_annual',
}) async {
  SharedPreferences.setMockInitialValues({});
  RevenueCatService.isPremiumNotifier.value = premium;
  RevenueCatService.activePlanNotifier.value = premium ? plan : null;
  final vm = ProfileViewModel();

  tester.view.physicalSize = Size(s.w * 2, s.h * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(
    ChangeNotifierProvider<ProfileViewModel>.value(
      value: vm,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(s.scale)),
          child: RepaintBoundary(key: key, child: c!),
        ),
        home: PremiumPaywallScreen(
          onClose: () {},
          offeringsLoader: loader,
          introEligibilityChecker: (id) async => eligible && id == trialProduct,
        ),
      ),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return key;
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (_dir == null) return;
  debugDisableShadows = false;
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump(const Duration(milliseconds: 16));
}

void _expectSinglePage(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  // The page itself never scrolls (the legal sheet does, but it is closed).
  expect(find.byType(Scrollable), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  tearDown(() {
    RevenueCatService.isPremiumNotifier.value = false;
    RevenueCatService.activePlanNotifier.value = null;
  });

  for (final s in _sizes) {
    testWidgets('paywall trial eligible${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final key = await _pump(tester, s, loader: () async => _fakeOfferings(weekly: true));
      expect(find.text('\$49.99'), findsOneWidget);
      expect(find.text('\$9.99'), findsOneWidget);
      expect(find.text('\$3.99'), findsOneWidget);
      expect(find.text('Start 3-Day Free Trial'), findsOneWidget);
      expect(find.text('BEST VALUE'), findsOneWidget);
      _expectSinglePage(tester);
      await _shot(tester, key, 'paywall${s.tag}');

      await tester.tap(find.text('Monthly'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Continue with Monthly'), findsOneWidget);
      expect(find.textContaining('Free Trial'), findsNothing);
      _expectSinglePage(tester);

      // Billing details opens a sheet (scrolls inside only).
      await tester.tap(find.text('Billing details'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Questions? support@veradostudio.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shot(tester, key, 'paywall_billing${s.tag}');
    });

    testWidgets('paywall with the free trial on Monthly only${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final key = await _pump(
        tester,
        s,
        loader: () async => _fakeOfferings(trialOnMonthly: true),
        trialProduct: 'lenz_\$rc_monthly',
      );
      // Monthly is preselected and carries the trial; Yearly never mentions one.
      expect(find.text('Start 3-Day Free Trial'), findsOneWidget);
      expect(find.text('\$9.99'), findsOneWidget);
      expect(find.text('\$49.99'), findsOneWidget);
      expect(find.textContaining('free trial'), findsNothing, reason: 'the yearly card never mentions a trial');
      expect(find.textContaining('then \$9.99'), findsOneWidget);
      _expectSinglePage(tester);
      await _shot(tester, key, 'paywall_trial_monthly${s.tag}');

      await tester.tap(find.text('Yearly'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Continue with Yearly'), findsOneWidget);
      expect(find.text('Start 3-Day Free Trial'), findsNothing);
      expect(find.textContaining('\$49.99 per year'), findsOneWidget);
      _expectSinglePage(tester);
    });

    testWidgets('paywall not eligible${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final key = await _pump(tester, s, loader: () async => _fakeOfferings(), eligible: false);
      expect(find.textContaining('Free Trial'), findsNothing);
      expect(find.textContaining('free trial'), findsNothing);
      expect(find.text('Continue with Monthly'), findsOneWidget);
      _expectSinglePage(tester);
      await _shot(tester, key, 'paywall_noeligible${s.tag}');
    });

    testWidgets('paywall loading${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final never = Completer<Offerings?>();
      final key = await _pump(tester, s, loader: () => never.future);
      expect(find.text('Loading plans…'), findsWidgets);
      _expectSinglePage(tester);
      await _shot(tester, key, 'paywall_loading${s.tag}');
    });

    testWidgets('paywall offerings failed${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final key = await _pump(tester, s, loader: () async => null);
      expect(find.text("Couldn't load subscription plans"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Plans unavailable'), findsOneWidget);
      expect(find.textContaining('\$'), findsNothing);
      _expectSinglePage(tester);
      await _shot(tester, key, 'paywall_unavailable${s.tag}');
    });

    testWidgets('paywall premium active${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final key = await _pump(tester, s, loader: () async => _fakeOfferings(), premium: true);
      expect(find.text('Manage Subscription'), findsOneWidget);
      expect(find.text('Restore Purchases'), findsOneWidget);
      expect(find.textContaining('Switch to Yearly'), findsNothing, reason: 'a yearly subscriber has nothing to switch to');
      expect(find.textContaining('Free Trial'), findsNothing);
      _expectSinglePage(tester);
      await _shot(tester, key, 'paywall_active${s.tag}');
    });

    testWidgets('paywall monthly subscriber can switch to yearly, manage and restore${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final key = await _pump(tester, s, loader: () async => _fakeOfferings(), premium: true, plan: 'Monthly Pro');
      expect(find.text('Switch to Yearly · \$49.99/year'), findsOneWidget);
      expect(find.text('Manage Subscription'), findsOneWidget);
      expect(find.text('Restore Purchases'), findsOneWidget);
      expect(find.textContaining('Free Trial'), findsNothing);
      _expectSinglePage(tester);
      await _shot(tester, key, 'paywall_active_monthly${s.tag}');
    });
  }
}
