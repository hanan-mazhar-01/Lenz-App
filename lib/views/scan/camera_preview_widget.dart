import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:provider/provider.dart';
import '../../services/storage_service.dart';

class CameraPreviewWidget extends StatefulWidget {
  final Widget? overlay;
  final ValueChanged<CameraController?>? onControllerReady;
  final ValueChanged<double>? onZoomChanged;

  const CameraPreviewWidget({
    super.key,
    this.overlay,
    this.onControllerReady,
    this.onZoomChanged,
  });

  @override
  State<CameraPreviewWidget> createState() => CameraPreviewWidgetState();
}

class CameraPreviewWidgetState extends State<CameraPreviewWidget>
    with WidgetsBindingObserver {
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      cameraController.dispose();
      _controller = null;
      _isInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      _initCameraController(_selectedCameraIndex);
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

  Future<void> _initCameraController(int cameraIndex) async {
    if (_cameras.isEmpty || cameraIndex >= _cameras.length) return;

    final oldController = _controller;
    if (oldController != null) {
      _controller = null;
      await oldController.dispose();
    }

    // "HD Multi-Angle Inspection" setting: veryHigh when on, medium when
    // off, so the toggle actually changes what gets captured instead of
    // always shooting at a single hardcoded preset regardless of its value.
    if (!mounted) return;
    final hdQuality = context.read<StorageService>().getBool('hd_quality', defaultValue: true);
    final newController = CameraController(
      _cameras[cameraIndex],
      hdQuality ? ResolutionPreset.veryHigh : ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await newController.initialize();
      await newController.setFlashMode(_flashMode);

      double minZ = 1.0;
      double maxZ = 4.0;
      try {
        minZ = await newController.getMinZoomLevel();
        maxZ = await newController.getMaxZoomLevel();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _controller = newController;
          _minZoom = minZ;
          _maxZoom = maxZ.clamp(1.0, 5.0);
          _currentZoom = minZ;
          _isInitialized = true;
          _hasError = false;
        });
        widget.onControllerReady?.call(newController);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] Camera init error: $e');
      }
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = _friendlyCameraError(e);
          _isInitialized = false;
        });
      }
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

  Future<XFile?> takePicture() async {
    if (!isInitialized || _controller == null) return null;
    if (_controller!.value.isTakingPicture) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] takePicture cancelled: camera is already capturing');
      }
      return null;
    }
    try {
      final file = await _controller!.takePicture();
      if (mounted && context.read<StorageService>().getBool('camera_sound', defaultValue: true)) {
        SystemSound.play(SystemSoundType.click);
      }
      return file;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CameraPreviewWidget] takePicture error: $e');
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.camera,
              size: 54,
              color: Colors.white.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Camera Unavailable',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage.isNotEmpty
                  ? _errorMessage
                  : 'Something went wrong opening the camera. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            CupertinoButton(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = '';
                });
                _initCameras();
              },
              child: const Text('Retry Camera', style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CupertinoActivityIndicator(
          color: Colors.white,
          radius: 14,
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera live feed filling 100% of container (BoxFit.cover) with pinch-to-zoom
        GestureDetector(
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

        // Optional custom overlay (viewfinder reticles, instructions, etc.)
        if (widget.overlay != null) widget.overlay!,
      ],
    );
  }
}
