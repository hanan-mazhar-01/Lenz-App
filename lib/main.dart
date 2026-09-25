import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'repositories/authentication_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/collection_repository.dart';
import 'repositories/gemini_authentication_repository.dart';
import 'repositories/guide_repository.dart';
import 'repositories/history_repository.dart';
import 'services/auth_service.dart';
import 'services/cloudinary_service.dart';
import 'services/data_migration_service.dart';
import 'services/gemini_service.dart';
import 'services/haptics.dart';
import 'services/revenue_cat_service.dart';
import 'services/storage_service.dart';
import 'viewmodels/favorites_viewmodel.dart';
import 'viewmodels/history_viewmodel.dart';
import 'viewmodels/home_viewmodel.dart';
import 'viewmodels/onboarding_viewmodel.dart';
import 'viewmodels/profile_viewmodel.dart';
import 'viewmodels/scan_flow_viewmodel.dart';
import 'views/auth/auth_screen.dart';
import 'views/main_navigation_shell.dart';
import 'views/onboarding/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set iOS-native light transparent system UI overlay
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (!kIsWeb) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[main] Firebase initializeApp error: $e');
  }

  // Pre-fetch SharedPreferences before the widget tree builds. Without this,
  // StorageService's own internal load is async and OnboardingViewModel
  // reads storage synchronously in its constructor - it would always see
  // the hardcoded pre-hydration defaults (e.g. onboarding_completed: false)
  // on cold start, regardless of what's actually persisted, and never
  // re-reads afterward. Awaiting it here means StorageService starts
  // already hydrated.
  final prefs = await SharedPreferences.getInstance();

  // Initialize RevenueCat In-App Purchases
  await RevenueCatService.init();

  runApp(VeriCheckRoot(prefs: prefs));
}

class VeriCheckRoot extends StatelessWidget {
  final SharedPreferences prefs;

  const VeriCheckRoot({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Services & Repositories
        ChangeNotifierProvider<StorageService>(
          create: (_) {
            final storage = StorageService(prefs: prefs);
            // Every tap-handler across the app goes through Haptics instead
            // of calling HapticFeedback directly, so the "Haptic Feedback"
            // setting actually does something - this wires it up once, here,
            // rather than threading StorageService through dozens of files.
            Haptics.attach(storage);
            return storage;
          },
        ),
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        Provider<CloudinaryService>(create: (_) => CloudinaryService()),
        ChangeNotifierProvider<CategoryRepository>(
          create: (_) => CategoryRepository()..loadCategories(),
        ),
        ChangeNotifierProvider<HistoryRepository>(
          create: (_) => HistoryRepository()..loadPersistedReports(),
        ),
        ChangeNotifierProvider<GuideRepository>(
          create: (_) => GuideRepository(),
        ),
        ChangeNotifierProvider<CollectionRepository>(
          create: (_) => CollectionRepository()..load(),
        ),
        Provider<GeminiService>(create: (_) => GeminiService()),
        Provider<GeminiAuthenticationRepository>(
          create: (ctx) => GeminiAuthenticationRepository(
            geminiService: ctx.read<GeminiService>(),
          ),
        ),
        ProxyProvider<GeminiAuthenticationRepository, AuthenticationRepository>(
          update: (_, gemini, previous) =>
              previous ?? AuthenticationRepository(geminiRepo: gemini),
        ),

        // ViewModels
        ChangeNotifierProxyProvider<StorageService, OnboardingViewModel>(
          create: (ctx) => OnboardingViewModel(
            storageService: ctx.read<StorageService>(),
          ),
          update: (_, storage, previous) =>
              previous ?? OnboardingViewModel(storageService: storage),
        ),
        ChangeNotifierProxyProvider4<AuthenticationRepository, HistoryRepository, CategoryRepository, CloudinaryService, ScanFlowViewModel>(
          create: (ctx) => ScanFlowViewModel(
            authRepo: ctx.read<AuthenticationRepository>(),
            historyRepo: ctx.read<HistoryRepository>(),
            categoryRepo: ctx.read<CategoryRepository>(),
            cloudinaryService: ctx.read<CloudinaryService>(),
            storageService: ctx.read<StorageService>(),
          ),
          update: (ctx, authRepo, historyRepo, categoryRepo, cloudinary, previous) =>
              previous ??
              ScanFlowViewModel(
                authRepo: authRepo,
                historyRepo: historyRepo,
                categoryRepo: categoryRepo,
                cloudinaryService: cloudinary,
                storageService: ctx.read<StorageService>(),
              ),
        ),
        ChangeNotifierProxyProvider2<HistoryRepository, CategoryRepository, HomeViewModel>(
          create: (ctx) => HomeViewModel(
            historyRepo: ctx.read<HistoryRepository>(),
            categoryRepo: ctx.read<CategoryRepository>(),
          ),
          update: (_, historyRepo, categoryRepo, previous) =>
              previous ??
              HomeViewModel(
                historyRepo: historyRepo,
                categoryRepo: categoryRepo,
              ),
        ),
        ChangeNotifierProxyProvider<HistoryRepository, HistoryViewModel>(
          create: (ctx) => HistoryViewModel(historyRepo: ctx.read<HistoryRepository>()),
          update: (_, historyRepo, previous) =>
              previous ?? HistoryViewModel(historyRepo: historyRepo),
        ),
        ChangeNotifierProxyProvider<HistoryRepository, FavoritesViewModel>(
          create: (ctx) => FavoritesViewModel(historyRepo: ctx.read<HistoryRepository>()),
          update: (_, historyRepo, previous) =>
              previous ?? FavoritesViewModel(historyRepo: historyRepo),
        ),
        ChangeNotifierProvider<ProfileViewModel>(
          create: (_) => ProfileViewModel(),
        ),
      ],
      child: const VeriCheckApp(),
    );
  }
}

