import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../core/config/authenticity_engine_config.dart';
import '../core/errors/app_error.dart';
import '../models/authentication_result.dart';
import '../models/evidence.dart';
import '../models/evidence_record.dart';
import '../models/evidence_validation.dart';
import '../models/product.dart';
import '../models/product_identification.dart';
import '../models/product_identity.dart';
import '../repositories/authentication_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/history_repository.dart';
import '../services/analytics_service.dart';
import '../services/cloudinary_service.dart';
import '../services/evidence_decision_engine.dart';
import '../services/evidence_planner.dart';
import '../services/image_quality_checker.dart';
import '../services/scan_consistency_service.dart';
import '../services/storage_service.dart';

enum ScanStep {
  directScan,
  identifying,
  validationFeedback,
  itemIdentified,
  dynamicEvidence,
  guidedCapture,
  validatingPhoto,
  photoQuality,
  analyzing,
  authenticationReport,
  partDetail,
  error,
}

enum ScanLifecycleState {
  idle,
  identifying,
  creatingEvidencePlan,
  identified,
  awaitingEvidence,
  capturingEvidence,
  validatingEvidence,
  evidenceReviewed,
  analyzing,
  resultReady,
  saving,
  saved,
  error,
}

/// What the photo check screen is doing right now.
enum PhotoCheckStage { checkingQuality, examiningDetails }

/// Drives one authentication session.
///
/// Stage A identifies the product from the first photo. Stage B then asks
/// for one photo at a time, always the one expected to be most informative,
/// re-evaluating the evidence after each. The user can finish whenever they
/// like; nothing about the verdict depends on how many photos were taken.
class ScanFlowViewModel extends ChangeNotifier {
  final AuthenticationRepository _authRepo;
  final HistoryRepository _historyRepo;
  final CategoryRepository? _categoryRepo;
  final CloudinaryService? _cloudinaryService;
  final StorageService? _storageService;

  ScanFlowViewModel({
    required AuthenticationRepository authRepo,
    required HistoryRepository historyRepo,
    CategoryRepository? categoryRepo,
    CloudinaryService? cloudinaryService,
    StorageService? storageService,
  })  : _authRepo = authRepo,
        _historyRepo = historyRepo,
        _categoryRepo = categoryRepo,
        _cloudinaryService = cloudinaryService,
        _storageService = storageService;

  /// Mirrors the "Anonymous Scanning" privacy toggle in Settings.
  bool get _stripExif => _storageService?.getBool('anonymous_scanning', defaultValue: false) ?? false;

  /// Optional callback invoked when a scan is successfully completed and recorded.
  VoidCallback? onScanComplete;

  Future<void> Function()? _failedAction;

  ScanStep _currentStep = ScanStep.directScan;
  ScanLifecycleState _scanState = ScanLifecycleState.idle;

  ScanContext? _ctx;
  final List<PhotoEvidence> _photos = [];
  final Set<String> _skipped = {};
  final Map<String, int> _retakeSuggestions = {};
  EngineResult? _engineResult;
  EvidencePlan? _plan;
  List<EvidenceItem> _requestItems = [];

  /// The checklist shown to the user: request ids, most informative first.
  /// Built once after the first photo (and again only if a later photo
  /// changes the product profile), so the list does not reshuffle under
  /// the user while they work through it.
  List<String> _checklist = [];
  String? _checklistProfileId;

  /// The request currently being captured (null = free extra photo).
  String? _activeRequestId;
  bool _activeIsRetake = false;

  AuthenticationReport? _currentReport;
  EvidenceItem? _selectedPart;
  String? _initialImagePath;
  String? _initialSourcePath;

  String? _pendingPhotoPath;
  PhotoCheckResult? _pendingCheck;
  PhotoEvidence? _pendingEvidence;
  PhotoCheckStage _checkStage = PhotoCheckStage.checkingQuality;
  ProductIdentification? _validationResult;

  AppError? _appError;
  bool _isLoading = false;

  // ---------------------------------------------------------------- getters
  ScanStep get currentStep => _currentStep;
  ScanLifecycleState get scanState => _scanState;
  Product? get currentProduct => _ctx?.product;
  ProductIdentity? get identity => _ctx?.identity;
  String? get profileName => _ctx?.profile.profile.name;
  bool get profileHasGenerations => _ctx?.profile.profile.hasGenerations ?? false;
  String get evaluatedModelLabel => _ctx?.profile.evaluatedModelLabel ?? '';
  ProductIdentification? get validationResult => _validationResult;

