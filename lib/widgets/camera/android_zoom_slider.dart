import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/haptics.dart';

/// Android-style camera zoom selector featuring quick preset buttons
/// and a horizontal swipeable/scrollable ruler dial.
class AndroidCameraZoomSlider extends StatefulWidget {
  final double currentZoom;
  final double minZoom;
  final double maxZoom;
  final ValueChanged<double> onZoomChanged;

  const AndroidCameraZoomSlider({
    super.key,
    required this.currentZoom,
    this.minZoom = 1.0,
    this.maxZoom = 4.0,
    required this.onZoomChanged,
  });

  @override
  State<AndroidCameraZoomSlider> createState() => _AndroidCameraZoomSliderState();
}

class _AndroidCameraZoomSliderState extends State<AndroidCameraZoomSlider> {
  bool _isDragging = false;
  double _dragStartZoom = 1.0;
  double _dragStartX = 0.0;
  int _lastHapticTick = 0;

  void _onDragStart(DragStartDetails details) {
    _isDragging = true;
    _dragStartZoom = widget.currentZoom;
    _dragStartX = details.localPosition.dx;
    _lastHapticTick = (widget.currentZoom * 10).round();
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // 180 horizontal pixels traverses roughly 3.0x zoom
    final double deltaX = details.localPosition.dx - _dragStartX;
    const double sensitivity = 0.012;
    final double targetZoom = (_dragStartZoom + (deltaX * sensitivity))
        .clamp(widget.minZoom, widget.maxZoom);

    final int tick = (targetZoom * 10).round();
    if (tick != _lastHapticTick) {
      _lastHapticTick = tick;
      Haptics.selectionClick();
    }

    widget.onZoomChanged(targetZoom);
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildScrollRuler();
  }

  Widget _buildScrollRuler() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () => setState(() => _isDragging = false),
      child: Container(
        width: 260,
        height: 38,
        decoration: BoxDecoration(
          color: _isDragging
              ? AppColors.pureWhite
              : AppColors.pureWhite.withOpacity(0.85),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: _isDragging
                ? AppColors.deepForestGreen.withOpacity(0.35)
                : AppColors.nearBlack.withOpacity(0.06),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Sliding ruler ticks painter
              CustomPaint(
                size: const Size(260, 38),
                painter: _RulerPainter(
                  currentZoom: widget.currentZoom,
                  minZoom: widget.minZoom,
                  maxZoom: widget.maxZoom,
                ),
              ),

              // Center indicator needle (accent color with zoom readout bubble)
              Positioned(
                top: 0,
                bottom: 0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 2.5,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.deepForestGreen,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.deepForestGreen.withOpacity(0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Dynamic Zoom Value pill shown while dragging or floating on top
              Positioned(
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.deepForestGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.currentZoom.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      color: AppColors.deepForestGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for horizontal scrollable tick marks
class _RulerPainter extends CustomPainter {
  final double currentZoom;
  final double minZoom;
  final double maxZoom;

  _RulerPainter({
    required this.currentZoom,
    required this.minZoom,
    required this.maxZoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;

    // 25 pixels per 0.1x zoom
    const double pixelsPerTenth = 6.0;

    final Paint minorPaint = Paint()
      ..color = AppColors.nearBlack.withOpacity(0.2)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final Paint majorPaint = Paint()
      ..color = AppColors.nearBlack.withOpacity(0.55)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final int minTenth = (minZoom * 10).round();
    final int maxTenth = (maxZoom * 10).round();
    final double currentTenth = currentZoom * 10;

    for (int t = minTenth; t <= maxTenth; t++) {
      final double x = centerX + ((t - currentTenth) * pixelsPerTenth);

      // Cull outside ruler bounds
      if (x < 10 || x > size.width - 10) continue;

      final bool isMajor = (t % 10 == 0); // whole numbers (1x, 2x, 3x)
      final bool isHalf = (t % 5 == 0 && !isMajor); // half numbers (1.5x, 2.5x)

      final double tickHeight = isMajor ? 16.0 : (isHalf ? 11.0 : 7.0);
      final Paint paint = isMajor ? majorPaint : minorPaint;

      // Fade out ticks near the edges for a smooth vignette look
      final double distFromCenter = (x - centerX).abs();
      final double maxDist = size.width / 2;
      final double alphaFactor = (1.0 - (distFromCenter / maxDist)).clamp(0.0, 1.0);

      paint.color = paint.color.withOpacity((isMajor ? 0.6 : 0.25) * alphaFactor);

      canvas.drawLine(
        Offset(x, centerY - (tickHeight / 2)),
        Offset(x, centerY + (tickHeight / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) {
    return oldDelegate.currentZoom != currentZoom ||
        oldDelegate.minZoom != minZoom ||
        oldDelegate.maxZoom != maxZoom;
  }
}
