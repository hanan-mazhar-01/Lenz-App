import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/authentication_rules.dart';
import '../../models/evidence.dart';
import '../../viewmodels/scan_flow_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/camera/android_zoom_slider.dart';
import 'camera_preview_widget.dart';
import '../../services/haptics.dart';

class GuidedCaptureView extends StatefulWidget {
  final EvidenceItem currentItem;
  final int currentIndex;
  final int totalCount;
  final void Function([String? photoPath])? onCapture;
  final VoidCallback? onSkip;
  final VoidCallback? onMarkUnavailable;
  final VoidCallback onBack;

  const GuidedCaptureView({
    super.key,
    required this.currentItem,
    required this.currentIndex,
    required this.totalCount,
    this.onCapture,
    this.onSkip,
    this.onMarkUnavailable,
    required this.onBack,
  });

  @override
  State<GuidedCaptureView> createState() => _GuidedCaptureViewState();
}

class _GuidedCaptureViewState extends State<GuidedCaptureView> {
  final GlobalKey<CameraPreviewWidgetState> _cameraKey = GlobalKey<CameraPreviewWidgetState>();
  bool _isFlashOn = false;
  bool _isCapturing = false;
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 4.0;

  Future<void> _toggleFlash() async {
    Haptics.lightImpact();
    final isTorch = await _cameraKey.currentState?.toggleFlash() ?? false;
    if (mounted) {
      setState(() {
        _isFlashOn = isTorch;
      });
    }
  }

  void _handleZoomChanged(double zoom) {
    setState(() => _zoomLevel = zoom);
    _cameraKey.currentState?.setZoom(zoom);
  }

