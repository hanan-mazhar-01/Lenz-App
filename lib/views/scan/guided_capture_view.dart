import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/evidence.dart';
import '../../viewmodels/scan_flow_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/camera/android_zoom_slider.dart';
import '../../widgets/camera/capture_guide_overlay.dart';
import 'camera_preview_widget.dart';
import '../../services/haptics.dart';

/// Camera screen for one requested photo. Shows the part to photograph, why,
/// a framing overlay, and distance / focus / lighting advice. The overlay is
/// only a framing aid: capture is always allowed and nothing checks alignment.
class GuidedCaptureView extends StatefulWidget {
  final EvidenceItem currentItem;
  final int currentIndex;
  final int totalCount;
  final void Function([String? photoPath])? onCapture;
  final VoidCallback? onSkip;
  final VoidCallback? onMarkUnavailable;
  final VoidCallback onBack;

  /// Which photo of the scan this will be (1-based), and the maximum.
  final int photoNumber;
  final int maxPhotos;

  /// 0-1 share of the evidence the leading result still needs.
  final double evidenceProgress;
  final String progressLabel;

  const GuidedCaptureView({
    super.key,
    required this.currentItem,
    required this.currentIndex,
    required this.totalCount,
    this.onCapture,
    this.onSkip,
    this.onMarkUnavailable,
    required this.onBack,
    this.photoNumber = 1,
    this.maxPhotos = 6,
    this.evidenceProgress = 0,
    this.progressLabel = '',
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
    if (mounted) setState(() => _isFlashOn = isTorch);
  }

  void _handleZoomChanged(double zoom) {
    setState(() => _zoomLevel = zoom);
    _cameraKey.currentState?.setZoom(zoom);
  }

  void _submit(String? path) {
    if (widget.onCapture != null) {
      widget.onCapture!(path);
    } else {
      context.read<ScanFlowViewModel>().submitEvidencePhoto(path);
    }
  }

  Future<void> _handleCapture() async {
    if (_isCapturing) return;
    Haptics.mediumImpact();
    setState(() => _isCapturing = true);
    String? capturedPath;
    try {
      capturedPath = (await _cameraKey.currentState?.takePicture())?.path;
    } catch (e) {
      debugPrint('[GuidedCaptureView] takePicture error: $e');
    }
    if (mounted) {
      setState(() => _isCapturing = false);
      _submit(capturedPath);
    }
  }

  Future<void> _pickFromGallery() async {
    Haptics.lightImpact();
    try {
      // Keep close to the original resolution: small engravings and label
      // text are lost if the photo is shrunk to 1920 px and recompressed.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (picked != null && mounted) _submit(picked.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open your photos. Check the Photos permission in Settings.")),
        );
      }
    }
  }

  void _showExample() {
    final item = widget.currentItem;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.warmIvory,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CaptureGuideIllustration(type: item.guideType, size: 96),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.nearBlack)),
                        const SizedBox(height: 4),
                        Text(item.guide, style: const TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.charcoalGray)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'This drawing shows what to frame. It is not a reference image of your model; no verified reference photo is available for it yet.',
                style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.softGray),
              ),
              if (item.aiChecks.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('What we will look at', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final c in item.aiChecks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $c', style: const TextStyle(fontSize: 13, color: AppColors.charcoalGray)),
                  ),
                const Text('Suggested by AI for this model; not independently verified.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.softGray)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.currentItem;
    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildProgress(),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.nearBlack, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.guide,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.charcoalGray, fontSize: 12.5, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final w = (constraints.maxWidth * 0.86).clamp(240.0, 380.0);
                final h = (constraints.maxHeight - 64).clamp(200.0, w * 1.15);
                return Column(
                  children: [
                    Center(
                      child: Container(
                        width: w,
                        height: h,
                        decoration: BoxDecoration(
                          color: AppColors.veryLightWarmGray,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(color: AppColors.nearBlack.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
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
                              CaptureGuideOverlay(
                                type: item.guideType,
                                label: 'Line up the part inside the guide. It is a framing aid only.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(height: 56, width: w, child: _buildTips(item)),
                  ],
                );
              }),
            ),
            _buildBottomControlCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildTips(EvidenceItem item) {
    Widget tip(IconData icon, String text) => Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 13, color: AppColors.deepForestGreen),
              const SizedBox(width: 4),
              Expanded(
                child: Text(text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, height: 1.2, color: AppColors.charcoalGray)),
              ),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _showExample,
          child: Column(
            children: [
              CaptureGuideIllustration(type: item.guideType, size: 40),
              const SizedBox(height: 2),
              const Text('Example', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.nearBlack)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        tip(CupertinoIcons.arrow_up_left_arrow_down_right, item.tips.distance),
        const SizedBox(width: 8),
        tip(CupertinoIcons.scope, item.tips.focus),
        const SizedBox(width: 8),
        tip(CupertinoIcons.sun_max, item.tips.lighting),
      ],
    );
  }

  Widget _circleButton({required VoidCallback onTap, required Widget child, Color? color}) => BounceButton(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color ?? AppColors.veryLightWarmGray,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.nearBlack.withOpacity(0.06)),
          ),
          child: Center(child: child),
        ),
      );

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          _circleButton(
            onTap: widget.onBack,
            child: const Icon(CupertinoIcons.chevron_back, color: AppColors.nearBlack, size: 18),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Capture Evidence',
                    style: TextStyle(color: AppColors.nearBlack, fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 3),
                Text(
                  'Photo ${widget.photoNumber} of up to ${widget.maxPhotos}',
                  style: const TextStyle(color: AppColors.charcoalGray, fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          _circleButton(
            onTap: _toggleFlash,
            color: _isFlashOn ? AppColors.deepForestGreen : null,
            child: Icon(_isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: _isFlashOn ? Colors.white : AppColors.nearBlack, size: 18),
          ),
        ],
      ),
    );
  }

  /// Progress of useful evidence, not of photos taken.
  Widget _buildProgress() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: widget.evidenceProgress.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: AppColors.nearBlack.withOpacity(0.08),
            valueColor: const AlwaysStoppedAnimation(AppColors.deepForestGreen),
          ),
        ),
        if (widget.progressLabel.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(widget.progressLabel,
              style: const TextStyle(fontSize: 11, color: AppColors.charcoalGray, fontWeight: FontWeight.w500)),
        ],
      ],
    );
  }

  Widget _labelledButton({required IconData icon, required String label, required VoidCallback onTap}) => BounceButton(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.nearBlack.withOpacity(0.07)),
              ),
              child: Center(child: Icon(icon, size: 22, color: AppColors.nearBlack)),
            ),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(color: AppColors.charcoalGray, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _buildBottomControlCard() {
    final item = widget.currentItem;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.veryLightWarmGray,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        border: Border(top: BorderSide(color: AppColors.nearBlack.withOpacity(0.05))),
        boxShadow: [BoxShadow(color: AppColors.nearBlack.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AndroidCameraZoomSlider(
            currentZoom: _zoomLevel,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            onZoomChanged: _handleZoomChanged,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _labelledButton(
                icon: item.screenshotOk ? Icons.screenshot_outlined : Icons.image_outlined,
                label: item.screenshotOk ? 'Screenshot' : 'Gallery',
                onTap: _pickFromGallery,
              ),
              BounceButton(
                scaleLower: 0.92,
                onTap: _handleCapture,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.pureWhite,
                    border: Border.all(color: AppColors.deepForestGreen, width: 3.5),
                    boxShadow: [
                      BoxShadow(color: AppColors.deepForestGreen.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 4)),
                    ],
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.deepForestGreen),
                    child: _isCapturing
                        ? const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 12))
                        : null,
                  ),
                ),
              ),
              _labelledButton(
                icon: CupertinoIcons.nosign,
                label: "Can't take",
                onTap: () {
                  Haptics.lightImpact();
                  (widget.onMarkUnavailable ?? widget.onSkip ?? widget.onBack)();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
