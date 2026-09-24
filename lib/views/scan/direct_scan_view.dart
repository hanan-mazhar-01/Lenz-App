import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../viewmodels/scan_flow_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/camera/android_zoom_slider.dart';
import 'camera_preview_widget.dart';
import '../../services/haptics.dart';

class DirectScanView extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String? imagePath)? onCapture;

  const DirectScanView({super.key, required this.onClose, this.onCapture});

  @override
  State<DirectScanView> createState() => _DirectScanViewState();
}

class _DirectScanViewState extends State<DirectScanView>
    with TickerProviderStateMixin {
  final GlobalKey<CameraPreviewWidgetState> _cameraKey =
      GlobalKey<CameraPreviewWidgetState>();
  CameraController? _cameraController;
  bool _isCapturing = false;
  bool _isFlashOn = false;
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 4.0;

  // Guidance pill animation (shows only once on open for a few seconds, then disappears)
  late AnimationController _guidanceAnimationController;
  late Animation<double> _guidanceAnimation;
  Timer? _guidanceTimer;

  @override
  void initState() {
    super.initState();
    _guidanceAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 1.0, // Visible when screen initially opens
    );
    _guidanceAnimation = CurvedAnimation(
      parent: _guidanceAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Show once for 2.8 seconds, then fade out permanently
    _guidanceTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) {
        _guidanceAnimationController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _guidanceTimer?.cancel();
    _guidanceAnimationController.dispose();
    super.dispose();
  }

  void _dismissGuidance() {
    _guidanceTimer?.cancel();
    if (_guidanceAnimationController.value > 0.0) {
      _guidanceAnimationController.reverse();
    }
  }

  Future<void> _toggleFlash() async {
    Haptics.lightImpact();
    _dismissGuidance();
    final isTorch = await _cameraKey.currentState?.toggleFlash() ?? false;
    if (mounted) {
      setState(() {
        _isFlashOn = isTorch;
      });
    }
  }

  Future<void> _flipCamera() async {
    Haptics.selectionClick();
    _dismissGuidance();
    await _cameraKey.currentState?.flipCamera();
  }

  void _handleZoomChanged(double zoom) {
    setState(() => _zoomLevel = zoom);
    _cameraKey.currentState?.setZoom(zoom);
    _dismissGuidance();
  }

  Future<void> _handleCapture() async {
    if (_isCapturing) return;
    Haptics.mediumImpact();
    _dismissGuidance();

    setState(() => _isCapturing = true);

    String? capturedPath;
    try {
      final xFile = await _cameraKey.currentState?.takePicture();
      if (xFile != null) {
        capturedPath = xFile.path;
      }
    } catch (e) {
      debugPrint('[DirectScanView] takePicture error: $e');
    }

    if (mounted) {
      setState(() => _isCapturing = false);
      if (widget.onCapture != null) {
        widget.onCapture!(capturedPath);
      } else {
        context.read<ScanFlowViewModel>().captureInitialPhoto(
          imagePath: capturedPath,
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    Haptics.lightImpact();
    _dismissGuidance();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (picked != null && mounted) {
        if (widget.onCapture != null) {
          widget.onCapture!(picked.path);
        } else {
          context.read<ScanFlowViewModel>().captureInitialPhoto(
            imagePath: picked.path,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DirectScanView] Gallery pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn\'t access your photo library. If you denied access, '
              'enable Photos permission in your device Settings.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final viewfinderWidth = (screenWidth * 0.78).clamp(280.0, 350.0);
    final viewfinderHeight = viewfinderWidth * 1.05;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ─── 1. Background: Live Camera Feed Blurred ───
          Positioned.fill(
            child: IgnorePointer(child: _buildBlurredBackground(context)),
          ),

          // ─── 2. Foreground UI ───
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Top Bar: [X]  [Scan Product + Subtitle]  [Flash]
                _buildTopBar(context),

                // Middle Viewport: Perfectly Centered Viewfinder + Floating Guidance Pill
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Centered Viewfinder Card
                      Center(
                        child: _buildViewfinder(
                          viewfinderWidth,
                          viewfinderHeight,
                        ),
                      ),

                      // Floating Guidance Pill (positioned below viewfinder without altering its centering)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FadeTransition(
                            opacity: _guidanceAnimation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.25),
                                end: Offset.zero,
                              ).animate(_guidanceAnimation),
                              child: GestureDetector(
                                onTap: () {
                                  Haptics.lightImpact();
                                  _dismissGuidance();
                                },
                                child: _buildGuidancePill(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Control Card: Gallery, Shutter Button, Flip Camera, Zoom Slider
                _buildBottomControlCard(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Full-screen blurred live camera background
  Widget _buildBlurredBackground(BuildContext context) {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return Container(color: const Color(0xFF141618));
    }

    final previewSize = ctrl.value.previewSize;
    if (previewSize == null) {
      return Container(color: const Color(0xFF141618));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final double previewWidth = isPortrait
            ? previewSize.height
            : previewSize.width;
        final double previewHeight = isPortrait
            ? previewSize.width
            : previewSize.height;
        final double previewAspect = previewWidth / previewHeight;

        final double containerWidth = constraints.maxWidth;
        final double containerHeight = constraints.maxHeight;
        final double containerAspect = containerWidth / containerHeight;

        double scale = 1.0;
        if (containerAspect > previewAspect) {
          scale = containerWidth / (containerHeight * previewAspect);
        } else {
          scale = (containerHeight * previewAspect) / containerWidth;
        }

        // Scale by extra 1.25x so blur edges don't show bleed/vignetting at borders
        scale *= 1.25;

        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 25,
                  sigmaY: 25,
                  tileMode: TileMode.decal,
                ),
                child: Center(
                  child: Transform.scale(
                    scale: scale,
                    child: AspectRatio(
                      aspectRatio: previewAspect,
                      child: CameraPreview(ctrl),
                    ),
                  ),
                ),
              ),
            ),
            // Semi-transparent dark scrim for optimal readability of UI controls
            Container(color: Colors.black.withOpacity(0.42)),
          ],
        );
      },
    );
  }

  /// Sharp Center Viewfinder Card with Corner Reticle Brackets
  Widget _buildViewfinder(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.38),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Live camera feed
            CameraPreviewWidget(
              key: _cameraKey,
              onZoomChanged: (zoom) {
                if (mounted) setState(() => _zoomLevel = zoom);
                _dismissGuidance();
              },
              onControllerReady: (ctrl) {
                if (mounted) {
                  setState(() {
                    _cameraController = ctrl;
                    _zoomLevel = _cameraKey.currentState?.currentZoom ?? 1.0;
                    _minZoom = _cameraKey.currentState?.minZoom ?? 1.0;
                    _maxZoom = _cameraKey.currentState?.maxZoom ?? 4.0;
                  });
                }
              },
            ),

            // Reticle Brackets (4 corners)
            // Top-left: vibrant mint green accent
            _buildCornerBracket(
              top: 14,
              left: 14,
              color: const Color(0xFF22C55E),
              isTop: true,
              isLeft: true,
            ),
            // Top-right: clean white
            _buildCornerBracket(
              top: 14,
              right: 14,
              color: Colors.white.withOpacity(0.92),
              isTop: true,
              isLeft: false,
            ),
            // Bottom-left: clean white
            _buildCornerBracket(
              bottom: 14,
              left: 14,
              color: Colors.white.withOpacity(0.92),
              isTop: false,
              isLeft: true,
            ),
            // Bottom-right: clean white
            _buildCornerBracket(
              bottom: 14,
              right: 14,
              color: Colors.white.withOpacity(0.92),
              isTop: false,
              isLeft: false,
            ),
          ],
        ),
      ),
    );
  }

  /// 1. Top Bar matching luxury reference design
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Close button [X]
          BounceButton(
            onTap: widget.onClose,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  CupertinoIcons.xmark,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),

          // Title & Subtitle in Center
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.filter_center_focus_rounded,
                      size: 21,
                      color: Color(0xFF22C55E),
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Scan Product',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Place the item inside the frame and\ntake a clear photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11.5,
                    height: 1.25,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),

          // Flash button [⚡]
          BounceButton(
            onTap: _toggleFlash,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isFlashOn
                    ? const Color(0xFF22C55E)
                    : Colors.black.withOpacity(0.35),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isFlashOn
                      ? const Color(0xFF22C55E)
                      : Colors.white.withOpacity(0.20),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Reticle Corner Bracket (L-shape with rounded corner)
  Widget _buildCornerBracket({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required Color color,
    required bool isTop,
    required bool isLeft,
  }) {
    const double size = 38.0;
    const double thickness = 3.5;
    const double radius = 14.0;

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border(
            top: isTop
                ? BorderSide(color: color, width: thickness)
                : BorderSide.none,
            bottom: !isTop
                ? BorderSide(color: color, width: thickness)
                : BorderSide.none,
            left: isLeft
                ? BorderSide(color: color, width: thickness)
                : BorderSide.none,
            right: !isLeft
                ? BorderSide(color: color, width: thickness)
                : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: isTop && isLeft
                ? const Radius.circular(radius)
                : Radius.zero,
            topRight: isTop && !isLeft
                ? const Radius.circular(radius)
                : Radius.zero,
            bottomLeft: !isTop && isLeft
                ? const Radius.circular(radius)
                : Radius.zero,
            bottomRight: !isTop && !isLeft
                ? const Radius.circular(radius)
                : Radius.zero,
          ),
        ),
      ),
    );
  }

  /// Android-style Horizontal Zoom Slider: Quick Presets + Swipe Ruler
  Widget _buildZoomSlider() {
    return AndroidCameraZoomSlider(
      currentZoom: _zoomLevel,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      onZoomChanged: _handleZoomChanged,
    );
  }

  /// Status guidance pill: "Keep the item centered · Well lit and in focus"
  Widget _buildGuidancePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.nearBlack.withOpacity(0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.filter_center_focus_rounded,
            size: 22,
            color: Color(0xFF22C55E),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Keep the item centered',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Well lit and in focus',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.80),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 3. Bottom Control Card (Gallery, Shutter Button, Flip Camera, Mode Switcher)
  Widget _buildBottomControlCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.veryLightWarmGray,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        border: Border(
          top: BorderSide(
            color: AppColors.nearBlack.withOpacity(0.05),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Android Camera Zoom Slider above shutter
          _buildZoomSlider(),
          const SizedBox(height: 16),

          // Camera controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Gallery Button
              BounceButton(
                onTap: _pickFromGallery,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.pureWhite,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.nearBlack.withOpacity(0.07),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.nearBlack.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 25,
                          color: AppColors.nearBlack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Gallery',
                      style: TextStyle(
                        color: AppColors.charcoalGray,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Central Shutter Button
              BounceButton(
                scaleLower: 0.92,
                onTap: _handleCapture,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.pureWhite,
                    border: Border.all(
                      color: AppColors.deepForestGreen,
                      width: 3.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepForestGreen.withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.deepForestGreen,
                    ),
                    child: _isCapturing
                        ? const Center(
                            child: CupertinoActivityIndicator(
                              color: Colors.white,
                              radius: 12,
                            ),
                          )
                        : null,
                  ),
                ),
              ),

              // Flip Camera Button
              BounceButton(
                onTap: _flipCamera,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.pureWhite,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.nearBlack.withOpacity(0.07),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.nearBlack.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.flip_camera_ios_outlined,
                          size: 24,
                          color: AppColors.nearBlack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Flip Camera',
                      style: TextStyle(
                        color: AppColors.charcoalGray,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
