import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/scan_flow_viewmodel.dart';
import '../../widgets/camera/android_zoom_slider.dart';
import '../../widgets/camera/lenz_camera_chrome.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';
import 'camera_preview_widget.dart';
import '../../services/haptics.dart';

class DirectScanView extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String? imagePath)? onCapture;

  /// Test-only stand-in for the live camera feed (widget tests have no
  /// camera). Production never sets it.
  @visibleForTesting
  final Widget? previewOverride;

  const DirectScanView({super.key, required this.onClose, this.onCapture, this.previewOverride});

  @override
  State<DirectScanView> createState() => _DirectScanViewState();
}

class _DirectScanViewState extends State<DirectScanView> with TickerProviderStateMixin {
  final GlobalKey<CameraPreviewWidgetState> _cameraKey = GlobalKey<CameraPreviewWidgetState>();
  bool _isCapturing = false;
  bool _frozen = false;
  bool _cameraUnavailable = false;
  bool _isCaptureSlow = false;
  Timer? _slowCaptureTimer;
  bool _isFlashOn = false;
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 4.0;

  // Guidance pill animation (shows only once on open for a few seconds, then disappears)
  late AnimationController _guidanceAnimationController;
  late Animation<double> _guidanceAnimation;
  Timer? _guidanceTimer;

  // White capture flash (presentation only).
  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

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
    _slowCaptureTimer?.cancel();
    _guidanceAnimationController.dispose();
    _flashController.dispose();
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
    if (!LenzMotion.reduced(context)) _flashController.forward(from: 0);
    // A capture that's still running after a couple of seconds isn't
    // frozen — but with no feedback it looks that way, so say so instead
    // of leaving the shutter button as the only (unchanged) thing on screen.
    _slowCaptureTimer?.cancel();
    _slowCaptureTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isCaptureSlow = true);
    });

    String? capturedPath;
    try {
      final xFile = await _cameraKey.currentState?.takePicture();
      if (xFile != null) {
        capturedPath = xFile.path;
      }
    } catch (e) {
      debugPrint('[DirectScanView] takePicture error: $e');
    }

    _slowCaptureTimer?.cancel();

    if (mounted) {
      setState(() {
        _isCapturing = false;
        _isCaptureSlow = false;
      });
      if (widget.onCapture != null) {
        widget.onCapture!(capturedPath);
      } else {
        context.read<ScanFlowViewModel>().captureInitialPhoto(imagePath: capturedPath);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    Haptics.lightImpact();
    _dismissGuidance();
    try {
      final picker = ImagePicker();
      // Near-original resolution: detail crops need the pixels.
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (picked != null && mounted) {
        if (widget.onCapture != null) {
          widget.onCapture!(picked.path);
        } else {
          context.read<ScanFlowViewModel>().captureInitialPhoto(imagePath: picked.path);
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
    final mq = MediaQuery.of(context);
    final compact = mq.size.height < 720;

    return Scaffold(
      backgroundColor: LenzColors.camera,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ─── 1. Camera scene + full-bleed live feed (prototype `.feed`) ───
          const Positioned.fill(child: LenzCameraBackdrop()),
          Positioned.fill(child: _buildPreview()),

          // ─── 2. Chrome ───
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                LenzCameraTopBar(
                  title: 'Scan product',
                  onClose: widget.onClose,
                  onFlash: _toggleFlash,
                  flashOn: _isFlashOn,
                ),
                Expanded(child: _buildViewport(compact)),
                _buildBottomControls(context, compact),
              ],
            ),
          ),

          // ─── 3. Capture flash ───
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
            _dismissGuidance();
          },
          onUnavailableChanged: (v) {
            if (mounted) setState(() => _cameraUnavailable = v);
          },
          onFrozenChanged: (v) {
            if (mounted) setState(() => _frozen = v);
          },
          onControllerReady: (ctrl) {
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

  /// Viewfinder brackets + static tip chips, then Lenz with his hint.
  Widget _buildViewport(bool compact) {
    final lenzWidth = compact ? 92.0 : 118.0;
    return LayoutBuilder(
      builder: (context, c) {
        // Lenz (bust) is ~0.96 x his width tall.
        final lenzHeight = lenzWidth * 0.96;
        final chips = _buildTipChips();
        final avail = c.maxHeight - lenzHeight - 56 - 24;
        final vf = (c.maxWidth * 0.76).clamp(120.0, avail.clamp(120.0, 340.0));
        return Stack(
          children: [
            if (!_cameraUnavailable)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: lenzHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: vf, maxHeight: vf),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: LenzViewfinder(frozen: _frozen || _isCapturing),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    chips,
                  ],
                ),
              ),
            if (!_cameraUnavailable)
              Positioned(
                left: 14,
                right: 14,
                bottom: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: lenzWidth,
                      child: LenzCharacter(
                        mood: _cameraUnavailable
                            ? LenzMood.sorry
                            : _isCapturing
                            ? LenzMood.shocked
                            : LenzMood.inspect,
                        view: LenzView.bust,
                      ),
                    ),
                    // Shows once on open for a few seconds, then fades (tap to dismiss).
                    if (!_cameraUnavailable)
                      Flexible(
                        child: FadeTransition(
                          opacity: _guidanceAnimation,
                          child: GestureDetector(
                            onTap: () {
                              Haptics.lightImpact();
                              _dismissGuidance();
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LenzBubble(
                                text: 'Center the item. Good light, in focus.',
                                dark: true,
                                maxWidth: 200,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// Advice only: the app does not measure light, centring or focus, so the
  /// chips stay neutral (they never turn green).
  Widget _buildTipChips() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          LenzTipChip(icon: LenzIcons.sparkles, label: 'Well lit'),
          LenzTipChip(icon: LenzIcons.scan, label: 'Centered'),
          LenzTipChip(icon: LenzIcons.eye, label: 'In focus'),
        ],
      ),
    );
  }

  /// Zoom ruler, then gallery / shutter / flip (prototype `.camctl`).
  Widget _buildBottomControls(BuildContext context, bool compact) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, compact ? 8 : 12, 24, bottom + (compact ? 14 : 24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reassurance for a capture that's taking longer than normal —
          // without this, a slow (but still working) shutter reads as frozen.
          if (_isCaptureSlow) ...[
            Text(
              'Still capturing…',
              style: LenzText.cap.copyWith(color: Colors.white.withValues(alpha: .85)),
            ),
            const SizedBox(height: 8),
          ],
          AndroidCameraZoomSlider(
            currentZoom: _zoomLevel,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            onZoomChanged: _handleZoomChanged,
            dark: true,
          ),
          SizedBox(height: compact ? 10 : 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              LenzCameraControl(
                icon: LenzIcons.image,
                onTap: _pickFromGallery,
                semanticLabel: 'Gallery',
              ),
              LenzShutterButton(onTap: _handleCapture, busy: _isCapturing),
              LenzCameraControl(
                icon: LenzIcons.refresh,
                onTap: _flipCamera,
                semanticLabel: 'Flip Camera',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
