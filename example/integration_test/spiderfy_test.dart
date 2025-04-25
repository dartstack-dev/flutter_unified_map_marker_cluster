import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster_example/src/demo_data.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' as pi show Offset;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show
        PlatformCameraUpdateNewCamera,
        PlatformMapTapEvent,
        PlatformMarkerTapEvent,
        PlatformMarkerTransition,
        UnifiedMapsPlatform;
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';
import 'support/macos_test_window.dart';
import 'support/recording_platform.dart';
import 'support/visibility.dart';

void _log(String message) => log('spiderfy', message);

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

  /// The twelve-stack the spiderfy tests tap: every pin on the same point, so its cluster cannot be split by
  /// zooming and a tap spiderfies it.
  const spot = LatLng(50.8467, 4.3524);
  final points = [for (var i = 0; i < 12; i++) ('SP-${(i + 1).toString().padLeft(3, '0')}', spot)];

  /// The cluster nearest to [point] on screen.
  String nearestCluster(ClusterScene scene, LatLng point) {
    final camera = scene.camera;
    final target = camera.latLngToScreenOffset(point);
    final clusters = recorder.markers.values.where((m) => m.id.contains('/c')).toList()
      ..sort(
        (a, b) => (camera.latLngToScreenOffset(a.position) - target).distance.compareTo(
          (camera.latLngToScreenOffset(b.position) - target).distance,
        ),
      );
    return clusters.first.id;
  }

  /// Taps the native marker [id]: a real tap on Android; on iOS and macOS synthetic Flutter pointer events do not
  /// reach UIKit / AppKit platform views, so the native marker tap event is injected.
  Future<void> tapMarker(WidgetTester tester, ClusterScene scene, String id) async {
    final taps = scene.clusterTaps.length;
    if (!Platform.isAndroid) {
      recorder.inject(PlatformMarkerTapEvent(recorder.builtViews.keys.last, id));
    } else {
      final origin = tester.getTopLeft(find.byType(UnifiedMap));
      for (var attempt = 1; attempt <= 2; attempt++) {
        final events = recorder.receivedEvents.length;
        await nativeTap(tester, origin + scene.camera.latLngToScreenOffset(recorder.markers[id]!.position));
        if (await pumpUntil(tester, () => scene.clusterTaps.length > taps, timeout: const Duration(seconds: 3))) break;
        final after = recorder.receivedEvents.skip(events).toList();
        _log(
          'native tap $attempt on $id did not reach onClusterTap; platform events since: ${after.map((e) => e.runtimeType)}',
        );
        // A marker tap event that reached the layer without reaching onClusterTap is a dropped tap, not a touch
        // Android missed: retrying would hide it.
        expect(
          after.whereType<PlatformMarkerTapEvent>().where((e) => e.markerId == id),
          isEmpty,
          reason: 'the layer dropped a delivered tap on $id',
        );
      }
    }
    expect(
      await pumpUntil(tester, () => scene.clusterTaps.length > taps, timeout: const Duration(seconds: 3)),
      isTrue,
      reason: 'the cluster tap reached onClusterTap',
    );
  }

  /// Waits for the spider of [count] markers and its legs, and checks it is still open once everything settled.
  Future<Set<String>> expectSpider(WidgetTester tester, int count, int from, LatLng clusterPosition) async {
    final opened = await pumpUntil(
      tester,
      () => recorder.polylines.length == count,
      timeout: const Duration(seconds: 8),
    );
    expect(opened, isTrue, reason: 'the $count legs are drawn once the markers arrived');
    await settleMarkers(tester, recorder);
    final transitions = recorder.markerTransitions.skip(from).whereType<PlatformMarkerTransition>().toList();
    final leaves = {
      for (final t in transitions)
        for (final MapEntry(key: id, value: origin) in t.appearFrom.entries)
          if (origin == clusterPosition && id.contains('/k:')) id,
    };
    _log('appeared from the cluster: ${leaves.length}');
    expect(leaves, hasLength(count));
    expect(leaves.every(recorder.markers.containsKey), isTrue, reason: 'still open once the camera settled');
    expect(recorder.polylines, hasLength(count));
    for (final leg in recorder.polylines.values) {
      expect(leg.points.first, clusterPosition);
    }
    return leaves;
  }

  testWidgets('a centered stacked cluster spiderfies with legs and closes on a map tap', (tester) async {
    if (recorder.supportsFlutterMapLayers) {
      markTestSkipped('flutter_map backend: spiderfy is flutter_map_marker_cluster\'s own');
      return;
    }
    final scene = ClusterScene(recorder, points);
    await scene.start(tester, center: spot, zoom: 16, maxClusterRadius: 60);
    final viewId = recorder.builtViews.keys.last;

    final clusterId = nearestCluster(scene, spot);
    final clusterPosition = recorder.markers[clusterId]!.position;
    final from = recorder.markerTransitions.length;
    await tapMarker(tester, scene, clusterId);
    expect(scene.clusterTaps.single.markers, hasLength(12));
    final spiderLeaves = await expectSpider(tester, 12, from, clusterPosition);
    expect(
      recorder.markerTransitions.skip(from).whereType<PlatformMarkerTransition>().map((t) => t.duration),
      contains(const Duration(milliseconds: 500)),
    );

    final camera = scene.camera;
    final center = camera.latLngToScreenOffset(clusterPosition);
    final screen = [for (final id in spiderLeaves) camera.latLngToScreenOffset(recorder.markers[id]!.position)];
    for (final p in screen) {
      expect((p - center).distance, inInclusiveRange(10, 120), reason: 'spiral around the cluster');
    }
    expect({for (final p in screen) '${p.dx.round()},${p.dy.round()}'}, hasLength(12));

    var visibility = await checkVisibility(
      tester,
      binding,
      recorder,
      scene.controller,
      label: 'open',
      ignore: {clusterId},
    );
    _log('spider open: $visibility');
    expect(visibility.ok, isTrue, reason: '$visibility');

    final closeFrom = recorder.markerTransitions.length;
    recorder.inject(PlatformMapTapEvent(viewId, clusterPosition, const pi.Offset(5, 5)));
    final closed = await pumpUntil(
      tester,
      () => recorder.polylines.isEmpty && spiderLeaves.every((id) => !recorder.markers.containsKey(id)),
      timeout: const Duration(seconds: 5),
    );
    expect(closed, isTrue);
    final disappearTo = {
      for (final t in recorder.markerTransitions.skip(closeFrom).whereType<PlatformMarkerTransition>())
        ...t.disappearTo,
    };
    expect(disappearTo.keys.toSet(), spiderLeaves);
    expect(disappearTo.values.toSet(), {clusterPosition});
    expect(recorder.markers.containsKey(clusterId), isTrue);
    await settleMarkers(tester, recorder);
    visibility = await checkVisibility(tester, binding, recorder, scene.controller, label: 'closed');
    _log('spider closed: $visibility');
    expect(visibility.ok, isTrue, reason: '$visibility');
    await scene.stop(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('an off-center stacked cluster: the camera centers it, then the spider opens and stays open', (
    tester,
  ) async {
    if (recorder.supportsFlutterMapLayers) {
      markTestSkipped('flutter_map backend: spiderfy is flutter_map_marker_cluster\'s own');
      return;
    }
    final scene = ClusterScene(recorder, points);
    final start = LatLng(spot.latitude + 0.0012, spot.longitude - 0.0018);
    await scene.start(tester, center: start, zoom: 16, maxClusterRadius: 60);

    final clusterId = nearestCluster(scene, spot);
    final clusterPosition = recorder.markers[clusterId]!.position;
    final moves = recorder.cameraMoves.length;
    final from = recorder.markerTransitions.length;
    await tapMarker(tester, scene, clusterId);
    expect(
      await pumpUntil(tester, () => recorder.cameraMoves.length > moves, timeout: const Duration(seconds: 5)),
      isTrue,
    );
    final move = recorder.cameraMoves[moves].update as PlatformCameraUpdateNewCamera;
    _log('camera moved to ${move.center} zoom ${move.zoom}');
    expect(move.center!.latitude, closeTo(clusterPosition.latitude, 1e-6));
    expect(move.center!.longitude, closeTo(clusterPosition.longitude, 1e-6));
    await expectSpider(tester, 12, from, clusterPosition);
    final center = scene.camera.latLngToScreenOffset(clusterPosition);
    final size = scene.camera.nonRotatedSize;
    expect((center - size.center(Offset.zero)).distance, lessThan(8), reason: 'the cluster is centered');
    await scene.stop(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('a cluster that separates only beyond maxZoom: zooms to maxZoom, then spiderfies on the next tap', (
    tester,
  ) async {
    if (recorder.supportsFlutterMapLayers) {
      markTestSkipped('flutter_map backend: spiderfy is flutter_map_marker_cluster\'s own');
      return;
    }
    // A ring 6e-4° wide: one cluster up to zoom 17 (MarkerClusterLayerOptions.maxZoom), apart from zoom 18 on.
    const hub = brussels;
    final points = [
      for (var i = 0; i < 12; i++)
        (
          'ring$i',
          LatLng(
            hub.latitude + 2e-4 * math.sin(2 * math.pi * i / 12),
            hub.longitude + 3e-4 * math.cos(2 * math.pi * i / 12),
          ),
        ),
    ];
    final scene = ClusterScene(recorder, points);
    await scene.start(tester, center: hub, zoom: 15, maxClusterRadius: 60);
    final first = nearestCluster(scene, hub);

    final moves = recorder.cameraMoves.length;
    await tapMarker(tester, scene, first);
    expect(
      await pumpUntil(tester, () => recorder.cameraMoves.length > moves, timeout: const Duration(seconds: 5)),
      isTrue,
    );
    final zoomIn = recorder.cameraMoves[moves].update as PlatformCameraUpdateNewCamera;
    _log('first tap: camera to zoom ${zoomIn.zoom}');
    expect(zoomIn.zoom, closeTo(17, 1e-9));
    await pumpUntil(tester, () => (scene.camera.zoom - 17).abs() < 1e-3, timeout: const Duration(seconds: 5));
    await settleMarkers(tester, recorder);
    expect(recorder.polylines, isEmpty, reason: 'zooming in does not spiderfy');
    final clusters = recorder.markers.keys.where((id) => id.contains('/c')).toList();
    _log('settled at zoom ${scene.camera.zoom}: ${recorder.markers.length} markers, clusters $clusters');
    expect(clusters, hasLength(1), reason: 'still one cluster at zoom 17');

    final clusterPosition = recorder.markers[clusters.single]!.position;
    final from = recorder.markerTransitions.length;
    await tapMarker(tester, scene, clusters.single);
    await expectSpider(tester, 12, from, clusterPosition);
    await scene.stop(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
