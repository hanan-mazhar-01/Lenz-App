// Launch + auth screens (splash, onboarding, auth, forgot-password sheet,
// guest paywall): behaviour + no-overflow checks on a 320x640 phone at text
// scale 1.3. With LENZ_SCREEN_DUMP=<dir> it also writes PNG renders at
// 390x844 @2x and 320x640 @2x for comparison with the prototype refs:
//
//   LENZ_SCREEN_DUMP=/path/to/lenz_screens flutter test test/screens/launch_screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as flutter_test show testWidgets;
import 'package:provider/provider.dart';
import 'package:replica_detector/core/theme/app_theme.dart';
import 'package:replica_detector/models/user_profile.dart';
import 'package:replica_detector/services/auth_service.dart';
import 'package:replica_detector/viewmodels/profile_viewmodel.dart';
import 'package:replica_detector/views/auth/auth_screen.dart';
import 'package:replica_detector/views/onboarding/first_screen_view.dart';
import 'package:replica_detector/views/paywall/guest_paywall_screen.dart';
import 'package:replica_detector/views/splash/splash_screen.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';

final String? _dumpDir = Platform.environment['LENZ_SCREEN_DUMP'];

class _FakeAuth extends ChangeNotifier implements AuthService {
  bool loading = false;
  String? error;
  String? nextError;
  int emailSignIns = 0;

  @override
  bool get isLoading => loading;
  @override
  bool get guestScansAlreadyUsedOnDevice => false;
  @override
  bool get freeScansAlreadyUsedOnDevice => false;
  @override
  String? get authError => error;
  @override
  bool get isAuthenticated => true;

