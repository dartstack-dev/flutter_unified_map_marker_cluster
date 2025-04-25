import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster_example/src/demo_data.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show UnifiedMapsPlatform;
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';
import 'support/macos_test_window.dart';
import 'support/recording_platform.dart';
import 'support/visibility.dart';

typedef _Step = ({String name, LatLng center, double zoom, bool animated, int burst, double rotation});

void _log(String message) => log('visibility', message);

/// Regression test for pins missing on the native map: every marker the layer publishes must be drawn, at every
/// step of a tour of zooms, pans, bursts of moves and rotations over the demo pins.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  holdMacOSTestWindowInFront();

  late UnifiedMapsPlatform real;
  late RecordingPlatform recorder;

  setUp(() {
    real = UnifiedMapsPlatform.instance;
    recorder = RecordingPlatform(real);
    UnifiedMapsPlatform.instance = recorder;
  });

  tearDown(() => UnifiedMapsPlatform.instance = real);

  testWidgets('every published marker stays visible while zooming and panning', (tester) async {
    if (recorder.supportsFlutterMapLayers) {
      markTestSkipped('flutter_map backend: clusters are drawn by flutter_map_marker_cluster, not as native markers');
      return;
    }
    final pins = generatePins();
    final points = [for (final s in pins) (s.id, s.point)];
    final scene = ClusterScene(recorder, points);
    await scene.start(tester, center: const LatLng(48.5, 9.0), zoom: 4.6, disableClusteringAtZoom: 10);
    final controller = scene.controller;

    final steps = <_Step>[
      (name: 'start', center: const LatLng(48.5, 9.0), zoom: 4.6, animated: false, burst: 0, rotation: 0),
      (name: 'z6', center: const LatLng(48.5, 9.0), zoom: 6, animated: false, burst: 0, rotation: 0),
      (name: 'munich z8', center: const LatLng(48.14, 11.58), zoom: 8, animated: false, burst: 0, rotation: 0),
      (name: 'munich z11', center: const LatLng(48.14, 11.58), zoom: 11, animated: false, burst: 0, rotation: 0),
      (name: 'pan munich z10', center: const LatLng(48.30, 11.20), zoom: 10, animated: true, burst: 0, rotation: 0),
      (name: 'z7', center: const LatLng(48.30, 11.20), zoom: 7, animated: true, burst: 0, rotation: 0),
      (name: 'paris z9', center: const LatLng(48.86, 2.35), zoom: 9, animated: true, burst: 0, rotation: 0),
      (name: 'paris z10.5', center: const LatLng(48.86, 2.35), zoom: 10.5, animated: true, burst: 0, rotation: 0),
      (name: 'paris z8', center: const LatLng(48.86, 2.35), zoom: 8, animated: false, burst: 0, rotation: 0),
      (name: 'burst zoom in', center: const LatLng(48.86, 2.35), zoom: 11, animated: true, burst: 8, rotation: 0),
      (name: 'burst instant', center: const LatLng(52.52, 13.40), zoom: 10, animated: false, burst: 10, rotation: 0),
      (name: 'burst instant out', center: const LatLng(50.0, 8.0), zoom: 6, animated: false, burst: 10, rotation: 0),
    ];
    final random = math.Random(7);
    final hubs = [for (final s in pins.take(40)) s.point];
    for (var i = 0; i < 4; i++) {
      final hub = hubs[random.nextInt(hubs.length)];
      final zoom = 5 + random.nextDouble() * 7.5;
      steps.add((
        name: 'random $i',
        center: LatLng(hub.latitude + random.nextDouble() * 0.2 - 0.1, hub.longitude + random.nextDouble() * 0.2 - 0.1),
        zoom: zoom,
        animated: random.nextBool(),
        burst: random.nextInt(3) == 0 ? 6 : 0,
        rotation: zoom >= 9 && random.nextBool() ? random.nextDouble() * 60 - 30 : 0,
      ));
    }

    final failures = <String>[];
    for (final (index, step) in steps.indexed) {
      final from = controller.camera;
      for (var i = 1; i <= step.burst; i++) {
        final t = i / (step.burst + 1);
        final center = LatLng(
          from.center.latitude + (step.center.latitude - from.center.latitude) * t,
          from.center.longitude + (step.center.longitude - from.center.longitude) * t,
        );
        final zoom = from.zoom + (step.zoom - from.zoom) * t;
        if (step.animated) {
          unawaited(controller.animateTo(dest: center, zoom: zoom, duration: const Duration(milliseconds: 250)));
        } else {
          controller.move(center, zoom);
        }
        await pumpFor(tester, Duration(milliseconds: 60 + random.nextInt(300)));
      }
      if (step.animated) {
        unawaited(controller.animateTo(dest: step.center, zoom: step.zoom));
      } else {
        controller.move(step.center, step.zoom);
      }
      await pumpFor(tester, const Duration(milliseconds: 300));
      if (step.rotation != controller.camera.rotation) {
        await pumpFor(tester, const Duration(milliseconds: 600));
        unawaited(controller.animateTo(rotation: step.rotation));
        await pumpFor(tester, const Duration(milliseconds: 300));
      }
      await settleMarkers(tester, recorder);
      final result = await checkVisibility(
        tester,
        binding,
        recorder,
        controller,
        label: '$index',
        allPoints: points,
        clusteringOffAbove: 10,
      );
      _log('step $index ${step.name}: zoom ${controller.camera.zoom.toStringAsFixed(2)}, $result');
      if (!result.ok) {
        failures.add('step $index ${step.name}: $result');
        _log('  snapshot at ${recorder.clock.elapsed.inMilliseconds} ms');
        for (final id in [...result.snapshotMissing, ...?result.screenMissing]) {
          final screen = controller.camera.latLngToScreenOffset(recorder.markers[id]!.position);
          _log('  at (${screen.dx.round()}, ${screen.dy.round()}) of ${controller.camera.nonRotatedSize}');
          _log('  ${recorder.historyOf(id)}');
        }
      }
    }
    _log('failures: ${failures.length}');
    for (final failure in failures) {
      _log('  $failure');
    }
    expect(failures, isEmpty);
    await scene.stop(tester);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