  List<PhotoEvidence> get photos => List.unmodifiable(_photos);

  /// Photos taken for checklist items (everything except the first photo).
  Iterable<PhotoEvidence> get _evidencePhotos => _photos.where((p) => !p.isInitialPhoto);
  EngineResult? get engineResult => _engineResult;
  EvidencePlan? get plan => _plan;
  List<String> get modelNotes => _ctx?.ranking?.modelNotes ?? const [];

  /// The checklist items, most informative first.
  List<EvidenceItem> get evidenceItems => List.unmodifiable(_checklistItems);

  List<EvidenceItem> get _checklistItems => [
        for (final (i, id) in _checklist.indexed)
          if (_requestItems.where((e) => e.id == id).firstOrNull case final item?) item.copyWith(index: i + 1),
      ];

  /// The single most informative next photo, if any.
  EvidenceItem? get recommendedItem {
    final rec = _plan?.recommended;
    if (rec == null) return null;
    final base = _requestItems.where((i) => i.id == rec.id).firstOrNull;
    if (base == null) return null;
    return base.copyWith(
      title: rec.isRetake ? 'Retake: ${base.title}' : base.title,
      recommendationReason: rec.reason,
      status: EvidenceStatus.pending,
      capturedImagePath: '',
    );
  }

  bool get recommendationIsRetake => _plan?.recommended?.isRetake ?? false;
  bool get nextPhotoOptional => _plan?.nextOptional ?? false;
  bool get evidenceSufficient => _engineResult?.sufficient ?? false;
  double get evidenceProgress => _engineResult?.progress ?? 0;
  String get evidenceProgressLabel => _engineResult?.progressLabel ?? '';

  int get photoCount => _photos.length;
  int get maxPhotos => AuthenticityEngineConfig.maxPhotosPerScan;
  bool get canAddPhoto => _photos.length < maxPhotos;

  int get currentEvidenceIndex {
    final i = _checklist.indexOf(_activeRequestId ?? '');
    return i < 0 ? 0 : i;
  }

  EvidenceItem? get currentEvidenceItem {
    final id = _activeRequestId;
    if (id == null) return null;
    final item = _requestItems.where((e) => e.id == id).firstOrNull;
    if (item == null) return null;
    if (!_activeIsRetake) return item;
    final fix = _evidencePhotos.where((p) => p.requestId == id).firstOrNull?.quality.fix ?? '';
    return item.copyWith(title: 'Retake: ${item.title}', recommendationReason: fix.isEmpty ? item.recommendationReason : fix);
  }

  AuthenticationReport? get currentReport => _currentReport;
  EvidenceItem? get selectedPart => _selectedPart;
  String? get initialImagePath => _initialImagePath;
  String? get pendingPhotoPath => _pendingPhotoPath;
  EvidenceValidationResult? get pendingValidation => _pendingCheck?.validation;
  PhotoEvidence? get pendingEvidence => _pendingEvidence;
  PhotoCheckStage get checkStage => _checkStage;

  AppError? get appError => _appError;
  String? get errorMessage => _appError?.message;
  bool get isLoading => _isLoading;

  /// Photos per checklist item, keyed by request id (what the checklist
  /// and analysing screens show).
  Map<String, String> get capturedImagePaths => {
        for (final e in _checklistItems)
          if (e.capturedImagePath.isNotEmpty) e.id: e.capturedImagePath,
      };

  /// Every accepted photo keyed by photo id ("overview" is the first photo),
  /// for upload.
  Map<String, String> get _photoPathsById => {for (final p in _photos) p.photoId: p.imagePath};

  int get totalEvidenceCount => _checklist.length;
  int get acceptedEvidenceCount => capturedImagePaths.length;

  /// Camera screen indicator: checklist photos taken out of the checklist.
  double get checklistProgress => totalEvidenceCount == 0 ? 0 : (acceptedEvidenceCount / totalEvidenceCount).clamp(0.0, 1.0);

  /// The user is never blocked: any accepted photo, including the first,
  /// can be analysed.
  bool get canAnalyze => _photos.isNotEmpty;