class VeriCheckApp extends StatefulWidget {
  const VeriCheckApp({super.key});

  @override
  State<VeriCheckApp> createState() => _VeriCheckAppState();
}

class _VeriCheckAppState extends State<VeriCheckApp> {
  String? _migratedUid;

  Future<void> _handlePostSignInMigration(String uid) async {
    await DataMigrationService.migrateOfflineDataIfNeeded(uid: uid);
    if (!mounted) return;
    context.read<HistoryRepository>().syncFromFirestore();
    context.read<CollectionRepository>().syncFromFirestore();
    context.read<CategoryRepository>().syncFromFirestore();
  }

  /// Wipes every locally-persisted, per-account cache on sign-out - including
  /// after account deletion, which also ends in a sign-out. Without this, a
  /// different account signing in afterward (or the same email re-registered
  /// post-deletion) "resurrects" the previous user's reports/collection/
  /// categories/profile info: DataMigrationService only skips pushing local
  /// data up to Firestore when that local cache is already empty, and it
  /// otherwise reads from the exact same SharedPreferences keys these
  /// repositories dual-write to.
  Future<void> _handleSignedOut(String previousUid) async {
    final orphaned = await context.read<HistoryRepository>().clearAllLocalData();
    if (!mounted) return;
    context.read<AuthenticationRepository>().deleteStoredImages(orphaned);
    await context.read<CollectionRepository>().clearAllLocalData();
    if (!mounted) return;
    await context.read<CategoryRepository>().clearAllLocalData();
    if (!mounted) return;
    await context.read<ProfileViewModel>().clearCachedProfile();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('vericheck_migrated_to_firestore_$previousUid');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final onboardingVm = context.watch<OnboardingViewModel>();
    final authService = context.watch<AuthService>();

    // Trigger offline-data migration + Firestore sync on sign-in, and the
    // local-cache wipe above on sign-out. Reset the guard on sign-out (uid
    // null) rather than only checking "uid changed": otherwise logging out
    // and back into the SAME account within one app session - the exact
    // logout -> login flow being tested - never re-triggers
    // syncFromFirestore, since uid matches the stale _migratedUid from
    // before the logout. That left a freshly-cleared local cache with
    // nothing to repopulate it.
    final uid = authService.uid;
    if (uid == null || uid.isEmpty) {
      if (_migratedUid != null) {
        final previousUid = _migratedUid!;
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleSignedOut(previousUid));
      }
      _migratedUid = null;
    } else if (uid != _migratedUid) {
      _migratedUid = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePostSignInMigration(uid));
    }

    Widget homeWidget;
    if (!authService.isInitialized) {
      // Firebase hasn't reported the real auth state yet (fresh cold start).
      // Without this gate, isAuthenticated reads as false for a moment and
      // the sign-in screen could flash before flipping to Home/Onboarding.
      homeWidget = const _SplashScreen();
    } else if (!onboardingVm.isCompleted) {
      homeWidget = OnboardingScreen(onFinish: onboardingVm.finishOnboarding);
    } else if (authService.isAuthenticated) {
      homeWidget = const MainNavigationShell();
    } else {
      homeWidget = AuthScreen(
        onContinueAsGuest: () => authService.signInAnonymously(),
      );
    }

    return MaterialApp(
      title: 'Lenz',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Light-only app: no darkTheme is registered, and themeMode is pinned
      // to light so the OS's dark-mode setting is never followed.
      themeMode: ThemeMode.light,
      home: homeWidget,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        // Clamp system accessibility text scale between 0.85 and 1.20 so text
        // remains legible on compact screens while preventing layout breakage.
        final clampedScaler = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.20,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedScaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Shown only for the brief moment before Firebase reports the real auth
/// state on a cold start, so the sign-in screen never has a chance to flash.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.deepForestGreen,
        ),
      ),
    );
  }
}
