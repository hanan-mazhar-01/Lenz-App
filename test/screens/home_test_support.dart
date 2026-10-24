// Shared fakes and pump helpers for the Home / History / Favorites /
// Category / shell screen tests.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:replica_detector/core/theme/app_theme.dart';
import 'package:replica_detector/models/authentication_result.dart';
import 'package:replica_detector/models/product.dart';
import 'package:replica_detector/models/user_profile.dart';
import 'package:replica_detector/repositories/authentication_repository.dart';
import 'package:replica_detector/repositories/category_repository.dart';
import 'package:replica_detector/repositories/gemini_authentication_repository.dart';
import 'package:replica_detector/repositories/history_repository.dart';
import 'package:replica_detector/services/auth_service.dart';
import 'package:replica_detector/services/storage_service.dart';
import 'package:replica_detector/viewmodels/favorites_viewmodel.dart';
import 'package:replica_detector/viewmodels/history_viewmodel.dart';
import 'package:replica_detector/viewmodels/home_viewmodel.dart';
import 'package:replica_detector/viewmodels/profile_viewmodel.dart';
import 'package:replica_detector/viewmodels/scan_flow_viewmodel.dart';
import 'package:replica_detector/widgets/cards/category_art.dart';
import 'package:replica_detector/widgets/lenz/lenz.dart';
import 'package:showcaseview/showcaseview.dart';

import '../support/fake_gemini.dart';

/// Where dump PNGs go (only when `LENZ_SCREENS_DUMP=1`).
const String kDumpDir =
    '/tmp/claude-1000/-home-hanan-Documents-Flutter-Flutter-practice-Verado-Studio-replica-detector/20c8dca2-5206-4d74-b31e-e62ce23c25e4/scratchpad/lenz_screens';
final bool kDump = Platform.environment['LENZ_SCREENS_DUMP'] == '1';

class FakeAuthService extends ChangeNotifier implements AuthService {
  FakeAuthService({this.anonymous = false});
  final bool anonymous;

