import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../core/errors/app_error.dart';
import '../models/authentication_result.dart';
import '../models/evidence.dart';
import '../models/evidence_validation.dart';
import '../models/product.dart';
import '../models/product_identification.dart';
import '../repositories/authentication_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/history_repository.dart';
import '../services/analytics_service.dart';
import '../services/cloudinary_service.dart';
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

/// Drives one authentication session. Holds no sample data: every product,
/// photo, score and report it exposes came from this run (§30).
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

  Future<void> Function()? _failedAction;

  ScanStep _currentStep = ScanStep.directScan;
  ScanLifecycleState _scanState = ScanLifecycleState.idle;

  Product? _currentProduct;
  List<EvidenceItem> _evidenceItems = [];
  int _currentEvidenceIndex = 0;
  AuthenticationReport? _currentReport;
  EvidenceItem? _selectedPart;

  String? _initialImagePath;

  /// Accepted photos only, keyed by evidence id. A rejected photo never
  /// reaches this map (§6).
  final Map<String, String> _capturedImagePaths = {};

  /// The photo currently under review, before it is accepted or discarded.
  String? _pendingPhotoPath;
  EvidenceValidationResult? _pendingValidation;
  ProductIdentification? _validationResult;

  AppError? _appError;
  bool _isLoading = false;

  // ---------------------------------------------------------------- getters
  ScanStep get currentStep => _currentStep;
  ScanLifecycleState get scanState => _scanState;
  Product? get currentProduct => _currentProduct;
  ProductIdentification? get validationResult => _validationResult;
  List<EvidenceItem> get evidenceItems => List.unmodifiable(_evidenceItems);
  int get currentEvidenceIndex => _currentEvidenceIndex;

  EvidenceItem? get currentEvidenceItem =>
      _currentEvidenceIndex >= 0 && _currentEvidenceIndex < _evidenceItems.length
          ? _evidenceItems[_currentEvidenceIndex]
          : null;

  AuthenticationReport? get currentReport => _currentReport;
  EvidenceItem? get selectedPart => _selectedPart;

  String? get initialImagePath => _initialImagePath;
  String? get pendingPhotoPath => _pendingPhotoPath;
  EvidenceValidationResult? get pendingValidation => _pendingValidation;

  AppError? get appError => _appError;
  String? get errorMessage => _appError?.message;
  bool get isLoading => _isLoading;

  Map<String, String> get capturedImagePaths => Map.unmodifiable(_capturedImagePaths);

  int get totalEvidenceCount => _evidenceItems.length;
  int get acceptedEvidenceCount => _capturedImagePaths.length;

  /// The user is never blocked. If they supplied none of the requested angles,
  /// the first identification photo alone is analysed — which will almost
  /// always come back inconclusive, and says so (§4, §26, §27).
  bool get canAnalyze =>
      _capturedImagePaths.isNotEmpty || (_initialImagePath?.isNotEmpty ?? false);

  // ---------------------------------------------------------------- session
  void startScan() {
    _authRepo.clearScanCaches();
    _currentStep = ScanStep.directScan;
    _scanState = ScanLifecycleState.idle;
    _currentProduct = null;
    _validationResult = null;
    _evidenceItems = [];
    _currentEvidenceIndex = 0;
    _currentReport = null;
    _selectedPart = null;
    _initialImagePath = null;
    _capturedImagePaths.clear();
    _pendingPhotoPath = null;
    _pendingValidation = null;
    _appError = null;
    _isLoading = false;
    _failedAction = null;
    notifyListeners();
  }

  void reset() => startScan();

  void _fail(Object e, Future<void> Function() retry) {
    _appError = AppError.fromException(e);
    _currentStep = ScanStep.error;
    _scanState = ScanLifecycleState.error;
    _failedAction = retry;
    AnalyticsService.instance.logScanFailed(
      errorType: _appError?.type.name ?? 'unknown',
      message: _appError?.message,
    );
    if (_appError != null) {
      AnalyticsService.instance.recordAppError(_appError!);
    }
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

  // ------------------------------------------------- step 1: identification
  /// Sends the user's first photo for identification, then fetches the
  /// product-specific evidence plan. One request each, both cached.
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
      final storedPath = await _authRepo.persistCapturedImage(
        imagePath,
        prefix: 'primary',
        stripExif: _stripExif,
      );
      _initialImagePath = storedPath;

      // 1. Fast local hardware/image checks (black/blank/washout)
      final quality = await ImageQualityChecker.evaluate(storedPath);
      if (!quality.isUsable) {
        _validationResult = ProductIdentification.unusable(
          reason: quality.reason,
          message: quality.message,
        );
        _currentStep = ScanStep.validationFeedback;
        _scanState = ScanLifecycleState.idle;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 2. Strict AI Presence & Identification
      final ident = await _authRepo.identifyProduct(storedPath);

      // 3. App-Side Safety Guard against false positives & weak detections
      if (!ident.productDetected ||
          ident.status != IdentificationStatus.productDetected ||
          ident.identificationConfidence < 0.70) {
        _validationResult = ident;
        _currentStep = ScanStep.validationFeedback;
        _scanState = ScanLifecycleState.idle;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 4. Product validated - proceed to evidence planning
      _currentProduct = ident.toProduct(imageAsset: storedPath);
      _categoryRepo?.registerCategory(_currentProduct!.categoryLabel);

      _scanState = ScanLifecycleState.creatingEvidencePlan;
      notifyListeners();

      _evidenceItems = List<EvidenceItem>.from(
        await _authRepo.getRequiredEvidence(_currentProduct!),
      );

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
    _pendingPhotoPath = null;
    _pendingValidation = null;
    _currentStep = ScanStep.dynamicEvidence;
    _scanState = ScanLifecycleState.awaitingEvidence;
    notifyListeners();
  }

  void startEvidenceCapture([int initialIndex = 0]) {
    if (_evidenceItems.isEmpty) return;
    _currentEvidenceIndex = initialIndex.clamp(0, _evidenceItems.length - 1);
    _pendingPhotoPath = null;
    _pendingValidation = null;
    _currentStep = ScanStep.guidedCapture;
    _scanState = ScanLifecycleState.capturingEvidence;
    notifyListeners();
  }

  // ------------------------------------------- step 2: submit & validate one
  /// Validates a submitted photo against the requested angle before it can
  /// become evidence. A wrong-subject photo is never stored (§6, §7, §9).
  Future<void> submitEvidencePhoto(String? photoPath) async {
    final item = currentEvidenceItem;
    if (item == null) return;

    if (photoPath == null || photoPath.isEmpty) {
      _appError = AppError.cameraError(detail: 'No photo was captured. Please try again.');
      notifyListeners();
      return;
    }

    _currentStep = ScanStep.validatingPhoto;
    _scanState = ScanLifecycleState.validatingEvidence;
    _isLoading = true;
    _pendingValidation = null;
    _appError = null;
    notifyListeners();

    try {
      final storedPath = await _authRepo.persistCapturedImage(
        photoPath,
        prefix: item.id,
        stripExif: _stripExif,
      );
      _pendingPhotoPath = storedPath;

      _pendingValidation = await _authRepo.validateEvidencePhoto(
        imagePath: storedPath,
        requestedItem: item,
        product: _currentProduct!,
      );

      _currentStep = ScanStep.photoQuality;
      _scanState = ScanLifecycleState.evidenceReviewed;
    } catch (e) {
      _fail(e, () => submitEvidencePhoto(photoPath));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Accepts the reviewed photo as evidence for the current item.
  ///
  /// [force] is only honoured for quality rejections, where the user may keep
  /// a usable-but-poor image; the evidence is then flagged so the scoring
  /// engine trusts it less (§50). Wrong-subject photos can never be forced in.
  void acceptPendingPhoto({bool force = false}) {
    final item = currentEvidenceItem;
    final validation = _pendingValidation;
    final path = _pendingPhotoPath;
    if (item == null || validation == null || path == null) return;

    if (!validation.isAccepted && !(force && validation.isOverridable)) {
      return;
    }

    final keptLowQuality = !validation.isAccepted;

    _capturedImagePaths[item.id] = path;
    _evidenceItems[_currentEvidenceIndex] = item.copyWith(
      capturedImagePath: path,
      status: EvidenceStatus.captured,
      validation: validation,
      keptDespiteLowQuality: keptLowQuality,
    );

    _pendingPhotoPath = null;
    _pendingValidation = null;
    _advanceOrReview();
  }

  /// Discards the reviewed photo and returns to the camera for the same item.
  void retakePendingPhoto() {
    _pendingPhotoPath = null;
    _pendingValidation = null;
    _currentStep = ScanStep.guidedCapture;
    _scanState = ScanLifecycleState.capturingEvidence;
    notifyListeners();
  }

  /// The user states they do not have this evidence. It is recorded as
  /// unavailable and lowers coverage — never treated as passing (§27).
  void markCurrentEvidenceUnavailable() {
    final item = currentEvidenceItem;
    if (item == null) return;

    _capturedImagePaths.remove(item.id);
    _evidenceItems[_currentEvidenceIndex] = item.copyWith(
      status: EvidenceStatus.unavailable,
      capturedImagePath: '',
    );
    _pendingPhotoPath = null;
    _pendingValidation = null;
    _advanceOrReview();
  }

  void markEvidenceUnavailableAt(int index) {
    if (index < 0 || index >= _evidenceItems.length) return;
    final item = _evidenceItems[index];
    _capturedImagePaths.remove(item.id);
    _evidenceItems[index] = item.copyWith(
      status: EvidenceStatus.unavailable,
      capturedImagePath: '',
    );
    notifyListeners();
  }

  void clearEvidenceAt(int index) {
    if (index < 0 || index >= _evidenceItems.length) return;
    final item = _evidenceItems[index];
    _capturedImagePaths.remove(item.id);
    _evidenceItems[index] = item.copyWith(
      status: EvidenceStatus.pending,
      capturedImagePath: '',
    );
    notifyListeners();
  }

  void skipCurrentEvidence() {
    _pendingPhotoPath = null;
    _pendingValidation = null;
    _advanceOrReview();
  }

  /// Moves to the next unresolved angle, or back to the checklist when the
  /// user has been through them all. Analysis is never triggered implicitly.
  void _advanceOrReview() {
    final nextIndex = _nextUnresolvedIndex(from: _currentEvidenceIndex + 1);
    if (nextIndex != null) {
      _currentEvidenceIndex = nextIndex;
      _currentStep = ScanStep.guidedCapture;
      _scanState = ScanLifecycleState.capturingEvidence;
    } else {
      _currentStep = ScanStep.dynamicEvidence;
      _scanState = ScanLifecycleState.awaitingEvidence;
    }
    notifyListeners();
  }

  int? _nextUnresolvedIndex({int from = 0}) {
    for (int i = from; i < _evidenceItems.length; i++) {
      final e = _evidenceItems[i];
      if (!_capturedImagePaths.containsKey(e.id) && !e.isUnavailable) return i;
    }
    return null;
  }

  // ---------------------------------------------------- step 3: final analysis
  Future<void> finishAndAnalyzeNow() => runAnalysis();

  Future<void> runAnalysis() async {
    if (_currentProduct == null) return;

    if (!canAnalyze) {
      _appError = AppError.unknown(
        detail: 'There is no photo to analyse. Capture the item first.',
      );
      notifyListeners();
      return;
    }

    _currentStep = ScanStep.analyzing;
    _scanState = ScanLifecycleState.analyzing;
    _appError = null;
    notifyListeners();

    try {
      final identificationConfidence =
          (_currentProduct!.identificationConfidence * 100).round().clamp(0, 99);

      final scored = await _authRepo.finalizeReport(
        product: _currentProduct!,
        evidenceItems: _evidenceItems,
        capturedImages: Map<String, String>.from(_capturedImagePaths),
        // Used only when none of the requested angles were supplied. It is
        // never credited to a requested angle, so coverage stays at zero.
        overviewImagePath: _initialImagePath,
        identificationConfidence: identificationConfidence,
        scanId: 'scan_${DateTime.now().microsecondsSinceEpoch}',
      );

      // Repeat-scan consistency (§17-19): a stable earlier result of the
      // same product is only overturned by new strong evidence.
      final report = ScanConsistencyService.reconcile(
        report: scored,
        history: _historyRepo.allReports,
      );

      _currentReport = report;
      _evidenceItems = List<EvidenceItem>.from(report.evidenceItems);
      _historyRepo.addReport(report);
      _categoryRepo?.registerCategory(report.product.categoryLabel);

      AnalyticsService.instance.logScanCompleted(
        reportId: report.id,
        verdict: report.verdict.name,
        confidence: report.overallScore,
      );

      _triggerBackgroundPhotoUpload(
        report,
        Map<String, String>.from(_capturedImagePaths),
        _initialImagePath,
      );

      _scanState = ScanLifecycleState.resultReady;
      _currentStep = ScanStep.authenticationReport;
    } catch (e) {
      _fail(e, () => runAnalysis());
    } finally {
      notifyListeners();
    }
  }

  void _triggerBackgroundPhotoUpload(
    AuthenticationReport report,
    Map<String, String> localImages,
    String? overviewPath,
  ) {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty || _cloudinaryService == null) return;

      final imagesToUpload = Map<String, String>.from(localImages);
      if (overviewPath != null && overviewPath.isNotEmpty) {
        imagesToUpload['overview'] = overviewPath;
      }

      _cloudinaryService.uploadEvidencePhotos(
        userId: uid,
        scanId: report.id,
        localImages: imagesToUpload,
      ).then((uploadedUrls) {
        if (uploadedUrls.isEmpty) return;

        // Swap each evidence item's local file path for its uploaded
        // Cloudinary URL (and the product's overview photo too), so the
        // saved report is still viewable once the local files are gone -
        // e.g. deleted on sign-out for privacy, or opened after logging
        // back in on this or another device. Previously this called
        // report.copyWith() with no arguments, silently discarding every
        // uploaded URL and leaving the report pointing at local-only paths.
        final updatedEvidence = report.evidenceItems.map((item) {
          final uploadedUrl = uploadedUrls[item.id];
          if (uploadedUrl == null || uploadedUrl.isEmpty) return item;
          return item.copyWith(capturedImagePath: uploadedUrl);
        }).toList();

        var updatedProduct = report.product;
        final overviewUrl = uploadedUrls['overview'];
        if (overviewUrl != null && overviewUrl.isNotEmpty) {
          updatedProduct = Product(
            id: updatedProduct.id,
            name: updatedProduct.name,
            brand: updatedProduct.brand,
            model: updatedProduct.model,
            category: updatedProduct.category,
            customCategory: updatedProduct.customCategory,
            imageAsset: overviewUrl,
            identificationConfidence: updatedProduct.identificationConfidence,
          );
        }

        final updatedReport = report.copyWith(
          evidenceItems: updatedEvidence,
          product: updatedProduct,
        );
        _historyRepo.updateReport(updatedReport);
      }).catchError((_) {});
    } catch (_) {}
  }

  /// Returns to the capture checklist so the user can add more evidence and
  /// re-run the analysis (§41 "Capture More Evidence").
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
