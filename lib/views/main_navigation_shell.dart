import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';

import '../core/theme/lenz_page_transitions.dart';
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
import '../widgets/ui/ui.dart';
import 'category/category_browse_screen.dart';
import 'favorites/favorites_screen.dart';
import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'paywall/guest_paywall_screen.dart';
import 'profile/help_support_sheet.dart';
import 'profile/premium_screen.dart';
import 'profile/privacy_sheet.dart';
import 'profile/profile_screen.dart';
import 'profile/terms_sheet.dart';
import 'profile/scan_credits_sheet.dart';
import 'report/authentication_report_view.dart';
import 'report/part_detail_view.dart';
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

/// Tab pages, in the order of [LenzTabBar] (the centre scan button is not a
/// page; it calls `_openScanFlow`).
abstract final class _Tab {
  static const int home = 0;
  static const int history = 1;
  static const int favorites = 2;
  static const int profile = 3;
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentTab = _Tab.home;
  bool _isScanFlowActive = false;
  AuthenticationReport? _inspectedReport;
  CategoryItem? _inspectedCategory;
  bool _isPremiumModalActive = false;

  final BiometricService _biometricService = BiometricService();

  // Home-tour coach-mark targets, in step order (see HomeScreen.tourSteps).
  final GlobalKey _tourHeroKey = GlobalKey();
  final GlobalKey _tourBrowseKey = GlobalKey();
  final GlobalKey _tourRecentKey = GlobalKey();
  final GlobalKey _tourProfileKey = GlobalKey();
  final GlobalKey _tourNavKey = GlobalKey();

