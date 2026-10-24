import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/evidence.dart';
import '../../viewmodels/scan_flow_viewmodel.dart';
import '../../widgets/camera/android_zoom_slider.dart';
import '../../widgets/camera/capture_guide_captions.dart';
import '../../widgets/camera/capture_guide_overlay.dart';
import '../../widgets/camera/lenz_camera_chrome.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';
import 'camera_preview_widget.dart';
import '../../services/haptics.dart';

/// Camera screen for one requested photo. The camera shows only the part
/// title with step dots, the framing guide with one short caption, one coach
/// line and the controls; the long advice (CaptureTips, example drawing) opens
/// in a bottom sheet from "Example" or a tip chip. The overlay is only a
/// framing aid: capture is always allowed and nothing checks alignment.
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

  /// Test-only stand-in for the live camera feed (widget tests have no
  /// camera). Production never sets it.
  @visibleForTesting
  final Widget? previewOverride;

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
    this.previewOverride,
  });

  @override
  State<GuidedCaptureView> createState() => _GuidedCaptureViewState();
}

class _GuidedCaptureViewState extends State<GuidedCaptureView> with SingleTickerProviderStateMixin {
  // White capture flash (presentation only).
  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  final GlobalKey<CameraPreviewWidgetState> _cameraKey = GlobalKey<CameraPreviewWidgetState>();
  bool _isFlashOn = false;
  bool _isCapturing = false;
  bool _frozen = false;
  bool _cameraUnavailable = false;
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
    if (!LenzMotion.reduced(context)) _flashController.forward(from: 0);
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
          const SnackBar(
            content: Text("Couldn't open your photos. Check the Photos permission in Settings."),
          ),
        );
      }
    }
  }

  void _showExample() {
    final item = widget.currentItem;
    Haptics.lightImpact();
    showLenzSheet<void>(
      context,
      builder: (context) =>
          _TipsSheet(item: item, photoNumber: widget.photoNumber, maxPhotos: widget.maxPhotos),
    );
  }

  /// Dim of the screen outside the guide (same colour the overlay paints).
  static const Color _dim = CaptureGuidePainter.scrimColor;

  @override
  Widget build(BuildContext context) {
    final item = widget.currentItem;
    final mq = MediaQuery.of(context);
    final compact = mq.size.height < 720;
    final total = widget.totalCount > 0 ? widget.totalCount : 1;
    final step = (widget.currentIndex + 1).clamp(1, total);
    return Scaffold(
      backgroundColor: LenzColors.camera,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: LenzCameraBackdrop()),
          Positioned.fill(child: _buildPreview()),
          Column(
            children: [
              ColoredBox(
                color: _dim,
                child: Padding(
                  padding: EdgeInsets.only(top: mq.padding.top, bottom: 10),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: LenzCaptureTopBar(
                      title: item.title,
                      step: step,
                      total: total,
                      onClose: widget.onBack,
                      onFlash: _toggleFlash,
                      flashOn: _isFlashOn,
                    ),
                  ),
                ),
              ),
              // The framing guide for this part: a framing aid only, nothing
              // checks alignment and capture is always allowed.
              Expanded(
                child: _cameraUnavailable
                    ? const SizedBox.expand()
                    : MediaQuery.withClampedTextScaling(
                        maxScaleFactor: compact ? 1.15 : 1.3,
                        child: CaptureGuideOverlay(
                          type: item.guideType,
                          label: captureGuideCaption(item.guideType),
                          animate: true,
                          frozen: _frozen || _isCapturing,
                        ),
                      ),
              ),
              ColoredBox(
                color: _dim,
                // Capped text scale so the guide keeps room to frame the part.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: compact ? 1.15 : 1.3,
                  child: _buildBottom(item, compact, mq.padding.bottom),
                ),
              ),
            ],
          ),
          Positioned.fill(child: LenzCaptureFlash(animation: _flashController)),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return widget.previewOverride ??
        CameraPreviewWidget(
          key: _cameraKey,
          onZoomChanged: (zoom) {
            if (mounted) setState(() => _zoomLevel = zoom);
          },
          onUnavailableChanged: (v) {
            if (mounted) setState(() => _cameraUnavailable = v);
          },
          onFrozenChanged: (v) {
            if (mounted) setState(() => _frozen = v);
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
        );
  }

  Widget _buildBottom(EvidenceItem item, bool compact, double safeBottom) {
    Widget chip(Widget icon, String label) => LenzGlassPill(
      label: label,
      leading: icon,
      height: 34,
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      semanticLabel: '$label tips',
      onTap: _showExample,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(0, compact ? 10 : 14, 0, safeBottom + (compact ? 10 : 16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // One coach line; the long advice is in the sheet.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                LenzCoachAvatar(mood: _isCapturing ? LenzMood.shocked : LenzMood.idle),
                const SizedBox(width: 10),
                Expanded(
                  child: _CoachBubble(key: ValueKey(item.id), text: _coachLine(item.guide)),
                ),
                const SizedBox(width: 10),
                LenzGlassPill(
                  label: 'Example',
                  leading: const LenzIcon(
                    LenzIcons.info,
                    size: 17,
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                  onTap: _showExample,
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          AndroidCameraZoomSlider(
            currentZoom: _zoomLevel,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            onZoomChanged: _handleZoomChanged,
            dark: true,
          ),
          SizedBox(height: compact ? 8 : 12),
          // Neutral reminders: the app measures none of these.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  chip(const LenzCamIcon(LenzCamIcons.sun, size: 16), 'Light'),
                  const SizedBox(width: 8),
                  chip(const LenzCamIcon(LenzCamIcons.focus, size: 16), 'Focus'),
                  const SizedBox(width: 8),
                  chip(const LenzCamIcon(LenzCamIcons.glare, size: 16), 'Glare'),
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: LenzIconButton(
                      icon: LenzIcons.image,
                      dark: true,
                      radius: 22,
                      iconSize: 22,
                      onTap: _pickFromGallery,
                      semanticLabel: item.screenshotOk ? 'Screenshot' : 'Gallery',
                    ),
                  ),
                ),
                LenzShutterButton(onTap: _handleCapture, busy: _isCapturing, size: 78),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: LenzGlassPill(
                      label: 'Skip',
                      semanticLabel: "Can't take this photo",
                      height: 44,
                      fontSize: 13,
                      leading: const LenzCamIcon(LenzCamIcons.flip, size: 17),
                      onTap: () {
                        Haptics.lightImpact();
                        (widget.onMarkUnavailable ?? widget.onSkip ?? widget.onBack)();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// First clause of the part's own photo instruction, so the bubble stays one
/// short line; the sheet shows the whole instruction.
String _coachLine(String guide) {
  final t = guide.trim();
  final m = RegExp(r'[,;.:]').firstMatch(t);
  final first = m == null ? t : t.substring(0, m.start).trim();
  return first.isEmpty ? t : first;
}

/// The coach's speech bubble (mock `.coach .say`): white, tail bottom-left,
/// popping in and typing the part's own photo instruction out character by
/// character (the sheet repeats it in full). Re-types for every part because
/// the caller keys it by the evidence item.
class _CoachBubble extends StatelessWidget {
  const _CoachBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Align(
        alignment: Alignment.centerLeft,
        child: LenzBubble(
          text: text,
          maxWidth: c.maxWidth,
          popDelay: const Duration(milliseconds: 120),
          typeDelay: const Duration(milliseconds: 260),
          style: LenzText.item.copyWith(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: LenzColors.ink,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with everything the camera no longer shows: the drawn
/// example, the three CaptureTips lines in full, what we will look at, and
/// the framing-aid footer. Advice only: none of it is measured.
class _TipsSheet extends StatelessWidget {
  const _TipsSheet({required this.item, required this.photoNumber, required this.maxPhotos});

  final EvidenceItem item;
  final int photoNumber;
  final int maxPhotos;

  @override
  Widget build(BuildContext context) {
    Widget tip(Widget icon, String text) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: LenzShadows.sh1,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: LenzColors.mint2,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: icon,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: LenzText.item.copyWith(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const LenzCoachAvatar(size: 56, ring: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: LenzText.title.copyWith(fontSize: 20)),
                  Text(
                    'Photo $photoNumber of up to $maxPhotos',
                    style: LenzText.sub.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (item.guide.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(item.guide, style: LenzText.sub.copyWith(fontSize: 13.5, height: 1.35)),
        ],
        Container(
          margin: const EdgeInsets.fromLTRB(0, 14, 0, 6),
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF173D2E), Color(0xFF0C2219)],
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: CaptureGuidePainter(type: item.guideType, scrim: false),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: LenzColors.ok,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LenzIcon(
                        LenzIcons.check,
                        size: 13,
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'What to frame',
                        style: LenzText.cap.copyWith(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'This drawing shows what to frame. It is not a reference image of your model; no verified reference photo is available for it yet.',
            style: LenzText.tiny.copyWith(fontSize: 12, height: 1.35),
          ),
        ),
        tip(
          const LenzIcon(LenzIcons.scan, size: 20, strokeWidth: 2.1, color: LenzColors.forest2),
          item.tips.distance,
        ),
        tip(
          const LenzCamIcon(
            LenzCamIcons.focus,
            size: 20,
            strokeWidth: 2.1,
            color: LenzColors.forest2,
          ),
          item.tips.focus,
        ),
        tip(
          const LenzCamIcon(
            LenzCamIcons.sun,
            size: 20,
            strokeWidth: 2.1,
            color: LenzColors.forest2,
          ),
          item.tips.lighting,
        ),
        if (item.aiChecks.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('What we will look at', style: LenzText.item.copyWith(fontSize: 14.5)),
          const SizedBox(height: 6),
          for (final c in item.aiChecks)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $c',
                style: LenzText.sub.copyWith(fontSize: 13, color: LenzColors.ink),
              ),
            ),
          Text(
            'Suggested by AI for this model; not independently verified.',
            style: LenzText.tiny.copyWith(fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 12),
        LenzButton(label: 'Got it', onPressed: () => Navigator.of(context).pop()),
        const SizedBox(height: 10),
        Text(
          'The guide is a framing aid only — it does not judge the photo.',
          textAlign: TextAlign.center,
          style: LenzText.tiny.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
