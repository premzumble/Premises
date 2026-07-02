import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:premises/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Theme Switch & Rendering Performance Benchmark', (WidgetTester tester) async {
    // Ignore layout overflow warnings in benchmark logs
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };

    // Set desktop screen bounds to avoid view overflows
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;

    final List<double> frameTimes = [];

    // 1. Measure Startup/Boot Layout Time
    final startupStopwatch = Stopwatch()..start();
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    startupStopwatch.stop();
    final startupTimeMs = startupStopwatch.elapsedMilliseconds;

    // 2. Measure Theme Switch Frame times (Build + Layout + Paint)
    for (int i = 0; i < 5; i++) {
      // Toggle to dark
      themeNotifier.value = ThemeMode.dark;
      
      final sw1 = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 50));
      sw1.stop();
      frameTimes.add(sw1.elapsedMicroseconds / 1000.0);

      final sw2 = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 100));
      sw2.stop();
      frameTimes.add(sw2.elapsedMicroseconds / 1000.0);

      final sw3 = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 170));
      sw3.stop();
      frameTimes.add(sw3.elapsedMicroseconds / 1000.0);

      // Toggle to light
      themeNotifier.value = ThemeMode.light;

      final sw4 = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 50));
      sw4.stop();
      frameTimes.add(sw4.elapsedMicroseconds / 1000.0);

      final sw5 = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 100));
      sw5.stop();
      frameTimes.add(sw5.elapsedMicroseconds / 1000.0);

      final sw6 = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 170));
      sw6.stop();
      frameTimes.add(sw6.elapsedMicroseconds / 1000.0);
    }

    final totalFrames = frameTimes.length;
    final averageFrameTime = totalFrames > 0 
        ? frameTimes.reduce((a, b) => a + b) / totalFrames 
        : 0.0;
    final maxFrameTime = totalFrames > 0
        ? frameTimes.reduce((a, b) => a > b ? a : b)
        : 0.0;

    print('=== PERFORMANCE BENCHMARK RESULT ===');
    print('Startup Time: $startupTimeMs ms');
    print('Total Logged Frames: $totalFrames');
    print('Average Frame Time: ${averageFrameTime.toStringAsFixed(2)} ms');
    print('Max Frame Time (Peak Jank): ${maxFrameTime.toStringAsFixed(2)} ms');
    print('Estimated Framerate: ${(1000.0 / (averageFrameTime > 0 ? averageFrameTime : 16.6)).toStringAsFixed(1)} FPS');
    print('=====================================');

    // Reset view settings and error handler
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    FlutterError.onError = originalOnError;
  });
}