  @override
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    emailSignIns++;
    error = nextError;
    notifyListeners();
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfile extends ChangeNotifier implements ProfileViewModel {
  _FakeProfile(this.remaining);
  final int remaining;

  @override
  UserProfile get user => UserProfile(
    name: 'Guest Collector',
    email: '',
    planName: 'Guest Plan',
    scansRemaining: remaining,
    isPremium: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _loadFonts() async {
  final loader = FontLoader('Nunito');
  for (final f in const ['SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    final bytes = File('assets/fonts/Nunito-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

final _boundary = GlobalKey();

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required Size size,
  double dpr = 1,
  double textScale = 1.3,
  _FakeAuth? auth,
  int remaining = 0,
}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth ?? _FakeAuth()),
        ChangeNotifierProvider<ProfileViewModel>.value(value: _FakeProfile(remaining)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: _boundary, child: c!),
        ),
        home: screen,
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester, [int ms = 2500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_dumpDir == null) return;
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await b.toImage(pixelRatio: tester.view.devicePixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dumpDir!).createSync(recursive: true);
    File('$_dumpDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Sizes rendered per screen: the overflow check (small phone, text 1.3) and,
/// when dumping, the 390x844 reference size.
List<(String, Size, double, double)> get _variants => [
  ('320', const Size(320, 640), _dumpDir == null ? 1 : 2, 1.3),
  if (_dumpDir != null) ('390', const Size(390, 844), 2, 1.0),
];

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  // Shadows are drawn only for the PNG dumps; the flag must be restored
  // inside the test body (invariants are checked before tearDown).
  void testWidgets(String name, Future<void> Function(WidgetTester) body) {
    flutter_test.testWidgets(name, (tester) async {
      debugDisableShadows = _dumpDir == null;
      try {
        await body(tester);
      } finally {
        debugDisableShadows = true;
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> loadAssets(WidgetTester tester) async {
    await tester.runAsync(() async {
      await LenzAssets.instance.ensureAllLoaded();
      await LenzAssets.instance.ensureIconLoaded();
    });
  }

  testWidgets('splash: timeline renders, tap calls onSkip', (tester) async {
    await loadAssets(tester);
    expect(SplashScreen.totalDuration, const Duration(milliseconds: 4500));
    for (final v in _variants) {
      for (final t in const [400, 1000, 2000, 3500]) {
        var skipped = 0;
        await _pump(
          tester,
          SplashScreen(
            startAt: Duration(milliseconds: t),
            onSkip: () => skipped++,
          ),
          size: v.$2,
          dpr: v.$3,
          textScale: v.$4,
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
        await _shot(tester, 'splash_t${t}_${v.$1}');
        await tester.tap(find.byType(SplashScreen));
        expect(skipped, 1);
        await _unmount(tester);
      }
    }
  });

  testWidgets('onboarding: three pages, next / get started / skip', (tester) async {
    await loadAssets(tester);
    for (final v in _variants) {
      for (var p = 0; p < 3; p++) {
        await _pump(
          tester,
          FirstScreenView(initialPage: p),
          size: v.$2,
          dpr: v.$3,
          textScale: v.$4,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _shot(tester, 'onboarding_${p + 1}_${v.$1}');
        await _unmount(tester);
      }
    }

    var started = 0, skipped = 0;
    await _pump(
      tester,
      FirstScreenView(onGetStarted: () => started++, onSkip: () => skipped++),
      size: const Size(320, 640),
    );
    await _settle(tester, 1500);
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await _settle(tester, 1000);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('I tell you exactly what to capture'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await _settle(tester, 1000);
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    expect(started, 1);
    await tester.tap(find.text('Skip'));
    await tester.tap(find.text('I already have an account'));
    expect(skipped, 2);
    await _unmount(tester);
  });

  testWidgets('auth: sign in, sign up, shy password, inline error', (tester) async {
    await loadAssets(tester);
    for (final v in _variants) {
      for (final ios in const [true, false]) {
        debugDefaultTargetPlatformOverride = ios ? TargetPlatform.iOS : TargetPlatform.android;
        final auth = _FakeAuth();
        final tag = '${ios ? 'ios' : 'android'}_${v.$1}';
        await _pump(
          tester,
          AuthScreen(onContinueAsGuest: () {}),
          size: v.$2,
          dpr: v.$3,
          textScale: v.$4,
          auth: auth,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Apple'), ios ? findsOneWidget : findsNothing);
        expect(find.text('Google'), findsOneWidget);
        expect(find.text('Continue as guest'), findsOneWidget);
        await _shot(tester, 'auth_signin_$tag');

        if (ios) {
          // Password focus -> Lenz closes his eyes.
          await tester.tap(find.byType(TextField).last);
          await _settle(tester, 1500);
          expect(find.text('No peeking, I promise.'), findsOneWidget);
          await _shot(tester, 'auth_shy_$tag');
          FocusManager.instance.primaryFocus?.unfocus();
          await _settle(tester, 600);

          // Empty submit -> inline error.
          await tester.ensureVisible(find.text('Sign in').last);
          await tester.tap(find.text('Sign in').last);
          await _settle(tester, 1200);
          expect(find.text('Please enter both email and password.'), findsOneWidget);
          await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, 600));
          await _settle(tester, 600);
          await _shot(tester, 'auth_error_$tag');

          // Switch to sign up.
          await tester.tap(find.text('Create account').first);
          await _settle(tester, 1500);
          expect(find.text('Full name'), findsOneWidget);
          expect(find.text("Let's set you up!"), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _shot(tester, 'auth_signup_$tag');
        }
        await _unmount(tester);
      }
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('auth: server error string shown inline', (tester) async {
    await loadAssets(tester);
    final auth = _FakeAuth()..nextError = 'Incorrect password. Please try again.';
    await _pump(tester, const AuthScreen(), size: const Size(320, 640), auth: auth);
    await _settle(tester, 1500);
    await tester.enterText(find.byType(TextField).first, 'a@b.co');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.ensureVisible(find.text('Sign in').last);
    await tester.tap(find.text('Sign in').last);
    await _settle(tester, 800);
    expect(auth.emailSignIns, 1);
    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('forgot password sheet', (tester) async {
    await loadAssets(tester);
    for (final v in _variants) {
      await _pump(tester, const AuthScreen(), size: v.$2, dpr: v.$3, textScale: v.$4);
      await _settle(tester, 1500);
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await _settle(tester, 2000);
      expect(find.text('Reset your password'), findsOneWidget);
      expect(find.text('Send reset link'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shot(tester, 'forgot_${v.$1}');
      await tester.tap(find.text('Send reset link'));
      await _settle(tester, 800);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await _unmount(tester);
    }
  });

  testWidgets('guest paywall', (tester) async {
    await loadAssets(tester);
    for (final v in _variants) {
      for (final ios in const [true, false]) {
        await _pump(
          tester,
          GuestPaywallScreen(showAppleOverride: ios),
          size: v.$2,
          dpr: v.$3,
          textScale: v.$4,
          remaining: 0,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('3 of 3 guest scans used'), findsOneWidget);
        expect(find.text('Free scans with your account'), findsOneWidget);
        expect(find.text('Apple'), ios ? findsOneWidget : findsNothing);
        await _shot(tester, 'guest_paywall_${ios ? 'ios' : 'android'}_${v.$1}');
        if (!ios) {
          await tester.ensureVisible(find.text('Continue with email'));
          await tester.tap(find.text('Continue with email'));
          await _settle(tester, 1200);
          expect(find.text('Your name'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _shot(tester, 'guest_paywall_email_${v.$1}');
        }
        await _unmount(tester);
      }
    }
  });
}
