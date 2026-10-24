import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:provider/provider.dart';

import '../../services/storage_service.dart';
import '../../widgets/ui/ui.dart';

class CameraPreviewWidget extends StatefulWidget {
  final Widget? overlay;
  final ValueChanged<CameraController?>? onControllerReady;
  final ValueChanged<double>? onZoomChanged;

  /// Presentation hook: told (after the frame) when the "Camera Unavailable"
  /// state appears or clears, so a screen can hide chrome that would sit on
  /// top of the message. Does not affect camera behaviour.
  final ValueChanged<bool>? onUnavailableChanged;

  /// Told when the frame is locked (the shutter was pressed) or released
  /// again (the capture failed), so screens can stop their scan animations.
  final ValueChanged<bool>? onFrozenChanged;

  const CameraPreviewWidget({
    super.key,
    this.overlay,
    this.onControllerReady,
    this.onZoomChanged,
    this.onUnavailableChanged,
    this.onFrozenChanged,
  });

  @override
  State<CameraPreviewWidget> createState() => CameraPreviewWidgetState();
}

class CameraPreviewWidgetState extends State<CameraPreviewWidget> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  FlashMode _flashMode = FlashMode.off;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 4.0;

  /// Set once a capture at the configured (possibly max) resolution times
  /// out — some Android camera stacks hang on still-capture at their sensor's
  /// absolute max resolution. Once that happens, every capture for the rest
  /// of this screen's lifetime uses a lower, more broadly-compatible preset
  /// instead of repeating the same multi-second hang on every subsequent try.
  bool _forceStandardResolution = false;

  /// Camera sessions are strictly serialized: a new controller is only opened
  /// after the previous one has finished closing, otherwise Android answers
  /// "camera is not available" and the screen shows "Camera Unavailable" (or a
  /// spinner that never ends) after the gallery picker, a permission dialog or
  /// any quick app switch.
  Future<void> _closing = Future<void>.value();
  bool _inBackground = false;

  /// The preview is paused on the frame the user captured.
  bool _frozen = false;
  bool get isFrozen => _frozen;
  final GlobalKey _previewKey = GlobalKey();
  ui.Image? _frozenFrame;

  /// Bumped whenever the camera is (re)opened or released, so results of an
  /// open that has been overtaken are discarded.
  int _gen = 0;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized && _controller != null;
  FlashMode get flashMode => _flashMode;
  double get currentZoom => _currentZoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gen++; // any open still in flight must not complete into a dead screen
    _frozenFrame?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Really in the background (picker, another app): free the camera.
      // Transient `inactive` moments (shade pulled down, dialogs) keep it.
      _inBackground = true;
      _releaseController();
    } else if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      if (_controller == null && mounted) {
        setState(() {
          _hasError = false;
          _errorMessage = '';
        });
        if (_cameras.isEmpty) {
          _initCameras();
        } else {
          _initCameraController(_selectedCameraIndex);
        }
      }
    }
  }

  /// Closes the live controller. Later opens wait for this to finish.
  void _releaseController() {
    _gen++; // an open that is still in flight is now stale
    final c = _controller;
    _controller = null;
    _isInitialized = false;
    if (mounted) setState(() {});
    if (c != null) {
      _closing = _closing.then((_) => c.dispose()).catchError((Object _) {});
    }
  }

  /// Turns a raw camera exception into something a user can actually act on,
  /// instead of a Dart exception string like "CameraException(...)".
  String _friendlyCameraError(Object e) {
    if (e is CameraException) {
      final code = e.code.toLowerCase();
      if (code.contains('denied') || code.contains('restricted') || code.contains('permission')) {
        return 'Camera access is turned off for Lenz. Enable it in your '
            'device Settings, then tap Retry.';
      }
    }
    return 'Something went wrong opening the camera. Please try again.';
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'No camera found on this device.';
        });
        return;
      }

      // Default to first back camera
      final backCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _selectedCameraIndex = backCameraIndex != -1 ? backCameraIndex : 0;
      await _initCameraController(_selectedCameraIndex);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] Error fetching available cameras: $e');
      }
      setState(() {
        _hasError = true;
        _errorMessage = _friendlyCameraError(e);
      });
    }
  }

  Future<void> _initCameraController(int cameraIndex, {int attempt = 0}) async {
    if (_cameras.isEmpty || cameraIndex >= _cameras.length) return;

    final gen = ++_gen;
    final oldController = _controller;
    if (oldController != null) {
      _controller = null;
      _closing = _closing.then((_) => oldController.dispose()).catchError((Object _) {});
    }
    // Never open while a previous session is still closing.
    await _closing;
    if (!mounted || gen != _gen) return;

    // The resolution preset also sets the still-photo size. veryHigh is
    // 1080p: real scans (2026-09-26) arrived as 1080x1920, where a watch
    // crown or engraving spans only ~150 px. "HD Multi-Angle Inspection" (on
    // by default) now captures at the sensor's full resolution so detail
    // crops keep real detail; off falls back to 1080p (previously 480p,
    // too small for authentication).
    final hdQuality =
        !_forceStandardResolution &&
        context.read<StorageService>().getBool('hd_quality', defaultValue: true);
    final newController = CameraController(
      _cameras[cameraIndex],
      hdQuality ? ResolutionPreset.max : ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await newController.initialize();
      await newController.setFlashMode(_flashMode);

      // Overtaken (screen closed, app backgrounded, newer open): hand it back.
      if (!mounted || gen != _gen || _inBackground) {
        await newController.dispose();
        return;
      }

      double minZ = 1.0;
      double maxZ = 4.0;
      try {
        minZ = await newController.getMinZoomLevel();
        maxZ = await newController.getMaxZoomLevel();
      } catch (_) {}

      if (mounted && gen == _gen) {
        setState(() {
          _controller = newController;
          _minZoom = minZ;
          _maxZoom = maxZ.clamp(1.0, 5.0);
          _currentZoom = minZ;
          _isInitialized = true;
          _hasError = false;
        });
        _unfreeze();
        widget.onControllerReady?.call(newController);
      } else {
        await newController.dispose();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] Camera init error: $e');
      }
      try {
        await newController.dispose();
      } catch (_) {}
      if (!mounted || gen != _gen) return;

      // "Camera busy" style failures are usually the previous session still
      // being torn down: wait a moment and try again before bothering the user.
      final permission =
          e is CameraException &&
          (e.code.toLowerCase().contains('denied') ||
              e.code.toLowerCase().contains('restricted') ||
              e.code.toLowerCase().contains('permission'));
      if (!permission && attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 600 + 600 * attempt));
        if (!mounted || gen != _gen || _inBackground) return;
        return _initCameraController(cameraIndex, attempt: attempt + 1);
      }
      setState(() {
        _hasError = true;
        _errorMessage = _friendlyCameraError(e);
        _isInitialized = false;
      });
    }
  }

  double _scaleStartZoom = 1.0;

  Future<void> setZoom(double zoom) async {
    if (!isInitialized || _controller == null) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    try {
      await _controller!.setZoomLevel(clamped);
      if (mounted) {
        setState(() => _currentZoom = clamped);
        widget.onZoomChanged?.call(clamped);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] setZoom error: $e');
      }
    }
  }

  Future<void> zoomIn() async {
    final next = (_currentZoom + 0.5).clamp(_minZoom, _maxZoom);
    await setZoom(next);
  }

  Future<void> zoomOut() async {
    final next = (_currentZoom - 0.5).clamp(_minZoom, _maxZoom);
    await setZoom(next);
  }

  Future<bool> toggleFlash() async {
    if (!isInitialized || _controller == null) return false;

    final nextMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;

    try {
      await _controller!.setFlashMode(nextMode);
      if (mounted) {
        setState(() => _flashMode = nextMode);
      }
      return nextMode == FlashMode.torch;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] Error toggling flash: $e');
      }
      return _flashMode == FlashMode.torch;
    }
  }

  Future<void> flipCamera() async {
    if (_cameras.length < 2) return;
    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _selectedCameraIndex = nextIndex;
    await _initCameraController(nextIndex);
  }

  /// Grabs the frame on screen right now (what the user is looking at when
  /// the shutter is pressed) and shows it in place of the live preview, so the
  /// picture is visibly locked while the photo is taken. The live preview keeps
  /// running underneath: pausing it (`pausePreview`) unbinds the preview use
  /// case on Android, which makes the following still capture hang.
  Future<void> _freeze() async {
    try {
      final boundary = _previewKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary && boundary.hasSize) {
        final ratio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
        final image = await boundary.toImage(pixelRatio: ratio);
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _frozenFrame?.dispose();
          _frozenFrame = image;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CameraPreviewWidget] freeze: $e');
    }
    _setFrozen(true);
  }

  void _unfreeze() {
    if (!_frozen && _frozenFrame == null) return;
    setState(() {
      _frozenFrame?.dispose();
      _frozenFrame = null;
    });
    _setFrozen(false);
  }

  void _setFrozen(bool v) {
    if (_frozen == v) return;
    _frozen = v;
    widget.onFrozenChanged?.call(v);
  }

  Future<XFile?> takePicture() async {
    if (!isInitialized || _controller == null) return null;
    if (_controller!.value.isTakingPicture) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] takePicture cancelled: camera is already capturing');
      }
      return null;
    }
    final cam = _controller!;
    // The moment the shutter is pressed the picture on screen is locked: the
    // preview stops on that frame instead of carrying on while the photo is
    // being taken and processed.
    await _freeze();
    try {
      // Some Android camera stacks stop answering after several open/close
      // cycles, or simply can't keep up with a still-capture at the sensor's
      // max resolution; without a bound the shutter spins forever with no
      // feedback, which reads to a user as "the camera just keeps running".
      final file = await cam.takePicture().timeout(const Duration(seconds: 6));
      if (mounted && context.read<StorageService>().getBool('camera_sound', defaultValue: true)) {
        SystemSound.play(SystemSoundType.click);
      }
      return file;
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint(
          '[CameraPreviewWidget] takePicture timed out after 6s - restarting camera at a lower resolution',
        );
      }
      // Self-healing: a hang is most often the max-resolution preset being
      // more than this device's camera stack can deliver for still capture.
      // Downgrade for the rest of this session instead of hanging the same
      // way on every retry.
      _forceStandardResolution = true;
      _unfreeze();
      if (mounted) unawaited(_initCameraController(_selectedCameraIndex));
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] takePicture error: $e');
      }
      _unfreeze();
      return null;
    }
  }

  bool _reportedUnavailable = false;

  void _reportUnavailable() {
    final unavailable = _hasError;
    if (unavailable == _reportedUnavailable) return;
    _reportedUnavailable = unavailable;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onUnavailableChanged?.call(unavailable);
    });
  }

  @override
  Widget build(BuildContext context) {
    _reportUnavailable();
    if (_hasError) {
      // Lenz dark-glass card over the camera backdrop. Retry behaviour is
      // unchanged: clear the error and look for cameras again.
      return Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, .14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color.fromRGBO(255, 255, 255, .2)),
              ),
              alignment: Alignment.center,
              child: const LenzIcon(LenzIcons.camera, size: 30, color: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(
              'Camera Unavailable',
              textAlign: TextAlign.center,
              style: LenzText.title.copyWith(color: Colors.white, fontSize: 19),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage.isNotEmpty
                  ? _errorMessage
                  : 'Something went wrong opening the camera. Please try again.',
              textAlign: TextAlign.center,
              style: LenzText.sub.copyWith(color: LenzColors.onDarkMuted, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            LenzPressable(
              semanticLabel: 'Retry Camera',
              onTap: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = '';
                });
                _initCameras();
              },
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(LenzRadii.buttonSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LenzIcon(LenzIcons.refresh, size: 18, color: LenzColors.forest),
                    const SizedBox(width: 8),
                    Text(
                      'Retry Camera',
                      style: LenzText.buttonSm.copyWith(color: LenzColors.forest),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: const CupertinoActivityIndicator(color: Colors.white, radius: 14),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera live feed filling 100% of container (BoxFit.cover) with pinch-to-zoom
        RepaintBoundary(
          key: _previewKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) {
              _scaleStartZoom = _currentZoom;
            },
            onScaleUpdate: (details) {
              final targetZoom = (_scaleStartZoom * details.scale).clamp(_minZoom, _maxZoom);
              setZoom(targetZoom);
            },
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previewSize = _controller!.value.previewSize;
                  if (previewSize == null) {
                    return CameraPreview(_controller!);
                  }

                  // In portrait, aspect ratio of camera preview is height / width
                  final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
                  final double previewWidth = isPortrait ? previewSize.height : previewSize.width;
                  final double previewHeight = isPortrait ? previewSize.width : previewSize.height;
                  final double previewAspect = previewWidth / previewHeight;

                  final double containerWidth = constraints.maxWidth;
                  final double containerHeight = constraints.maxHeight;
                  final double containerAspect = containerWidth / containerHeight;

                  // Calculate scale to completely cover the container
                  double scale = 1.0;
                  if (containerAspect > previewAspect) {
                    // Container is wider than camera preview ratio: scale by width
                    scale = containerWidth / (containerHeight * previewAspect);
                  } else {
                    // Container is taller than camera preview ratio: scale by height
                    scale = (containerHeight * previewAspect) / containerWidth;
                  }

                  return Center(
                    child: Transform.scale(
                      scale: scale,
                      child: AspectRatio(
                        aspectRatio: previewAspect,
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // The locked frame, drawn over the live preview from the shutter press.
        if (_frozenFrame != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RawImage(image: _frozenFrame, fit: BoxFit.fill),
            ),
          ),

        // Optional custom overlay (viewfinder reticles, instructions, etc.)
        if (widget.overlay != null) widget.overlay!,
      ],
    );
  }
}