  // ---------------------------------------------------------------- session
  void startScan() {
    _authRepo.clearScanCaches();
    _currentStep = ScanStep.directScan;
    _scanState = ScanLifecycleState.idle;
    _ctx = null;
    _photos.clear();
    _skipped.clear();
    _retakeSuggestions.clear();
    _engineResult = null;
    _plan = null;
    _requestItems = [];
    _checklist = [];
    _checklistProfileId = null;
    _activeRequestId = null;
    _activeIsRetake = false;
    _validationResult = null;
    _currentReport = null;
    _selectedPart = null;
    _initialImagePath = null;
    _initialSourcePath = null;
    _clearPending();
    _appError = null;
    _isLoading = false;
    _failedAction = null;
    notifyListeners();
  }

  void reset() => startScan();

  void _clearPending() {
    _pendingPhotoPath = null;
    _pendingCheck = null;
    _pendingEvidence = null;
  }

  void _fail(Object e, Future<void> Function() retry) {
    _appError = AppError.fromException(e);
    _currentStep = ScanStep.error;
    _scanState = ScanLifecycleState.error;
    _failedAction = retry;
    AnalyticsService.instance.logScanFailed(
      errorType: _appError?.type.name ?? 'unknown',
      message: _appError?.message,
    );
    if (_appError != null) AnalyticsService.instance.recordAppError(_appError!);
  }

  Future<void> retryLastAction() async {
    final action = _failedAction;
    _appError = null;
    _failedAction = null;
    notifyListeners();
    if (action != null) {
      await action();
    } else {
      startScan();
    }
  }

  void _recompute() {
    final ctx = _ctx;
    if (ctx == null) return;
    _engineResult = _authRepo.evaluate(ctx, _photos);
    _plan = _authRepo.plan(ctx, _photos, _engineResult!, skipped: _skipped, retakeSuggestions: _retakeSuggestions);
    _requestItems = _authRepo.requestItems(ctx, _plan!, _photos, _skipped);

    if (_checklistProfileId != ctx.profile.id) {
      // Evidence photos already taken first, then the most informative
      // photos still missing, up to the per-scan photo limit. The first
      // (identification) photo counts as evidence but never fills an item.
      final taken = [
        for (final r in ctx.profile.profile.requests)
          if (_evidencePhotos.any((p) => p.requestId == r.id)) r.id,
      ];
      final room = maxPhotos - _photos.length;
      final missing = _plan!.ranked.where((r) => !r.isRetake && !taken.contains(r.id)).map((r) => r.id).take(room);
      _checklist = [...taken, ...missing];
      _checklistProfileId = ctx.profile.id;
    }
    // A photo accepted for a part that is not on the list still appears on it.
    for (final p in _evidencePhotos) {
      if (!_checklist.contains(p.requestId) && ctx.profile.request(p.requestId) != null) _checklist.add(p.requestId);
    }
  }

  /// Fetches the model-specific ranking when the context lacks one (first
  /// photo, or after a later photo changed the profile).
  Future<void> _ensureRanking() async {
    final ctx = _ctx;
    if (ctx == null || ctx.ranking != null) return;
    final ranking = await _authRepo.recommendEvidence(ctx, covered: {for (final p in _photos) p.requestId});
    _ctx = _ctx!.copyWith(ranking: ranking);
  }