  Future<void> _handleCapture() async {
    if (_isCapturing) return;
    Haptics.mediumImpact();
    setState(() => _isCapturing = true);

    String? capturedPath;
    try {
      final xFile = await _cameraKey.currentState?.takePicture();
      if (xFile != null) {
        capturedPath = xFile.path;
      }
    } catch (e) {
      debugPrint('[GuidedCaptureView] takePicture error: $e');
    }

    if (mounted) {
      setState(() => _isCapturing = false);
      if (widget.onCapture != null) {
        widget.onCapture!(capturedPath);
      } else {
        context.read<ScanFlowViewModel>().submitEvidencePhoto(capturedPath);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    Haptics.lightImpact();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 88,
      );
      if (picked != null && mounted) {
        if (widget.onCapture != null) {
          widget.onCapture!(picked.path);
        } else {
          context.read<ScanFlowViewModel>().submitEvidencePhoto(picked.path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.currentItem;
    final screenWidth = MediaQuery.of(context).size.width;
    final viewfinderWidth = (screenWidth * 0.80).clamp(280.0, 360.0);
    final viewfinderHeight = viewfinderWidth * 1.06;

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── Top bar: Back, Title, Skip + Flash
            _buildTopBar(context),

            // ─── Middle: Viewfinder + Progress + Guidance
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 6),

                      // ─── Progress indicator line
                      _buildProgressIndicator(),

                      const SizedBox(height: 10),

                      // ─── Current evidence text
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.guide,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.charcoalGray,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Viewfinder Card with camera preview + reticle
                      Center(
                        child: Container(
                          width: viewfinderWidth,
                          height: viewfinderHeight,
                          decoration: BoxDecoration(
                            color: AppColors.veryLightWarmGray,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.nearBlack.withOpacity(0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CameraPreviewWidget(
                                  key: _cameraKey,
                                  onZoomChanged: (zoom) {
                                    if (mounted) setState(() => _zoomLevel = zoom);
                                  },
                                  onControllerReady: (_) {
                                    if (mounted) {
                                      setState(() {
                                        _zoomLevel = _cameraKey.currentState?.currentZoom ?? 1.0;
                                        _minZoom = _cameraKey.currentState?.minZoom ?? 1.0;
                                        _maxZoom = _cameraKey.currentState?.maxZoom ?? 4.0;
                                      });
                                    }
                                  },
                                ),

                                // Framing guide
                                Center(
                                  child: Builder(
                                    builder: (context) {
                                      final frame = CaptureFrame.forEvidence(item.id, title: item.title);
                                      final width = viewfinderWidth * 0.65;
                                      final height = width * frame.aspect;
                                      final isCircle = frame == CaptureFrame.circle;
                                      return Container(
                                        width: width,
                                        height: height,
                                        decoration: BoxDecoration(
                                          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                                          borderRadius: isCircle ? null : BorderRadius.circular(16),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.55),
                                            width: 1.6,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                // "Place the item inside the frame" pill at bottom
                                Positioned(
                                  bottom: 12,
                                  left: 14,
                                  right: 14,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      'Place the item inside the frame',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),

            // ─── Bottom controls: Zoom + Shutter row
            _buildBottomControlCard(context),
          ],
        ),
      ),
    );
  }

  /// Top bar: [←] [Capture Evidence + step count] [Skip] [Flash]
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Back button
          BounceButton(
            onTap: widget.onBack,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.veryLightWarmGray,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.nearBlack.withOpacity(0.06),
                ),
              ),
              child: const Center(
                child: Icon(
                  CupertinoIcons.chevron_back,
                  color: AppColors.nearBlack,
                  size: 18,
                ),
              ),
            ),
          ),

          // Center title + step counter
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt_rounded,
                      size: 18,
                      color: AppColors.deepForestGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Capture Evidence',
                      style: const TextStyle(
                        color: AppColors.nearBlack,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.currentIndex + 1} of ${widget.totalCount}',
                  style: const TextStyle(
                    color: AppColors.charcoalGray,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Flash button (Skip removed)
          BounceButton(
            onTap: _toggleFlash,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _isFlashOn ? AppColors.deepForestGreen : AppColors.veryLightWarmGray,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.nearBlack.withOpacity(0.06),
                ),
              ),
              child: Center(
                child: Icon(
                  _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _isFlashOn ? Colors.white : AppColors.nearBlack,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Progress indicator: small segments for each evidence item
  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(widget.totalCount, (i) {
          final isActive = i == widget.currentIndex;
          final isCompleted = i < widget.currentIndex;
          return Expanded(
            child: Container(
              height: 3.5,
              margin: EdgeInsets.only(right: i < widget.totalCount - 1 ? 4 : 0),
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.deepForestGreen
                    : isActive
                        ? AppColors.deepForestGreen.withOpacity(0.5)
                        : AppColors.nearBlack.withOpacity(0.08),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Bottom control card: zoom row + shutter + gallery/info
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
            color: AppColors.nearBlack.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 38),
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
              // Gallery button
              BounceButton(
                onTap: _pickFromGallery,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.pureWhite,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.nearBlack.withOpacity(0.07),
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 23,
                          color: AppColors.nearBlack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Gallery',
                      style: TextStyle(
                        color: AppColors.charcoalGray,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Shutter button
              BounceButton(
                scaleLower: 0.92,
                onTap: _handleCapture,
                child: Container(
                  width: 76,
                  height: 76,
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

              // "I don't have this" button
              if (widget.onMarkUnavailable != null)
                BounceButton(
                  onTap: () {
                    Haptics.lightImpact();
                    widget.onMarkUnavailable!();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.pureWhite,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.nearBlack.withOpacity(0.07),
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            CupertinoIcons.nosign,
                            size: 20,
                            color: AppColors.nearBlack,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        "Don't have",
                        style: TextStyle(
                          color: AppColors.charcoalGray,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              else
                BounceButton(
                  onTap: () {
                    Haptics.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(widget.currentItem.reason.isNotEmpty
                            ? widget.currentItem.reason
                            : widget.currentItem.guide),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.pureWhite,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.nearBlack.withOpacity(0.07),
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            CupertinoIcons.info,
                            size: 20,
                            color: AppColors.nearBlack,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Tip',
                        style: TextStyle(
                          color: AppColors.charcoalGray,
                          fontSize: 11,
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

  /// Android-style Horizontal Zoom Slider: Quick Presets + Swipe Ruler
  Widget _buildZoomSlider() {
    return AndroidCameraZoomSlider(
      currentZoom: _zoomLevel,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      onZoomChanged: _handleZoomChanged,
    );
  }
}
