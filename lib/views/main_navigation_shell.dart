import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';

import '../core/theme/app_colors.dart';
import '../models/authentication_result.dart';
import '../models/category_item.dart';
import '../repositories/history_repository.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/home_tour_service.dart';
import '../services/storage_service.dart';
import '../widgets/tour/home_tour_card.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../viewmodels/scan_flow_viewmodel.dart';
import '../widgets/navigation/ios_bottom_nav_bar.dart';
import 'category/category_browse_screen.dart';
import 'collection/collection_screen.dart';
import 'favorites/favorites_screen.dart';
import 'guides/guides_screen.dart';
import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'paywall/guest_paywall_screen.dart';
import 'profile/help_support_sheet.dart';
import 'profile/premium_screen.dart';
import 'profile/privacy_sheet.dart';
import 'profile/profile_screen.dart';
import 'profile/scan_credits_sheet.dart';
import 'report/authentication_report_view.dart';
import 'report/part_detail_view.dart';
import 'report/physical_detection_tips_view.dart';
import 'scan/analyzing_view.dart';
import '../models/product_identification.dart';
import 'scan/scan_validation_result_view.dart';
import 'scan/direct_scan_view.dart';
import 'scan/validating_photo_view.dart';
import 'scan/dynamic_evidence_view.dart';
import 'scan/guided_capture_view.dart';
import 'scan/identifying_view.dart';
import 'scan/photo_quality_view.dart';
import 'scan/scan_error_view.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentTab = 0;
  bool _isScanFlowActive = false;
  AuthenticationReport? _inspectedReport;
  CategoryItem? _inspectedCategory;
  bool _isPremiumModalActive = false;
  bool _isGuidesActive = false;
  bool _isCollectionActive = false;

  final BiometricService _biometricService = BiometricService();

  // Home-tour coach-mark targets, in step order (see HomeScreen.tourSteps).
  final GlobalKey _tourHeroKey = GlobalKey();
  final GlobalKey _tourBrowseKey = GlobalKey();
  final GlobalKey _tourRecentKey = GlobalKey();
  final GlobalKey _tourProfileKey = GlobalKey();
  final GlobalKey _tourNavKey = GlobalKey();

  // In-memory guard: prevents the first-time auto-show from firing more than
  // once per app session even if this widget rebuilds - the persisted
  // per-account flag (HomeTourService) is the actual source of truth for
  // "has this account ever seen the tour", this just stops a duplicate
  // presentation caused by navigation/rebuild timing within one session.
  bool _autoTourCheckStarted = false;
  bool _isTourActive = false;

  @override
  void initState() {
    super.initState();
    ShowcaseView.register(
      semanticEnable: true,
      enableAutoScroll: true,
      scrollDuration: const Duration(milliseconds: 180),
      onStart: (index, key) =>
          debugPrint('[HomeTour DEBUG] onStart index=$index key=$key'),
      onComplete: (index, key) =>
          debugPrint('[HomeTour DEBUG] onComplete index=$index key=$key'),
      onFinish: () {
        debugPrint('[HomeTour DEBUG] onFinish');
        _handleTourEnded();
      },
      onDismiss: (key) {
        debugPrint('[HomeTour DEBUG] onDismiss key=$key');
        _handleTourEnded();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeAutoShowHomeTour(),
    );
  }

  @override
  void dispose() {
    ShowcaseView.get().unregister();
    super.dispose();
  }

  Future<void> _maybeAutoShowHomeTour() async {
    if (_autoTourCheckStarted || !mounted) return;
    _autoTourCheckStarted = true;

    final uid = context.read<AuthService>().uid ?? '';
    final alreadySeen = await HomeTourService.hasSeenTour(uid);
    if (alreadySeen || !mounted) return;

    setState(() => _isTourActive = true);
    // Home's sections re-render a few times right after first mount as
    // Firestore listeners (profile/history/category) attach and their first
    // real snapshots arrive - starting the showcase mid-storm caused it to
    // silently race through several steps before anything was visible.
    // Giving that settling period a moment to finish first is a more
    // reliable fix than trying to outrun it with zero-duration animations.
    ShowcaseView.get().startShowCase([
      _tourHeroKey,
      _tourBrowseKey,
      _tourRecentKey,
      _tourProfileKey,
      _tourNavKey,
    ], delay: const Duration(milliseconds: 700));
  }

  /// Marks the tour seen for the current account whether it was completed
  /// (`onFinish`) or skipped/dismissed early (`onDismiss`) - both are
  /// "the user is done with this walkthrough" as far as auto-show is
  /// concerned. This also fires for a manual "?" replay; that's intentional
  /// (see the class doc on `_autoTourCheckStarted`) since a replay only ever
  /// happens after the account has already seen (or is currently seeing)
  /// the tour, so marking it seen again is a no-op in practice.
  void _handleTourEnded() {
    if (mounted) setState(() => _isTourActive = false);
    final uid = context.read<AuthService>().uid ?? '';
    HomeTourService.markTourSeen(uid);
  }

  void _openScanFlow() {
    final authService = context.read<AuthService>();
    final historyRepo = context.read<HistoryRepository>();
    final profileVm = context.read<ProfileViewModel>();

    // 1. Gated check: Guests are allowed 3 scans maximum before requiring account creation/sign in
    if (authService.isAnonymous &&
        (historyRepo.allReports.length >= 3 ||
            profileVm.user.scansRemaining <= 0)) {
      GuestPaywallScreen.show(context);
      return;
    }

    // 2. Registered users: credit/premium gate temporarily disabled - no
    // scan limit for signed-in accounts for now. Guests above still get 3
    // scans max. To re-enable, restore this check before starting the scan:
    //   if (!authService.isAnonymous && !profileVm.user.isPremium &&
    //       profileVm.user.scansRemaining <= 0) {
    //     setState(() => _isPremiumModalActive = true);
    //     return;
    //   }

    final scanVm = context.read<ScanFlowViewModel>();
    scanVm.startScan();
    setState(() {
      _isScanFlowActive = true;
      _inspectedReport = null;
      _inspectedCategory = null;
      _isGuidesActive = false;
      _isCollectionActive = false;
    });
  }

  void _closeScanFlow() {
    setState(() {
      _isScanFlowActive = false;
    });
  }

  Future<void> _openReport(AuthenticationReport report) async {
    final biometricRequired = context.read<StorageService>().getBool(
      'biometric_enabled',
      defaultValue: false,
    );

    if (biometricRequired) {
      final authenticated = await _biometricService.authenticate(
        reason: 'Unlock to view this authentication report',
      );
      if (!authenticated) return;
    }

    if (!mounted) return;
    setState(() {
      _inspectedReport = report;
    });
  }

  void _openCategory(CategoryItem category) {
    setState(() {
      _inspectedCategory = category;
    });
  }

  void _openPrivacySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const PrivacySecuritySheet(),
    );
  }

  void _openHelpSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const HelpSupportSheet(),
    );
  }

  void _openCreditsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ScanCreditsSheet(
        onOpenPremium: () => setState(() => _isPremiumModalActive = true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Premium Modal Layer
    if (_isPremiumModalActive) {
      return PremiumScreen(
        onClose: () => setState(() => _isPremiumModalActive = false),
      );
    }

    // 2. Guides Screen Layer
    if (_isGuidesActive) {
      return GuidesScreen(
        onBack: () => setState(() => _isGuidesActive = false),
      );
    }

    // 3. Collection Screen Layer
    if (_isCollectionActive) {
      return CollectionScreen(
        onBack: () => setState(() => _isCollectionActive = false),
        onScanItem: _openScanFlow,
      );
    }

    // 4. Active Authentication / Camera Scan Flow
    if (_isScanFlowActive) {
      return _buildActiveScanFlow(context);
    }

    // 5. Inspected Report Detail View (from Home / History / Favorites)
    if (_inspectedReport != null) {
      return AuthenticationReportView(
        report: _inspectedReport!,
        onSelectPart: (part) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PartDetailView(
                item: part,
                onBack: () => Navigator.of(context).pop(),
                onOpenDetectYourself: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PhysicalDetectionTipsView(
                        report: _inspectedReport!,
                        onBack: () => Navigator.of(context).pop(),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
        onOpenDetectYourself: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PhysicalDetectionTipsView(
                report: _inspectedReport!,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
          );
        },
        onToggleFavorite: () {
          context.read<HistoryRepository>().toggleFavorite(
            _inspectedReport!.id,
          );
          setState(() {
            _inspectedReport = _inspectedReport!.copyWith(
              isFavorite: !_inspectedReport!.isFavorite,
            );
          });
        },
        onDone: () => setState(() => _inspectedReport = null),
      );
    }

    // 6. Category Browse Screen
    if (_inspectedCategory != null) {
      return CategoryBrowseScreen(
        category: _inspectedCategory!,
        onOpenReport: _openReport,
        onBack: () => setState(() => _inspectedCategory = null),
        onStartScan: _openScanFlow,
      );
    }

    // 7. Main Tab Shell
    return PopScope(
      // While the Home tour is active, the system back gesture dismisses it
      // instead of its normal effect (matching Skip/barrier-tap behavior)
      // rather than doing nothing or exiting the app underneath the overlay.
      canPop: !_isTourActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isTourActive) ShowcaseView.get().dismiss();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            IndexedStack(
              index: _currentTab,
              children: [
                HomeScreen(
                  onStartScan: _openScanFlow,
                  onOpenReport: _openReport,
                  onOpenCategory: _openCategory,
                  onOpenProfile: () => setState(() => _currentTab = 4),
                  onOpenGuides: () => setState(() => _isGuidesActive = true),
                  onOpenHistory: () => setState(() => _currentTab = 2),
                  tourHeroKey: _tourHeroKey,
                  tourBrowseKey: _tourBrowseKey,
                  tourRecentKey: _tourRecentKey,
                  tourProfileKey: _tourProfileKey,
                  tourNavKey: _tourNavKey,
                ),
                const SizedBox.shrink(), // Tab 1 triggers direct scan
                HistoryScreen(
                  onOpenReport: _openReport,
                  onStartScan: _openScanFlow,
                ),
                FavoritesScreen(onOpenReport: _openReport),
                ProfileScreen(
                  onOpenPremium: () =>
                      setState(() => _isPremiumModalActive = true),
                  onOpenCollection: () =>
                      setState(() => _isCollectionActive = true),
                  onOpenPrivacy: _openPrivacySheet,
                  onOpenHelp: _openHelpSheet,
                  onOpenCredits: _openCreditsSheet,
                  onOpenHistory: () => setState(() => _currentTab = 2),
                  onOpenSaved: () => setState(() => _currentTab = 3),
                  onOpenGuestPaywall: () => GuestPaywallScreen.show(context),
                ),
              ],
            ),

            // Floating iOS Bottom Nav Bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Showcase.withWidget(
                key: _tourNavKey,
                container: HomeTourCard(
                  title: HomeScreen.tourSteps[4].title,
                  description: HomeScreen.tourSteps[4].description,
                  stepIndex: 4,
                  totalSteps: HomeScreen.tourSteps.length,
                ),
                targetBorderRadius: BorderRadius.circular(34),
                onBarrierClick: () => ShowcaseView.get().dismiss(),
                disableDefaultTargetGestures: true,
                disableMovingAnimation: true,
                tooltipPosition: TooltipPosition.top,
                child: IosBottomNavBar(
                  currentIndex: _currentTab,
                  onTap: (index) {
                    if (index == 1) {
                      _openScanFlow();
                    } else {
                      setState(() {
                        _inspectedReport = null;
                        _inspectedCategory = null;
                        _isGuidesActive = false;
                        _isCollectionActive = false;
                        _isPremiumModalActive = false;
                        _currentTab = index;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveScanFlow(BuildContext context) {
    final scanVm = context.watch<ScanFlowViewModel>();

    switch (scanVm.currentStep) {
      case ScanStep.directScan:
        return DirectScanView(
          onClose: _closeScanFlow,
          onCapture: (imagePath) =>
              scanVm.captureInitialPhoto(imagePath: imagePath),
        );

      case ScanStep.validationFeedback:
        final val = scanVm.validationResult;
        return ScanValidationResultView(
          capturedImagePath: scanVm.initialImagePath,
          status: val?.status ?? IdentificationStatus.notProduct,
          reason: val?.reason ?? 'unsupported_object',
          message: val?.message ?? 'No supported luxury product detected.',
          missingEvidence: val?.missingEvidence ?? const [],
          onTryAgain: scanVm.reset,
          onClose: _closeScanFlow,
        );

      case ScanStep.identifying:
      case ScanStep.itemIdentified:
        return IdentifyingView(
          scanState: scanVm.scanState,
          product: scanVm.currentProduct,
          capturedImagePath: scanVm.initialImagePath,
          evidenceCount: scanVm.totalEvidenceCount,
          onContinue: scanVm.proceedToEvidenceChecklist,
          onBack: _closeScanFlow,
        );

      case ScanStep.dynamicEvidence:
        return DynamicEvidenceView(
          product: scanVm.currentProduct!,
          evidenceItems: scanVm.evidenceItems,
          capturedImages: scanVm.capturedImagePaths,
          acceptedCount: scanVm.acceptedEvidenceCount,
          canAnalyze: scanVm.canAnalyze,
          onSelectPart: (index) => scanVm.startEvidenceCapture(index),
          onMarkUnavailable: scanVm.markEvidenceUnavailableAt,
          onClearEvidence: scanVm.clearEvidenceAt,
          onAnalyze: scanVm.finishAndAnalyzeNow,
          onBack: _closeScanFlow,
        );

      case ScanStep.guidedCapture:
        return GuidedCaptureView(
          currentItem: scanVm.currentEvidenceItem!,
          currentIndex: scanVm.currentEvidenceIndex,
          totalCount: scanVm.evidenceItems.length,
          onCapture: ([photoPath]) => scanVm.submitEvidencePhoto(photoPath),
          onSkip: scanVm.skipCurrentEvidence,
          onMarkUnavailable: scanVm.markCurrentEvidenceUnavailable,
          onBack: scanVm.backToEvidenceChecklist,
        );

      case ScanStep.validatingPhoto:
        return ValidatingPhotoView(item: scanVm.currentEvidenceItem);

      case ScanStep.photoQuality:
        return PhotoQualityView(
          item: scanVm.currentEvidenceItem!,
          photoPath: scanVm.pendingPhotoPath,
          validation: scanVm.pendingValidation!,
          onKeep: scanVm.acceptPendingPhoto,
          onKeepAnyway: scanVm.pendingValidation!.isOverridable
              ? () => scanVm.acceptPendingPhoto(force: true)
              : null,
          onRetake: scanVm.retakePendingPhoto,
          onChooseAnother: scanVm.retakePendingPhoto,
        );

      case ScanStep.analyzing:
        return AnalyzingView(
          items: scanVm.evidenceItems,
          capturedImages: scanVm.capturedImagePaths,
          product: scanVm.currentProduct,
          onBack: _closeScanFlow,
        );

      case ScanStep.authenticationReport:
        return AuthenticationReportView(
          report: scanVm.currentReport!,
          onSelectPart: scanVm.openPartDetail,
          onOpenDetectYourself: () => _openPhysicalTips(scanVm),
          onToggleFavorite: scanVm.toggleFavoriteCurrentReport,
          onCaptureMoreEvidence: scanVm.captureMoreEvidence,
          onDone: _closeScanFlow,
        );

      case ScanStep.partDetail:
        return PartDetailView(
          item: scanVm.selectedPart!,
          onBack: scanVm.closePartDetail,
          onOpenDetectYourself: () => _openPhysicalTips(scanVm),
        );

      case ScanStep.error:
        return ScanErrorView(
          errorMessage: scanVm.errorMessage ?? "We couldn't finish the check.",
          appError: scanVm.appError,
          onRetry: scanVm.retryLastAction,
          onCancel: _closeScanFlow,
        );
    }
  }

  void _openPhysicalTips(ScanFlowViewModel scanVm) {
    final report = scanVm.currentReport;
    if (report == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhysicalDetectionTipsView(
          report: report,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