  @override
  bool get isAnonymous => anonymous;
  @override
  String? get uid => 'test-uid';
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeProfileViewModel extends ChangeNotifier implements ProfileViewModel {
  FakeProfileViewModel(this._user);
  final UserProfile _user;

  @override
  UserProfile get user => _user;
  @override
  bool get isPremium => _user.isPremium;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

UserProfile profile({String name = 'Alex Morgan', bool premium = false, int scans = 3}) =>
    UserProfile(
      name: name,
      email: 'alex@example.com',
      planName: premium ? 'Lenz Pro' : 'Free Plan',
      scansRemaining: scans,
      isPremium: premium,
    );

AuthenticationReport report(
  String id,
  String name,
  String brand,
  ProductCategory cat,
  Verdict v, {
  int daysAgo = 0,
  bool fav = false,
  String strength = 'strong',
}) {
  return AuthenticationReport(
    id: id,
    product: Product(
      id: 'p$id',
      name: name,
      brand: brand,
      model: name,
      category: cat,
      imageAsset: '',
    ),
    verdict: v,
    overallScore: 0,
    quickSummaryPoints: const [],
    evidenceItems: const [],
    rationale: '',
    timestamp: DateTime.now().subtract(Duration(days: daysAgo, minutes: 5)),
    isFavorite: fav,
    engineVersion: '4.1',
    evidenceStrength: strength,
  );
}

List<AuthenticationReport> sampleReports() => [
  report(
    '1',
    'Neverfull MM',
    'Louis Vuitton',
    ProductCategory.bags,
    Verdict.likelyAuthentic,
    fav: true,
  ),
  report(
    '2',
    'Submariner Date',
    'Rolex',
    ProductCategory.watches,
    Verdict.likelyReplica,
    daysAgo: 1,
    strength: 'moderate',
  ),
  report(
    '3',
    'Air Jordan 1 High OG',
    'Nike',
    ProductCategory.sneakers,
    Verdict.likelyAuthentic,
    daysAgo: 5,
    fav: true,
  ),
  report(
    '4',
    'Classic Flap Medium',
    'Chanel',
    ProductCategory.bags,
    Verdict.inconclusive,
    daysAgo: 8,
    strength: 'limited',
  ),
  report(
    '5',
    'Ace Embroidered Sneaker',
    'Gucci',
    ProductCategory.sneakers,
    Verdict.likelyReplica,
    daysAgo: 13,
  ),
];

/// Registers the [ShowcaseView] the Home screen's tour targets need.
class TourHost extends StatefulWidget {
  const TourHost({super.key, required this.child});
  final Widget child;
  @override
  State<TourHost> createState() => _TourHostState();
}

class _TourHostState extends State<TourHost> {
  @override
  void initState() {
    super.initState();
    ShowcaseView.register();
  }

  // Not unregistered on dispose: a later pump in the same test registers
  // again (last registration wins) before this one is disposed.

  @override
  Widget build(BuildContext context) => widget.child;
}

class ScreenEnv {
  ScreenEnv({
    this.anonymous = false,
    UserProfile? user,
    List<AuthenticationReport> reports = const [],
  }) : auth = FakeAuthService(anonymous: anonymous),
       profileVm = FakeProfileViewModel(user ?? profile()),
       history = HistoryRepository() {
    for (final r in reports.reversed) {
      history.addReport(r);
    }
  }

  final bool anonymous;
  final FakeAuthService auth;
  final FakeProfileViewModel profileVm;
  final HistoryRepository history;

  Widget wrap(Widget child, {double textScale = 1, bool disableAnimations = false}) {
    final authRepo = AuthenticationRepository(
      geminiRepo: GeminiAuthenticationRepository(
        geminiService: FakeGeminiService(),
        imagePrep: FakeImagePreparationService(),
      ),
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: StorageService()),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<ProfileViewModel>.value(value: profileVm),
        ChangeNotifierProvider<HistoryRepository>.value(value: history),
        Provider<AuthenticationRepository>.value(value: authRepo),
        ChangeNotifierProvider<HomeViewModel>(
          create: (_) => HomeViewModel(historyRepo: history, categoryRepo: CategoryRepository()),
        ),
        ChangeNotifierProvider<HistoryViewModel>(
          create: (_) => HistoryViewModel(historyRepo: history),
        ),
        ChangeNotifierProvider<FavoritesViewModel>(
          create: (_) => FavoritesViewModel(historyRepo: history),
        ),
        ChangeNotifierProvider<ScanFlowViewModel>(
          create: (_) => ScanFlowViewModel(authRepo: authRepo, historyRepo: history),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: c!,
        ),
        home: TourHost(child: child),
      ),
    );
  }
}

/// Loads the character layers and decodes the category art so the first
/// frame shows real artwork.
Future<void> preloadArt(WidgetTester tester) async {
  await tester.runAsync(() => LenzAssets.instance.ensureAllLoaded());
}

Future<void> precacheArt(WidgetTester tester) async {
  final ctx = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final a in const [
      LenzCategoryArt.bags,
      LenzCategoryArt.sneakers,
      LenzCategoryArt.watches,
      LenzCategoryArt.clothing,
      LenzCategoryArt.accessories,
    ]) {
      await precacheImage(AssetImage(a), ctx);
    }
  });
}

/// Pumps [app] on a [size] logical-px phone and, when dumping, writes
/// `<name>.png` at 2x.
Future<GlobalKey> pumpScreen(
  WidgetTester tester,
  String name,
  Widget app, {
  Size size = const Size(390, 844),
  int settleMs = 2600,
  Future<void> Function()? after,
}) async {
  debugDisableShadows = !kDump;
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: app));
  await precacheArt(tester);
  await after?.call();
  for (var i = 0; i < settleMs ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await dumpNow(tester, key, name);
  return key;
}

/// Writes the current frame under [key] to `<name>.png` (when dumping).
Future<void> dumpNow(WidgetTester tester, GlobalKey key, String name) async {
  if (!kDump) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(kDumpDir).createSync(recursive: true);
    File('$kDumpDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// [testWidgets] that draws real shadows while dumping and restores the
/// painting debug flag before the framework checks it.
void screenTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}
