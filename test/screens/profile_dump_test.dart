// Profile tab + its sheets and confirm sheets, rendered at 390x844 and at
// 320x640 with text scale 1.3 (overflow = test failure). With
// LENZ_SCREEN_DUMP_DIR set, every frame is also written as a PNG for visual
// comparison with the prototype references:
//
//   LENZ_SCREEN_DUMP_DIR=/tmp/lenz_screens flutter test test/screens/profile_dump_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:replica_detector/core/theme/app_theme.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/services/auth_service.dart';
import 'package:replica_detector/services/revenue_cat_service.dart';
import 'package:replica_detector/viewmodels/profile_viewmodel.dart';
import 'package:replica_detector/views/profile/help_support_sheet.dart';
import 'package:replica_detector/views/profile/privacy_sheet.dart';
import 'package:replica_detector/views/profile/profile_screen.dart';
import 'package:replica_detector/views/paywall/guest_paywall_screen.dart';
import 'package:replica_detector/views/profile/scan_credits_sheet.dart';
import 'package:replica_detector/views/profile/terms_sheet.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';
import 'package:shared_preferences/shared_preferences.dart';

final String? _dir = Platform.environment['LENZ_SCREEN_DUMP_DIR'];

class _FakeAuth extends ChangeNotifier implements AuthService {
  _FakeAuth({required this.anonymous});
  final bool anonymous;

  @override
  bool get isAnonymous => anonymous;
  @override
  User? get currentUser => null;
  @override
  bool get isLoading => false;
  @override
  bool get guestScansAlreadyUsedOnDevice => false;
  @override
  bool get freeScansAlreadyUsedOnDevice => false;
  @override
  String? get authError => null;
  @override
  Future<void> signOut() async {}

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

enum _User { guest, free, premium }

class _Size {
  const _Size(this.w, this.h, this.scale, this.tag);
  final double w, h, scale;
  final String tag;
}

const _sizes = [_Size(390, 844, 1, ''), _Size(320, 640, 1.3, '_se')];

Future<(ProfileViewModel, GlobalKey)> _pumpProfile(WidgetTester tester, _User kind, _Size s) async {
  SharedPreferences.setMockInitialValues({
    if (kind != _User.guest) 'user_profile_name': 'Sam Rivera',
    if (kind != _User.guest) 'user_profile_email': 'sam@example.com',
    'user_profile_scans_remaining': kind == _User.guest ? 3 : 6,
  });
  RevenueCatService.isPremiumNotifier.value = kind == _User.premium;
  RevenueCatService.activePlanNotifier.value = kind == _User.premium ? 'Yearly Pro' : null;

  final vm = ProfileViewModel();
  final history = HistoryRepository();
  final auth = _FakeAuth(anonymous: kind == _User.guest);

  tester.view.physicalSize = Size(s.w * 2, s.h * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileViewModel>.value(value: vm),
        ChangeNotifierProvider<HistoryRepository>.value(value: history),
        ChangeNotifierProvider<AuthService>.value(value: auth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(s.scale)),
          child: RepaintBoundary(key: key, child: c!),
        ),
        home: ProfileScreen(
          onOpenPremium: () {},
          onOpenPrivacy: () {},
          onOpenHelp: () {},
          onOpenCredits: () {},
          onOpenTerms: () {},
          onOpenHistory: () {},
          onOpenFavorites: () {},
          onOpenGuestPaywall: () {},
        ),
      ),
    ),
  );
  // Let the cached profile load from (mock) SharedPreferences.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await _settle(tester);
  return (vm, key);
}

Future<void> _settle(WidgetTester tester, {int ms = 2600}) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (_dir == null) return;
  // flutter_test disables blurred shadows; draw them for the dump frame only.
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

