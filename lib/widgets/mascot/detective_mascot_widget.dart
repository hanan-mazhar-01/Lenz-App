import 'package:flutter/material.dart';
import 'detective_mascot.dart';

export 'detective_mascot.dart';

typedef MascotState = DetectiveMascotState;

/// Backward-compatible wrapper for DetectiveMascot
class DetectiveMascotWidget extends StatelessWidget {
  final MascotState state;
  final double size;
  final bool showHalo;
  final bool interactive;
  final bool triggerGlance;
  final VoidCallback? onTap;

  const DetectiveMascotWidget({
    super.key,
    this.state = MascotState.idle,
    this.size = 120,
    this.showHalo = false,
    this.interactive = false,
    this.triggerGlance = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DetectiveMascot(
      state: state,
      size: size,
      showHalo: showHalo,
      triggerGlance: triggerGlance,
      onTap: onTap,
    );
  }
}