  /// The tour target currently in the spotlight (presentation only: draws
  /// the white ring around the spotlight hole).
  final ValueNotifier<GlobalKey?> _activeTourTarget = ValueNotifier(null);

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
      onStart: (index, key) {
        if (kDebugMode) debugPrint('[HomeTour] onStart index=$index key=$key');
        _activeTourTarget.value = key;
      },
      onComplete: (index, key) {
        if (kDebugMode) debugPrint('[HomeTour] onComplete index=$index key=$key');
      },
      onFinish: () {
        if (kDebugMode) debugPrint('[HomeTour] onFinish');
        _handleTourEnded();
      },
      onDismiss: (key) {
        if (kDebugMode) debugPrint('[HomeTour] onDismiss key=$key');
        _handleTourEnded();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoShowHomeTour());
  }

  @override
  void dispose() {
    ShowcaseView.get().unregister();
    _activeTourTarget.dispose();
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
    _activeTourTarget.value = null;
    if (mounted) setState(() => _isTourActive = false);
    final uid = context.read<AuthService>().uid ?? '';
    HomeTourService.markTourSeen(uid);
  }

  void _openScanFlow() {
    final authService = context.read<AuthService>();
    final profileVm = context.read<ProfileViewModel>();

    // 1. Gated check: Guests are allowed 3 scans maximum before requiring account creation/sign in
    // (counted from the scan balance: guest scans are not kept in History).
    if (authService.isAnonymous && profileVm.user.scansRemaining <= 0) {
      GuestPaywallScreen.show(context);
      return;
    }

    // 2. Registered users: require Pro subscription if user runs out of free scans
    if (!authService.isAnonymous &&
        !profileVm.user.isPremium &&
        profileVm.user.scansRemaining <= 0) {
      setState(() => _isPremiumModalActive = true);
      return;
    }

    final scanVm = context.read<ScanFlowViewModel>();
    // Only a signed-in account keeps its reports (History / Favorites).
    scanVm.saveReports = !authService.isAnonymous;
    // The scan balance is charged by the server (when the final analysis is
    // run) and arrives through the profile listener, so nothing is counted
    // down here: counting locally as well would charge twice.
    scanVm.onScanComplete = null;
    scanVm.startScan();
    setState(() {
      _isScanFlowActive = true;
      _inspectedReport = null;
      _inspectedCategory = null;
    });
  }

  void _closeScanFlow() {
    // If analysis is still running in the background, discard its result
    // instead of letting it silently finish, save to history, and charge
    // a scan credit after the user has already left.
    context.read<ScanFlowViewModel>().abandonAnalysisIfRunning();
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

  void _openTermsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const TermsOfServiceSheet(),
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
      builder: (_) =>
          ScanCreditsSheet(onOpenPremium: () => setState(() => _isPremiumModalActive = true)),
    );
  }

  void _selectTab(int index) {
    setState(() {
      _inspectedReport = null;
      _inspectedCategory = null;
      _isPremiumModalActive = false;
      _currentTab = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Full-screen layers stack above the tabs in the same priority the
    // previous shell used (premium > scan flow > report > category): the
    // top-most active one is what the user sees. Each slides/zooms in with
    // the prototype's transition and plays it in reverse when closed.
    final layers = <_LayerSpec>[
      _LayerSpec(id: 'tabs', kind: LenzRouteKind.fade, child: _buildTabs(context)),
      if (_inspectedCategory != null)
        _LayerSpec(
          id: 'category',
          kind: LenzRouteKind.forward,
          child: CategoryBrowseScreen(
            category: _inspectedCategory!,
            onOpenReport: _openReport,
            onBack: () => setState(() => _inspectedCategory = null),
            onStartScan: _openScanFlow,
          ),
        ),
      if (_inspectedReport != null)
        _LayerSpec(
          id: 'report',
          kind: LenzRouteKind.forward,
          child: _buildInspectedReport(context),
        ),
      if (_isScanFlowActive)
        _LayerSpec(
          id: 'scan',
          kind: LenzRouteKind.modalUp,
          // Intercept the Android back gesture/button so it goes through the
          // same close path as the in-app back buttons (credit/history-safe),
          // instead of exiting or backgrounding the app mid-scan.
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              // A paywall opened over the scan flow takes the back press first.
              if (!didPop && !_isPremiumModalActive) _closeScanFlow();
            },
            child: _ScanStepSwitcher(
              stepKey: _scanStepGroup(context.watch<ScanFlowViewModel>().currentStep),
              kind: _scanStepKind(context.watch<ScanFlowViewModel>().currentStep),
              child: _buildActiveScanFlow(context),
            ),
          ),
        ),
      if (_isPremiumModalActive)
        _LayerSpec(
          id: 'premium',
          kind: LenzRouteKind.modalUp,
          child: PremiumScreen(onClose: () => setState(() => _isPremiumModalActive = false)),
        ),
    ];
    final onTabs = layers.length == 1;
    // Spotlight for the tour's tab-bar step: the whole docked bar incl. the scan button.
    final navHole = EdgeInsets.zero;

    return PopScope(
      // System back closes the top-most layer, then returns to Home, and only
      // leaves the app from the Home tab. (The scan flow and the Home tour
      // have their own handlers above.)
      canPop: onTabs && _currentTab == _Tab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isPremiumModalActive) {
          setState(() => _isPremiumModalActive = false);
        } else if (_isScanFlowActive) {
          // handled by the scan flow's own PopScope
        } else if (_inspectedReport != null) {
          setState(() => _inspectedReport = null);
        } else if (_inspectedCategory != null) {
          setState(() => _inspectedCategory = null);
        } else if (_currentTab != _Tab.home) {
          _selectTab(_Tab.home);
        }
      },
      child: Scaffold(
        backgroundColor: LenzColors.ivory,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(child: _LayerStack(layers: layers)),
            // Floating Lenz tab bar: slides away (translateY + fade) whenever a
            // full-screen layer covers the tabs.
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
                targetBorderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                targetPadding: navHole,
                overlayColor: HomeTourStyle.overlayColor,
                overlayOpacity: HomeTourStyle.overlayOpacity,
                onBarrierClick: () => ShowcaseView.get().dismiss(),
                disableDefaultTargetGestures: true,
                disableMovingAnimation: true,
                tooltipPosition: TooltipPosition.top,
                child: HomeTourRing(
                  target: _tourNavKey,
                  active: _activeTourTarget,
                  radius: 30,
                  outset: navHole,
                  child: LenzTabBar(
                    currentIndex: _currentTab,
                    hidden: !onTabs,
                    onTab: _selectTab,
                    onScan: _openScanFlow,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    return PopScope(
      // While the Home tour is active, the system back gesture dismisses it
      // instead of its normal effect (matching Skip/barrier-tap behavior)
      // rather than doing nothing or exiting the app underneath the overlay.
      canPop: !_isTourActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isTourActive) ShowcaseView.get().dismiss();
      },
      child: _TabFade(
        index: _currentTab,
        // Every tab stays alive, but only the visible one may run animations:
        // TickerMode mutes the Lenz characters / blobs of the hidden tabs.
        child: LenzEntranceScope(
          // Tabs are revealed by the tab cross-fade only; their own staggered
          // entrance would play a second animation on top of it.
          always: true,
          child: IndexedStack(
            index: _currentTab,
            children: [
              for (final (i, tab) in <Widget>[
                HomeScreen(
                  onStartScan: _openScanFlow,
                  onOpenReport: _openReport,
                  onOpenCategory: _openCategory,
                  onOpenProfile: () => setState(() => _currentTab = _Tab.profile),
                  onOpenPremium: () => setState(() => _isPremiumModalActive = true),
                  onOpenHistory: () => setState(() => _currentTab = _Tab.history),
                  tourHeroKey: _tourHeroKey,
                  tourBrowseKey: _tourBrowseKey,
                  tourRecentKey: _tourRecentKey,
                  tourProfileKey: _tourProfileKey,
                  tourNavKey: _tourNavKey,
                  activeTourTarget: _activeTourTarget,
                ),
                HistoryScreen(onOpenReport: _openReport, onStartScan: _openScanFlow),
                FavoritesScreen(onOpenReport: _openReport),
                ProfileScreen(
                  onOpenPremium: () => setState(() => _isPremiumModalActive = true),
                  onOpenPrivacy: _openPrivacySheet,
                  onOpenTerms: _openTermsSheet,
                  onOpenHelp: _openHelpSheet,
                  onOpenCredits: _openCreditsSheet,
                  onOpenHistory: () => setState(() => _currentTab = _Tab.history),
                  onOpenFavorites: () => setState(() => _currentTab = _Tab.favorites),
                  onOpenGuestPaywall: () => GuestPaywallScreen.show(context),
                ),
              ].indexed)
                TickerMode(enabled: i == _currentTab, child: tab),
            ],
          ),
        ),
      ),
    );
  }

  /// Inspected Report Detail View (from Home / History / Favorites / Category).
  Widget _buildInspectedReport(BuildContext context) {
    return AuthenticationReportView(
      report: _inspectedReport!,
      onSelectPart: (part) {
        Navigator.of(context).push(
          LenzRoutes.forward(
            PartDetailView(
              item: part,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        );
      },
      onToggleFavorite: () {
        context.read<HistoryRepository>().toggleFavorite(_inspectedReport!.id);
        setState(() {
          _inspectedReport = _inspectedReport!.copyWith(isFavorite: !_inspectedReport!.isFavorite);
        });
      },
      onDone: () => setState(() => _inspectedReport = null),
    );
  }

  /// Steps that render the same view share a group so they don't animate
  /// between each other.
  static String _scanStepGroup(ScanStep step) => switch (step) {
    ScanStep.identifying || ScanStep.itemIdentified => 'identify',
    _ => step.name,
  };

  /// Prototype transitions inside the scan journey: analysis and the report
  /// reveal zoom, everything else slides forward.
  static LenzRouteKind _scanStepKind(ScanStep step) => switch (step) {
    ScanStep.analyzing || ScanStep.authenticationReport => LenzRouteKind.zoom,
    _ => LenzRouteKind.forward,
  };

  Widget _buildActiveScanFlow(BuildContext context) {
    final scanVm = context.watch<ScanFlowViewModel>();

    switch (scanVm.currentStep) {
      case ScanStep.directScan:
        return DirectScanView(
          onClose: _closeScanFlow,
          onCapture: (imagePath) => scanVm.captureInitialPhoto(imagePath: imagePath),
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
          // The indicator counts the checklist photos actually taken.
          photoNumber: scanVm.currentEvidenceIndex + 1,
          maxPhotos: scanVm.totalEvidenceCount,
          evidenceProgress: scanVm.checklistProgress,
          progressLabel:
              '${scanVm.acceptedEvidenceCount} of ${scanVm.totalEvidenceCount} photos taken',
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
          onToggleFavorite: () {
            if (!scanVm.saveReports) {
              showLenzToast(context, 'Create an account to save reports and favorites.');
              return;
            }
            scanVm.toggleFavoriteCurrentReport();
          },
          onCaptureMoreEvidence: scanVm.captureMoreEvidence,
          onDone: _closeScanFlow,
        );

      case ScanStep.partDetail:
        return PartDetailView(
          item: scanVm.selectedPart!,
          onBack: scanVm.closePartDetail,
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
}

// ---------------------------------------------------------------------------
// Presentation helpers: layered full-screen states with prototype transitions.
// ---------------------------------------------------------------------------

class _LayerSpec {
  const _LayerSpec({required this.id, required this.kind, required this.child});
  final String id;
  final LenzRouteKind kind;
  final Widget child;
}

class _LayerEntry {
  _LayerEntry(this.spec, this.controller);
  _LayerSpec spec;
  final AnimationController controller;
  bool removing = false;
}

/// Stacks [layers] bottom-to-top. A layer that appears plays its
/// [LenzRouteKind] entrance while the one below plays the matching exit (like
/// a pushed route); a layer that disappears plays it in reverse. Fully
/// covered layers are kept alive (offstage, tickers paused).
class _LayerStack extends StatefulWidget {
  const _LayerStack({required this.layers});
  final List<_LayerSpec> layers;

  @override
  State<_LayerStack> createState() => _LayerStackState();
}

class _LayerStackState extends State<_LayerStack> with TickerProviderStateMixin {
  final List<_LayerEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    for (final spec in widget.layers) {
      _entries.add(_newEntry(spec, animate: false));
    }
  }

  _LayerEntry _newEntry(_LayerSpec spec, {required bool animate}) {
    final c = AnimationController(
      vsync: this,
      duration: spec.kind.duration,
      reverseDuration: spec.kind.reverseDuration,
      value: animate ? 0 : 1,
    );
    c.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    return _LayerEntry(spec, c);
  }

  @override
  void didUpdateWidget(covariant _LayerStack old) {
    super.didUpdateWidget(old);
    final wanted = {for (final s in widget.layers) s.id: s};
    final reduce = LenzMotion.reduced(context);

    // Update / revive existing entries, start removing vanished ones.
    for (final e in _entries) {
      final spec = wanted[e.spec.id];
      if (spec != null) {
        e.spec = spec;
        if (e.removing) {
          e.removing = false;
          e.controller.forward();
        }
      } else if (!e.removing) {
        e.removing = true;
        if (reduce) {
          e.controller.value = 0;
          _scheduleRemove(e);
        } else {
          e.controller.reverse().whenCompleteOrCancel(() => _scheduleRemove(e));
        }
      }
    }

    // Insert new entries in priority order.
    for (var i = 0; i < widget.layers.length; i++) {
      final spec = widget.layers[i];
      if (_entries.any((e) => e.spec.id == spec.id)) continue;
      final entry = _newEntry(spec, animate: true);
      // Place after the entry of the previous wanted layer.
      var at = _entries.length;
      if (i + 1 < widget.layers.length) {
        final nextIds = widget.layers.sublist(i + 1).map((s) => s.id).toSet();
        final idx = _entries.indexWhere((e) => nextIds.contains(e.spec.id));
        if (idx >= 0) at = idx;
      }
      _entries.insert(at, entry);
      if (reduce) {
        entry.controller.value = 1;
      } else {
        entry.controller.forward();
      }
    }
  }

  void _scheduleRemove(_LayerEntry e) {
    if (!mounted || !e.removing || e.controller.value > 0) return;
    setState(() {
      _entries.remove(e);
      e.controller.dispose();
    });
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      final above = i + 1 < _entries.length ? _entries[i + 1] : null;
      // Covered by a fully-shown layer above: keep alive but offstage.
      final covered = _entries
          .skip(i + 1)
          .any((a) => !a.removing && a.controller.status == AnimationStatus.completed);
      final interactive =
          !e.removing && _entries.skip(i + 1).every((a) => a.removing && a.controller.value == 0);
      children.add(
        KeyedSubtree(
          key: ValueKey('layer-${e.spec.id}'),
          child: Offstage(
            offstage: covered,
            child: TickerMode(
              enabled: !covered,
              child: IgnorePointer(
                ignoring: !interactive && i != _entries.length - 1,
                child: LenzTransitions.build(
                  context: context,
                  animation: e.controller,
                  secondaryAnimation: above?.controller ?? kAlwaysDismissedAnimation,
                  kind: e.spec.kind,
                  nextKind: above?.spec.kind ?? LenzRouteKind.forward,
                  child: e.spec.child,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Stack(fit: StackFit.expand, children: children);
  }
}

/// Animates between scan-journey steps: the incoming step plays [kind]'s
/// entrance, the outgoing one fades out quickly underneath.
class _ScanStepSwitcher extends StatefulWidget {
  const _ScanStepSwitcher({required this.stepKey, required this.kind, required this.child});
  final String stepKey;
  final LenzRouteKind kind;
  final Widget child;

  @override
  State<_ScanStepSwitcher> createState() => _ScanStepSwitcherState();
}

class _ScanStepSwitcherState extends State<_ScanStepSwitcher> {
  // A fresh serial per step change keeps keys unique even when a step is
  // revisited while its previous instance is still fading out.
  int _serial = 0;
  late String _lastStep = widget.stepKey;

  @override
  void didUpdateWidget(covariant _ScanStepSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.stepKey != _lastStep) {
      _lastStep = widget.stepKey;
      _serial++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return AnimatedSwitcher(
      duration: kind.duration,
      reverseDuration: const Duration(milliseconds: 260),
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        if (animation.status == AnimationStatus.reverse) {
          return FadeTransition(opacity: animation, child: child);
        }
        return LenzTransitions.build(
          context: context,
          animation: animation,
          secondaryAnimation: kAlwaysDismissedAnimation,
          kind: kind,
          child: child,
        );
      },
      child: KeyedSubtree(key: ValueKey('${widget.stepKey}#$_serial'), child: widget.child),
    );
  }
}

/// Cross-fade (prototype `fade`: 420ms, scale .985 -> 1) when switching tabs.
class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: LenzMotion.routeFade,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _TabFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !LenzMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LenzTransitions.build(
      context: context,
      animation: _c,
      secondaryAnimation: kAlwaysDismissedAnimation,
      kind: LenzRouteKind.fade,
      isFirst: true,
      child: widget.child,
    );
  }
}