  // ------------------------------------------------ Stage A: identification
  Future<void> captureInitialPhoto({String? imagePath}) async {
    if (imagePath == null || imagePath.isEmpty) {
      _appError = AppError.cameraError(detail: 'No photo was captured. Please try again.');
      _currentStep = ScanStep.error;
      _scanState = ScanLifecycleState.error;
      notifyListeners();
      return;
    }

    _currentStep = ScanStep.identifying;
    _scanState = ScanLifecycleState.identifying;
    _appError = null;
    _validationResult = null;
    _isLoading = true;
    notifyListeners();
    AnalyticsService.instance.logScanStarted();

    try {
      // A retry of the same photo reuses its stored copy; a new photo is stored.
      final storedPath = (_initialImagePath != null && _initialSourcePath == imagePath)
          ? _initialImagePath!
          : await _authRepo.persistCapturedImage(imagePath, prefix: 'primary', stripExif: _stripExif);
      _initialImagePath = storedPath;
      _initialSourcePath = imagePath;
      _authRepo.prewarmPhoto(storedPath, initial: true);

      // 1. Instant on-device check (black, blank, corrupt).
      final quality = await ImageQualityChecker.evaluate(storedPath);
      if (!quality.isUsable) {
        _validationResult = ProductIdentification.unusable(reason: quality.reason, message: quality.message);
        _currentStep = ScanStep.validationFeedback;
        _scanState = ScanLifecycleState.idle;
        return;
      }

      // 2. Product recognition with per-attribute certainty.
      final ident = await _authRepo.identifyProduct(storedPath);
      if (!ident.productDetected ||
          ident.status != IdentificationStatus.productDetected ||
          ident.identificationConfidence < 0.70) {
        _validationResult = ident;
        _currentStep = ScanStep.validationFeedback;
        _scanState = ScanLifecycleState.idle;
        return;
      }

      final product = ident.toProduct(imageAsset: storedPath);
      _ctx = _authRepo.createContext(product);
      _categoryRepo?.registerCategory(product.categoryLabel);
      _scanState = ScanLifecycleState.creatingEvidencePlan;
      notifyListeners();

      // 3. In parallel: which photos matter for this model, and what the
      //    first photo already shows. The first photo counts as evidence.
      final results = await Future.wait<Object>([
        _authRepo.recommendEvidence(_ctx!),
        _authRepo.analyzeInitialPhoto(ctx: _ctx!, imagePath: storedPath, itemBox: ident.itemBox),
      ]);
      _ctx = _ctx!.copyWith(ranking: results[0] as AiEvidenceRanking);
      final initial = results[1] as PhotoEvidence;
      _photos
        ..clear()
        ..add(initial);
      _ctx = _authRepo.absorbPhoto(_ctx!, initial);
      await _ensureRanking();
      _recompute();

      _scanState = ScanLifecycleState.identified;
      _currentStep = ScanStep.itemIdentified;
    } catch (e) {
      _fail(e, () => captureInitialPhoto(imagePath: imagePath));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void proceedToEvidenceChecklist() {
    _currentStep = ScanStep.dynamicEvidence;
    _scanState = ScanLifecycleState.awaitingEvidence;
    notifyListeners();
  }

  void backToEvidenceChecklist() {
    _clearPending();
    _currentStep = ScanStep.dynamicEvidence;
    _scanState = ScanLifecycleState.awaitingEvidence;
    notifyListeners();
  }

  /// Opens the camera for the recommended photo.
  void captureRecommended() {
    final rec = _plan?.recommended;
    if (rec == null || !canAddPhoto && !rec.isRetake) return;
    _openCapture(rec.id, isRetake: rec.isRetake);
  }

  /// Opens the camera for the request at [index] in [evidenceItems].
  void startEvidenceCapture([int index = 0]) {
    final items = _checklistItems;
    if (items.isEmpty) return;
    final item = items[index.clamp(0, items.length - 1)];
    final alreadyTaken = _evidencePhotos.any((p) => p.requestId == item.id);
    if (!canAddPhoto && !alreadyTaken) return;
    _skipped.remove(item.id);
    _openCapture(item.id, isRetake: alreadyTaken);
  }

  void _openCapture(String requestId, {bool isRetake = false}) {
    _activeRequestId = requestId;
    _activeIsRetake = isRetake;
    _clearPending();
    _currentStep = ScanStep.guidedCapture;
    _scanState = ScanLifecycleState.capturingEvidence;
    notifyListeners();
  }

  // ----------------------------------------- Stage B: check & analyse one
  Future<void> submitEvidencePhoto(String? photoPath) async {
    final ctx = _ctx;
    if (ctx == null) return;
    if (photoPath == null || photoPath.isEmpty) {
      _appError = AppError.cameraError(detail: 'No photo was captured. Please try again.');
      notifyListeners();
      return;
    }

    _currentStep = ScanStep.validatingPhoto;
    _scanState = ScanLifecycleState.validatingEvidence;
    _checkStage = PhotoCheckStage.checkingQuality;
    _isLoading = true;
    _clearPending();
    _appError = null;
    notifyListeners();

    try {
      final storedPath = await _authRepo.persistCapturedImage(
        photoPath,
        prefix: _activeRequestId ?? 'extra',
        stripExif: _stripExif,
      );
      _pendingPhotoPath = storedPath;

      final existing = _photos.where((p) => p.requestId != _activeRequestId || !_activeIsRetake).toList();
      final check = await _authRepo.checkPhoto(
        ctx: ctx,
        imagePath: storedPath,
        requestedId: _activeRequestId,
        existing: existing,
      );
      _pendingCheck = check;

      // Analyse straight away when the photo is usable, so the review screen
      // can already say what it showed.
      if (check.validation.isAccepted) {
        _checkStage = PhotoCheckStage.examiningDetails;
        notifyListeners();
        _pendingEvidence = await _authRepo.analyzePhoto(ctx: ctx, check: check);
      }

      _currentStep = ScanStep.photoQuality;
      _scanState = ScanLifecycleState.evidenceReviewed;
    } catch (e) {
      _fail(e, () => submitEvidencePhoto(photoPath));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Accepts the reviewed photo. [force] keeps a photo flagged for quality
  /// (never one of the wrong subject); its observations are then trusted less.
  Future<void> acceptPendingPhoto({bool force = false}) async {
    final ctx = _ctx;
    final check = _pendingCheck;
    if (ctx == null || check == null) return;
    final validation = check.validation;
    if (!validation.isAccepted && !(force && validation.isOverridable)) return;

    try {
      var evidence = _pendingEvidence;
      if (evidence == null) {
        _currentStep = ScanStep.validatingPhoto;
        _checkStage = PhotoCheckStage.examiningDetails;
        _isLoading = true;
        notifyListeners();
        evidence = await _authRepo.analyzePhoto(ctx: ctx, check: check, keptDespiteLowQuality: !validation.isAccepted);
      }

      final replacedIndex = _photos.indexWhere((p) => p.photoId == evidence!.photoId && !p.isInitialPhoto);
      if (replacedIndex >= 0) {
        _photos[replacedIndex] = evidence;
        _retakeSuggestions[evidence.requestId] = (_retakeSuggestions[evidence.requestId] ?? 0) + 1;
      } else {
        _photos.add(evidence);
      }
      _skipped.remove(evidence.requestId);
      _ctx = _authRepo.absorbPhoto(_ctx!, evidence);
      await _ensureRanking();
      _recompute();

      _clearPending();
      _advanceOrReview();
    } catch (e) {
      _fail(e, () => acceptPendingPhoto(force: force));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void retakePendingPhoto() {
    _clearPending();
    _currentStep = ScanStep.guidedCapture;
    _scanState = ScanLifecycleState.capturingEvidence;
    notifyListeners();
  }

  /// The user can't take this photo. Recorded so it isn't asked again; it
  /// is never treated as evidence either way.
  void markCurrentEvidenceUnavailable() {
    final id = _activeRequestId;
    if (id != null && !_evidencePhotos.any((p) => p.requestId == id)) _skipped.add(id);
    _clearPending();
    _recompute();
    _advanceOrReview();
    notifyListeners();
  }

  /// Moves to the next checklist item that has no photo and was not skipped,
  /// or back to the checklist when there is none (the original flow).
  void _advanceOrReview() {
    final items = _checklistItems;
    final from = currentEvidenceIndex + 1;
    int? next;
    for (var i = from; i < items.length; i++) {
      if (items[i].status == EvidenceStatus.pending) {
        next = i;
        break;
      }
    }
    if (next != null && canAddPhoto) {
      _activeRequestId = items[next].id;
      _activeIsRetake = false;
      _currentStep = ScanStep.guidedCapture;
      _scanState = ScanLifecycleState.capturingEvidence;
    } else {
      _activeRequestId = null;
      _activeIsRetake = false;
      _currentStep = ScanStep.dynamicEvidence;
      _scanState = ScanLifecycleState.awaitingEvidence;
    }
  }

  void markEvidenceUnavailableAt(int index) {
    final items = _checklistItems;
    if (index < 0 || index >= items.length) return;
    final id = items[index].id;
    if (_evidencePhotos.any((p) => p.requestId == id)) return;
    _skipped.add(id);
    _recompute();
    notifyListeners();
  }

  /// Removes an added photo (never the first, identification photo).
  void clearEvidenceAt(int index) {
    final items = _checklistItems;
    if (index < 0 || index >= items.length) return;
    final id = items[index].id;
    _photos.removeWhere((p) => p.requestId == id && !p.isInitialPhoto);
    _skipped.remove(id);
    _recompute();
    notifyListeners();
  }

  void skipCurrentEvidence() {
    _clearPending();
    _advanceOrReview();
    notifyListeners();
  }

  // ---------------------------------------------------- final evaluation
  Future<void> finishAndAnalyzeNow() => runAnalysis();

  Future<void> runAnalysis() async {
    final ctx = _ctx;
    if (ctx == null) return;
    if (!canAnalyze) {
      _appError = AppError.unknown(detail: 'There is no photo to analyse. Capture the item first.');
      notifyListeners();
      return;
    }

    _currentStep = ScanStep.analyzing;
    _scanState = ScanLifecycleState.analyzing;
    _appError = null;
    notifyListeners();

    try {
      final scored = await _authRepo.finalizeReport(
        ctx: ctx,
        photos: List<PhotoEvidence>.from(_photos),
        skipped: Set<String>.from(_skipped),
        retakeSuggestions: Map<String, int>.from(_retakeSuggestions),
        scanId: 'scan_${DateTime.now().microsecondsSinceEpoch}',
      );

      // Repeat-scan consistency: a stable earlier result of the same
      // product is only overturned by new strong evidence.
      final report = ScanConsistencyService.reconcile(report: scored, history: _historyRepo.allReports);

      _currentReport = report;
      _historyRepo.addReport(report);
      onScanComplete?.call();
      _categoryRepo?.registerCategory(report.product.categoryLabel);

      AnalyticsService.instance.logScanCompleted(
        reportId: report.id,
        verdict: report.verdict.name,
        confidence: report.overallScore,
      );

      _triggerBackgroundPhotoUpload(report, _photoPathsById);

      _scanState = ScanLifecycleState.resultReady;
      _currentStep = ScanStep.authenticationReport;
    } catch (e) {
      _fail(e, () => runAnalysis());
    } finally {
      notifyListeners();
    }
  }

  void _triggerBackgroundPhotoUpload(AuthenticationReport report, Map<String, String> localImages) {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty || _cloudinaryService == null) return;

      _cloudinaryService.uploadEvidencePhotos(
        userId: uid,
        scanId: report.id,
        localImages: Map<String, String>.from(localImages),
      ).then((uploadedUrls) {
        if (uploadedUrls.isEmpty) return;

        // Swap local paths for uploaded URLs so the saved report stays
        // viewable once local files are gone (sign-out, another device).
        final updatedEvidence = report.evidenceItems.map((item) {
          final uploadedUrl = uploadedUrls[item.id];
          if (uploadedUrl == null || uploadedUrl.isEmpty) return item;
          return item.copyWith(capturedImagePath: uploadedUrl);
        }).toList();

        final overviewUrl = uploadedUrls['overview'];
        final updatedProduct = overviewUrl != null && overviewUrl.isNotEmpty
            ? report.product.copyWith(imageAsset: overviewUrl)
            : report.product;

        _historyRepo.updateReport(report.copyWith(evidenceItems: updatedEvidence, product: updatedProduct));
      }).catchError((_) {});
    } catch (_) {}
  }

  /// Returns to the evidence screen so the user can add the recommended
  /// photo and re-run the analysis. Earlier photos and their analysis are
  /// kept, not repeated.
  void captureMoreEvidence() {
    _currentReport = null;
    _currentStep = ScanStep.dynamicEvidence;
    _scanState = ScanLifecycleState.awaitingEvidence;
    notifyListeners();
  }

  // ------------------------------------------------------------------ report
  void openPartDetail(EvidenceItem item) {
    _selectedPart = item;
    _currentStep = ScanStep.partDetail;
    notifyListeners();
  }

  void closePartDetail() {
    _selectedPart = null;
    _currentStep = ScanStep.authenticationReport;
    notifyListeners();
  }

  void toggleFavoriteCurrentReport() {
    final report = _currentReport;
    if (report == null) return;
    _historyRepo.toggleFavorite(report.id);
    _currentReport = report.copyWith(isFavorite: !report.isFavorite);
    notifyListeners();
  }
}
