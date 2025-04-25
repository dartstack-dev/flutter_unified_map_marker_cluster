import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart';

import 'recording_platform.dart';

final _clock = Stopwatch()..start();

void log(String tag, String message) => debugPrint('[$tag] +${_clock.elapsed.inMilliseconds}ms $message');

/// Waits until [condition] holds, at most [timeout] of wall-clock time. Each step lets real async work run (icon
/// rasterising, platform channels) and then pumps a frame. Works under `flutter test` and `integration_test`.
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed > timeout) return false;
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(step);
  }
  return true;
}

Future<void> pumpFor(WidgetTester tester, Duration duration) => pumpUntil(tester, () => false, timeout: duration);

/// Waits until no marker update reached the platform for [quiet] (longer than the 500 ms transitions).
Future<void> settleMarkers(
  WidgetTester tester,
  RecordingPlatform recorder, {
  Duration quiet = const Duration(milliseconds: 1500),
}) async {
  var count = -1;
  var stableSince = DateTime.now();
  final settled = await pumpUntil(tester, () {
    final now = recorder.markerUpdates.length + recorder.polylineUpdates.length;
    if (now != count) {
      count = now;
      stableSince = DateTime.now();
    }
    return DateTime.now().difference(stableSince) > quiet;
  }, timeout: const Duration(seconds: 20));
  expect(settled, isTrue, reason: 'marker updates did not settle within 20 s');
}

/// A tap the native map recognises as a tap: `tester.tapAt` stamps events with time 0, which Android turns into a
/// long press; the engine frame clock is the same monotonic clock as Android's uptime.
Future<void> nativeTap(WidgetTester tester, Offset position) async {
  final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
  final gesture = await tester.createGesture();
  await gesture.down(position, timeStamp: now);
  await tester.pump(const Duration(milliseconds: 60));
  await gesture.up(timeStamp: now + const Duration(milliseconds: 60));
}

const pinColor = Color(0xFFFF00FF);
const clusterColor = Color(0xFF00FF00);

/// Solid magenta disc: easy to find in a native snapshot.
class TestPin extends StatelessWidget {
  const TestPin({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: pinColor, shape: BoxShape.circle),
  );
}

/// Solid lime disc with the count (lime, unlike cyan, never shows up in a base map).
class TestBadge extends StatelessWidget {
  const TestBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: clusterColor, shape: BoxShape.circle),
    child: Center(
      child: Text(
        '$count',
        textDirection: TextDirection.ltr,
        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// A full-screen map with one cluster layer of [points], drawn with [TestPin] and [TestBadge].
class ClusterScene {
  ClusterScene(this.recorder, this.points);

  final RecordingPlatform recorder;
  final List<(String, LatLng)> points;
  final controller = MapController();
  final clusterTaps = <MarkerClusterNode>[];
  var ready = false;

  MapCamera get camera => controller.camera;

  late final markers = [
    for (final (id, point) in points)
      Marker(key: ValueKey(id), point: point, iconKey: 'test-pin', child: const TestPin()),
  ];

  Future<void> start(
    WidgetTester tester, {
    required LatLng center,
    required double zoom,
    int disableClusteringAtZoom = 20,
    int maxClusterRadius = 80,
    AnimationsOptions animations = const AnimationsOptions(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: UnifiedMap(
            mapController: controller,
            options: MapOptions(initialCenter: center, initialZoom: zoom, onMapReady: () => ready = true),
            children: [
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  markers: markers,
                  size: const Size(44, 44),
                  disableClusteringAtZoom: disableClusteringAtZoom,
                  maxClusterRadius: maxClusterRadius,
                  animationsOptions: animations,
                  builder: (context, markers) => TestBadge(markers.length),
                  onClusterTap: clusterTaps.add,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(await pumpUntil(tester, () => ready), isTrue, reason: 'map ready');
    await settleMarkers(tester, recorder);
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpFor(tester, const Duration(milliseconds: 200));
    controller.dispose();
  }
}
