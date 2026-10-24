import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/core/theme/app_theme.dart';

/// Loads the bundled Nunito weights so layout in tests uses the real metrics
/// (the default test font, Ahem, is far wider and would cause false overflow).
Future<void> loadNunito() async {
  final loader = FontLoader('Nunito');
  for (final f in const [
    'SemiBold',
    'Bold',
    'ExtraBold',
    'Black',
  ]) {
    final bytes = File('assets/fonts/Nunito-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Pumps [child] in the Lenz light theme on a phone-sized surface.
Future<void> pumpLenz(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double height = 640,
  double textScale = 1.3,
  bool disableAnimations = false,
  bool scaffold = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: c!,
      ),
      home: scaffold
          ? Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: child,
                ),
              ),
            )
          : child,
    ),
  );
}