Future<void> _openSheet(WidgetTester tester, WidgetBuilder builder) async {
  final ctx = tester.element(find.byType(ProfileScreen));
  showModalBottomSheet(
    context: ctx,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: builder,
  );
  await _settle(tester, ms: 2200);
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await _settle(tester, ms: 600);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  tearDown(() {
    RevenueCatService.isPremiumNotifier.value = false;
    RevenueCatService.activePlanNotifier.value = null;
  });

  for (final s in _sizes) {
    for (final kind in _User.values) {
      testWidgets('profile ${kind.name}${s.tag}', (tester) async {
        await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
        final (_, key) = await _pumpProfile(tester, kind, s);

        // Guests never see Pro; signed-in free users get the gold upgrade.
        expect(
          find.text('Upgrade to Lenz Pro'),
          kind == _User.free ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Sign In / Create Account'),
          kind == _User.guest ? findsWidgets : findsNothing,
        );
        expect(
          find.text('Manage subscription'),
          kind == _User.premium ? findsOneWidget : findsNothing,
        );
        expect(find.text('Favorites'), findsOneWidget);
        expect(find.text('Saved Reports'), findsNothing);
        await _shot(tester, key, 'profile_${kind.name}${s.tag}');

        // Scroll to the bottom section (support rows + log out / delete).
        await _scrollTo(tester, find.text(kind == _User.guest ? 'Terms of service' : 'Delete account'));
        expect(find.text('Terms of service'), findsOneWidget);
        await _shot(tester, key, 'profile_${kind.name}_bottom${s.tag}');
      });
    }

    testWidgets('profile sheets${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final (_, key) = await _pumpProfile(tester, _User.free, s);

      Future<void> sheet(String name, WidgetBuilder b) async {
        await _openSheet(tester, b);
        await _shot(tester, key, 'sheet_$name${s.tag}');
        Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
        await _settle(tester, ms: 800);
      }

      await sheet('help', (_) => const HelpSupportSheet());
      await sheet('privacy', (_) => const PrivacySecuritySheet());
      await sheet('terms', (_) => const TermsOfServiceSheet());
      await sheet('credits', (_) => ScanCreditsSheet(onOpenPremium: () {}));
    });

    testWidgets('profile credits sheet guest + premium${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final (_, key) = await _pumpProfile(tester, _User.guest, s);
      await _openSheet(tester, (_) => ScanCreditsSheet(onOpenPremium: () {}));
      expect(find.text('Upgrade for unlimited scans'), findsNothing);
      await _shot(tester, key, 'sheet_credits_guest${s.tag}');
      Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
      await _settle(tester, ms: 800);

      final (_, key2) = await _pumpProfile(tester, _User.premium, s);
      await _openSheet(tester, (_) => ScanCreditsSheet(onOpenPremium: () {}));
      expect(find.text('Upgrade for unlimited scans'), findsNothing);
      await _shot(tester, key2, 'sheet_credits_premium${s.tag}');
    });

    testWidgets('guest credits sheet button opens the account paywall${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      await _pumpProfile(tester, _User.guest, s);
      await _openSheet(tester, (_) => ScanCreditsSheet(onOpenPremium: () {}));
      await tester.tap(find.text('Sign In / Create Account').last);
      await _settle(tester, ms: 1500);
      expect(find.byType(GuestPaywallScreen), findsOneWidget);
    });

    testWidgets('guest has no Log out or Delete account; a signed-in user has both${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      await _pumpProfile(tester, _User.guest, s);
      expect(find.text('Log out', skipOffstage: false), findsNothing);
      expect(find.text('Delete account', skipOffstage: false), findsNothing);

      await _pumpProfile(tester, _User.free, s);
      expect(find.text('Log out', skipOffstage: false), findsOneWidget);
      expect(find.text('Delete account', skipOffstage: false), findsOneWidget);
    });

    testWidgets('profile confirm + edit sheets${s.tag}', (tester) async {
      await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
      final (_, key) = await _pumpProfile(tester, _User.free, s);

      await _scrollTo(tester, find.text('Delete account'));
      await tester.tap(find.text('Log out'));
      await _settle(tester, ms: 2200);
      expect(find.text('Log out?'), findsOneWidget);
      await _shot(tester, key, 'confirm_logout${s.tag}');
      await tester.tap(find.text('Cancel'));
      await _settle(tester, ms: 800);

      await tester.tap(find.text('Delete account'));
      await _settle(tester, ms: 2200);
      expect(find.text('Delete account?'), findsOneWidget);
      await _shot(tester, key, 'confirm_delete${s.tag}');
      await tester.tap(find.text('Cancel'));
      await _settle(tester, ms: 800);

      await _scrollTo(tester, find.text('Sam Rivera'));
      await tester.tap(find.text('Sam Rivera'));
      await _settle(tester, ms: 2200);
      expect(find.text('Edit profile'), findsOneWidget);
      await _shot(tester, key, 'sheet_edit_profile${s.tag}');
    });
  }
}
