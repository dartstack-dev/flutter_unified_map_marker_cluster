import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map_marker_cluster/src/core/spiderfy.dart' as upstream;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart';
import 'package:flutter_unified_map_marker_cluster/src/core/spiderfy.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import 'support/fake_platform.dart';
import 'support/harness.dart';

const _red = Color(0xFFFF0000);

Marker _marker(String name, LatLng point, {VoidCallback? onTap}) =>
    Marker(key: ValueKey(name), point: point, iconKey: 'dot', onTap: onTap, child: const Dot(_red));

List<Marker> _trioMarkers() => [
  _marker('p1', const LatLng(48.0, 2.0)),
  _marker('p2', const LatLng(48.0, 2.2)),
  _marker('p3', const LatLng(48.05, 3.0)),
];

final _trio = _trioMarkers();

const _center = LatLng(48.0, 2.5);

PlatformCamera _at(double zoom, {LatLng center = _center}) => PlatformCamera(center: center, zoom: zoom);

bool _isCluster(String id) => id.contains('/c');

String _name(String id) => id.substring(id.indexOf('/') + 1);

Matcher _near(LatLng expected) => isA<LatLng>()
    .having((p) => p.latitude, 'latitude', closeTo(expected.latitude, 1e-9))
    .having((p) => p.longitude, 'longitude', closeTo(expected.longitude, 1e-9));

/// Everything the platform received since [from], as one merged transition (null when no update was animated).
PlatformMarkerTransition? _transitionSince(FakeUnifiedMapsPlatform fake, int from) {
  PlatformMarkerTransition? merged;
  for (final transition in fake.markerTransitions.skip(from)) {
    if (transition == null) continue;
    merged = PlatformMarkerTransition(
      duration: transition.duration,
      appearFrom: {...?merged?.appearFrom, ...transition.appearFrom},
      disappearTo: {...?merged?.disappearTo, ...transition.disappearTo},
    );
  }
  return merged;
}

void main() {
  late FakeUnifiedMapsPlatform fake;

  setUp(() => fake = installFakePlatform());

  Widget cluster(MarkerClusterLayerOptions options, {MapController? controller}) => mapApp(
    controller: controller,
    children: [MarkerClusterLayerWidget(options: options)],
  );

  MarkerClusterLayerOptions options({
    List<Marker>? markers,
    AnimationsOptions animationsOptions = const AnimationsOptions(),
    void Function(List<Marker>)? onMarkersClustered,
    void Function(MarkerClusterNode)? onClusterTap,
    void Function(Marker)? onMarkerTap,
  }) => MarkerClusterLayerOptions(
    markers: markers ?? _trio,
    animationsOptions: animationsOptions,
    onMarkersClustered: onMarkersClustered,
    onClusterTap: onClusterTap,
    onMarkerTap: onMarkerTap,
    builder: (context, markers) => Text('${markers.length}'),
  );

  /// Moves the camera and waits until the transitions are over.
  Future<void> moveTo(WidgetTester tester, double zoom, {LatLng center = _center}) async {
    fake.moveTo(_at(zoom, center: center));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
  }

  void gestureTo(double zoom) {
    fake.emit(PlatformCameraMoveStartedEvent(fake.lastViewId, byGesture: true));
    fake.emit(PlatformCameraMoveEvent(fake.lastViewId, _at(zoom)));
  }

  /// Shows the trio at levels 6, 8 and 10 so that every icon is rasterised, and ends at level 6 with the cluster of
  /// three, whose id it returns.
  Future<String> warmUp(WidgetTester tester) async {
    await tester.pumpWidget(cluster(options()));
    fake.ready(camera: _at(6));
    await settle(tester);
    await moveTo(tester, 8);
    await moveTo(tester, 10);
    await moveTo(tester, 6);
    return fake.markers.keys.single;
  }

  testWidgets('zooming in splits clusters: new elements slide out of the cluster that held them', (tester) async {
    await tester.pumpWidget(cluster(options()));
    fake.ready(camera: _at(6));
    await settle(tester);
    expect(fake.markers.keys.map(_name), [startsWith('c')], reason: 'one cluster of three at level 6');
    final top = fake.markers.values.single;
    expect(fake.markerTransitions.whereType<PlatformMarkerTransition>(), isEmpty, reason: 'first publish is instant');

    var from = fake.markerTransitions.length;
    await moveTo(tester, 8);
    final level8 = Map.of(fake.markers);
    expect(level8.keys.map(_name), unorderedEquals([startsWith('c'), 'k:p3']));
    final pair = level8.keys.firstWhere(_isCluster);
    final split = _transitionSince(fake, from)!;
    expect(split.duration, const Duration(milliseconds: 500));
    expect(split.appearFrom, {pair: top.position, level8.keys.firstWhere((id) => !_isCluster(id)): top.position});
    expect(split.disappearTo, isEmpty, reason: 'the parent cluster fades out in place');
    final atomic = fake.markerUpdates.skip(from).where((u) => u.removedIds.contains(top.id)).single;
    expect(atomic.added.map((m) => m.id), containsAll(level8.keys), reason: 'removal and additions in one update');

    from = fake.markerTransitions.length;
    final updatesBefore = fake.markerUpdates.length;
    await moveTo(tester, 10);
    expect(fake.markers.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']));
    final p3 = fake.markers.keys.firstWhere((id) => id.endsWith('k:p3'));
    final again = _transitionSince(fake, from)!;
    expect(again.appearFrom, {for (final id in fake.markers.keys.where((id) => id != p3)) id: level8[pair]!.position});
    for (final update in fake.markerUpdates.skip(updatesBefore)) {
      expect(update.added.map((m) => m.id), isNot(contains(p3)), reason: 'p3 keeps its id');
      expect(update.removedIds, isNot(contains(p3)));
    }
  });

  testWidgets('zooming out merges: leaving elements slide into the cluster that takes them', (tester) async {
    final clustered = <List<Marker>>[];
    await tester.pumpWidget(cluster(options(onMarkersClustered: clustered.add)));
    fake.ready(camera: _at(10));
    await settle(tester);
    final singles = Map.of(fake.markers);
    expect(singles.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']));

    final from = fake.markerTransitions.length;
    await moveTo(tester, 6);
    final top = fake.markers.values.single;
    expect(_isCluster(top.id), isTrue);
    final merge = _transitionSince(fake, from)!;
    expect(merge.disappearTo, {for (final id in singles.keys) id: top.position});
    expect(merge.appearFrom, isEmpty, reason: 'the new cluster fades in in place');
    expect(clustered.expand((m) => m).map((m) => m.key), unorderedEquals(_trio.map((m) => m.key)));
  });

  testWidgets('AnimationsOptions.zoom = Duration.zero turns transitions off', (tester) async {
    await tester.pumpWidget(cluster(options(animationsOptions: const AnimationsOptions(zoom: Duration.zero))));
    fake.ready(camera: _at(6));
    await settle(tester);
    await moveTo(tester, 10);
    await moveTo(tester, 6);
    expect(fake.markerUpdates.length, greaterThanOrEqualTo(3));
    expect(fake.markerTransitions, everyElement(isNull));
  });

  testWidgets('reclusters during a gesture as soon as the zoom level changes, before idle', (tester) async {
    await tester.pumpWidget(cluster(options()));
    fake.ready(camera: _at(6));
    await settle(tester);
    final updates = fake.markerUpdates.length;
    fake.emit(PlatformCameraMoveStartedEvent(fake.lastViewId, byGesture: true));
    fake.emit(PlatformCameraMoveEvent(fake.lastViewId, _at(9.4)));
    await settle(tester);
    expect(fake.markerUpdates.length, greaterThan(updates), reason: 'no idle event was sent');
    expect(
      fake.markers.keys.map(_name),
      unorderedEquals(['k:p1', 'k:p2', 'k:p3']),
      reason: 'level 10 (zoom 9.4 rounded up)',
    );
    expect(fake.markerTransitions.last, isNotNull);
  });

  testWidgets('reclusters without animation when a gesture pans far at the same level', (tester) async {
    final far = _marker('far', const LatLng(48.0, 9.0));
    await tester.pumpWidget(cluster(options(markers: [..._trio, far])));
    fake.ready(camera: _at(10));
    await settle(tester);
    expect(fake.markers.keys.map(_name), isNot(contains('k:far')), reason: 'beyond one viewport around the view');

    final updates = fake.markerUpdates.length;
    fake.emit(PlatformCameraMoveStartedEvent(fake.lastViewId, byGesture: true));
    fake.emit(PlatformCameraMoveEvent(fake.lastViewId, _at(10, center: const LatLng(48.0, 8.5))));
    await settle(tester);
    expect(fake.markers.keys.map(_name), contains('k:far'));
    expect(fake.markerTransitions.skip(updates), everyElement(isNull), reason: 'a pan is not animated');
  });

  testWidgets('MapKit-style zoom 5.9999999 and 6.0000001 both show level 6', (tester) async {
    await tester.pumpWidget(cluster(options()));
    fake.ready(camera: _at(5.9999999));
    await settle(tester);
    final atSix = fake.markers.keys.toSet();
    await moveTo(tester, 6.0000001);
    expect(fake.markers.keys.toSet(), atSix);
  });

  testWidgets('two level changes in one frame: elements slide out of the cluster the platform shows', (tester) async {
    final topId = await warmUp(tester);
    final top = fake.markers[topId]!.position;
    final from = fake.markerTransitions.length;
    gestureTo(8);
    gestureTo(10);
    await settle(tester);
    expect(fake.markers.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']));
    final animated = fake.markerTransitions.skip(from).whereType<PlatformMarkerTransition>().toList();
    expect(animated, hasLength(1), reason: 'both generations reached the platform in one update');
    expect(animated.single.appearFrom, {for (final id in fake.markers.keys) id: top});
  });

  testWidgets('two merges in one frame: leaving elements slide into the cluster that ends on the map', (tester) async {
    await warmUp(tester);
    await moveTo(tester, 10);
    final singles = fake.markers.keys.toSet();
    final from = fake.markerTransitions.length;
    gestureTo(8);
    gestureTo(6);
    await settle(tester);
    final top = fake.markers.values.single;
    final animated = fake.markerTransitions.skip(from).whereType<PlatformMarkerTransition>().toList();
    expect(animated, hasLength(1));
    expect(animated.single.disappearTo, {for (final id in singles) id: top.position});
  });

  testWidgets('a level change while a marker update is in flight: applied in order, from where the cluster is', (
    tester,
  ) async {
    final topId = await warmUp(tester);
    final top = fake.markers[topId]!.position;
    final gate = Completer<void>();
    fake.markerUpdateGate = () => gate.future;
    final from = fake.markerUpdates.length;
    gestureTo(8);
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.markerUpdatesInFlight, 1);
    fake.emit(PlatformCameraMoveEvent(fake.lastViewId, _at(10)));
    await tester.pump(const Duration(milliseconds: 20));
    expect(fake.markerUpdatesInFlight, 1, reason: 'the next update waits for the one in flight');
    expect(fake.markerUpdates, hasLength(from));

    fake.markerUpdateGate = null;
    gate.complete();
    await settle(tester);
    expect(fake.maxMarkerUpdatesInFlight, 1);
    final applied = fake.markerUpdates.skip(from).toList();
    expect(applied, hasLength(2));
    expect(applied.first.removedIds, [topId]);
    final pair = applied.first.added.singleWhere((m) => _isCluster(m.id));
    expect(applied.last.removedIds, [pair.id]);
    expect(fake.markers.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']));

    // The level-10 generation was made 100 ms into the pair's 500 ms glide out of the cluster of three.
    final t = Curves.easeInOut.transform(100 / 500);
    final glided = LatLng(
      top.latitude + (pair.position.latitude - top.latitude) * t,
      top.longitude + (pair.position.longitude - top.longitude) * t,
    );
    final split = fake.markerTransitions.skip(from).last!;
    expect(split.appearFrom.keys.map(_name), unorderedEquals(['k:p1', 'k:p2']));
    expect(split.appearFrom.values, everyElement(_near(glided)));
  });

  testWidgets('a generation waiting for its icons leaves the map as it is; a newer one supersedes it', (tester) async {
    await tester.pumpWidget(cluster(options()));
    fake.ready(camera: _at(6));
    await settle(tester);
    final top = fake.markers.values.single;
    final from = fake.markerUpdates.length;
    gestureTo(8);
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.markerUpdates, hasLength(from), reason: 'the level-8 icons are not rasterised yet');
    expect(fake.markers.keys, [top.id]);
    fake.emit(PlatformCameraMoveEvent(fake.lastViewId, _at(10)));
    await settle(tester);
    expect(fake.markers.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']));
    final added = fake.markerUpdates.skip(from).expand((u) => u.added).map((m) => m.id);
    expect(added.where(_isCluster), isEmpty, reason: 'the level-8 generation never reached the platform');
    final split = fake.markerTransitions.skip(from).whereType<PlatformMarkerTransition>().single;
    expect(split.appearFrom, {for (final id in fake.markers.keys) id: top.position});
  });

  testWidgets('equivalent markers in a new list keep every id: nothing is sent again', (tester) async {
    await tester.pumpWidget(cluster(options()));
    fake.ready(camera: _at(8));
    await settle(tester);
    final before = Map.of(fake.markers);
    final updates = fake.markerUpdates.length;
    await tester.pumpWidget(
      cluster(
        MarkerClusterLayerOptions(
          markers: _trioMarkers(),
          computeSize: (markers) => const Size(30, 30),
          builder: (context, markers) => Text('${markers.length}'),
        ),
      ),
    );
    await settle(tester);
    expect(fake.markers, before);
    expect(fake.markerUpdates.skip(updates).where((u) => u.isNotEmpty), isEmpty);
  });

  testWidgets('the area continues across the antimeridian', (tester) async {
    final markers = [_marker('east', const LatLng(10, 179.0)), _marker('west', const LatLng(10, -179.0))];
    await tester.pumpWidget(cluster(options(markers: markers)));
    fake.ready(camera: _at(8, center: const LatLng(10, 179.8)));
    await settle(tester);
    expect(fake.markers.keys.map(_name), unorderedEquals(['k:east', 'k:west']));
    await moveTo(tester, 8, center: const LatLng(10, -179.8));
    expect(fake.markers.keys.map(_name), unorderedEquals(['k:east', 'k:west']));
  });

  testWidgets('a cluster tap fits its bounds with AnimationsOptions.fitBound', (tester) async {
    MarkerClusterNode? tapped;
    await tester.pumpWidget(
      cluster(
        options(
          onClusterTap: (node) => tapped = node,
          animationsOptions: const AnimationsOptions(fitBound: Duration(milliseconds: 321)),
        ),
      ),
    );
    fake.ready(camera: _at(6));
    await settle(tester);
    fake.tapMarker(fake.markers.keys.single);
    await tester.pump();
    expect(tapped!.mapMarkers, unorderedEquals(_trio));
    final move = fake.cameraMoves.last;
    expect(move.animation, const Duration(milliseconds: 321));
    final update = move.update as PlatformCameraUpdateNewCamera;
    expect(update.zoom, greaterThan(6));
    expect(update.center!.latitude, closeTo(48.025, 1e-3));
    expect(update.center!.longitude, closeTo(2.5, 1e-6));
    expect(fake.polygons, hasLength(1), reason: 'the convex hull is shown while the map zooms in');
  });

  testWidgets('a marker tap reaches onMarkerTap and Marker.onTap and centers it', (tester) async {
    final tapped = <String>[];
    Marker? seen;
    final markers = [_marker('solo', const LatLng(48.0, 2.5), onTap: () => tapped.add('solo'))];
    await tester.pumpWidget(cluster(options(markers: markers, onMarkerTap: (m) => seen = m)));
    fake.ready(camera: _at(10, center: const LatLng(48.1, 2.6)));
    await settle(tester);
    fake.tapMarker(fake.markers.keys.single);
    expect(seen, same(markers.single));
    expect(tapped, ['solo']);
    final move = fake.cameraMoves.last;
    expect(move.animation, const Duration(milliseconds: 500));
    expect((move.update as PlatformCameraUpdateNewCamera).center, const LatLng(48.0, 2.5));
  });

  group('spiderfy', () {
    const spot = LatLng(48.0, 2.0);
    final stack = [for (var i = 0; i < 10; i++) _marker('s$i', spot)];

    Future<String> openSpider(WidgetTester tester, {List<List<Marker>>? clustered}) async {
      await tester.pumpWidget(cluster(options(markers: stack, onMarkersClustered: clustered?.add)));
      fake.ready(camera: _at(12, center: spot));
      await settle(tester);
      final clusterId = fake.markers.keys.single;
      expect(_isCluster(clusterId), isTrue);
      fake.tapMarker(clusterId);
      await settle(tester);
      return clusterId;
    }

    testWidgets('markers at one spot glide out of their cluster to the spiral positions', (tester) async {
      final from = fake.markerTransitions.length;
      final clusterId = await openSpider(tester);
      final clusterPosition = fake.markers[clusterId]!.position;
      final leaves = fake.markers.keys.where((id) => !_isCluster(id)).toList();
      expect(leaves, hasLength(10));
      final transition = _transitionSince(fake, from)!;
      expect(transition.appearFrom, {for (final id in leaves) id: clusterPosition});

      final camera = MapCamera(
        crs: const Epsg3857(),
        rotation: 0,
        center: spot,
        zoom: 12,
        nonRotatedSize: const Size(800, 600),
      );
      final expected = Spiderfy.spiral(1, 10, const ui.Offset(400, 300));
      for (var i = 0; i < 10; i++) {
        final screen = camera.latLngToScreenOffset(
          fake.markers[leaves.firstWhere((id) => id.endsWith('k:s$i'))]!.position,
        );
        expect(screen.dx, closeTo(expected[i]!.dx, 1e-6));
        expect(screen.dy, closeTo(expected[i]!.dy, 1e-6));
      }
      expect(fake.polylines, isEmpty, reason: 'legs appear once the markers have arrived');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(fake.polylines, hasLength(10));
      for (final leg in fake.polylines.values) {
        expect(leg.points.first, clusterPosition);
        expect(fake.markers.values.map((m) => m.position), contains(leg.points.last));
      }
    });

    testWidgets('a map tap closes the spider: markers slide back into the cluster', (tester) async {
      final clustered = <List<Marker>>[];
      final clusterId = await openSpider(tester, clustered: clustered);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      final leaves = fake.markers.keys.where((id) => !_isCluster(id)).toSet();
      final from = fake.markerTransitions.length;
      fake.tap(spot, const Offset(10, 10));
      await settle(tester);
      expect(fake.markers.keys, [clusterId]);
      expect(_transitionSince(fake, from)!.disappearTo, {
        for (final id in leaves) id: fake.markers[clusterId]!.position,
      });
      expect(fake.polylines, isEmpty);
      expect(clustered.expand((m) => m), unorderedEquals(stack));
    });

    testWidgets('zooming closes the spider', (tester) async {
      await openSpider(tester);
      expect(fake.markers, hasLength(11));
      await moveTo(tester, 12.5, center: spot);
      expect(fake.markers, hasLength(1));
    });

    testWidgets('a long press keeps the spider open', (tester) async {
      await openSpider(tester);
      fake.longPress(spot, const Offset(10, 10));
      await settle(tester);
      expect(fake.markers, hasLength(11));
      fake.tap(spot, const Offset(10, 10));
      await settle(tester);
      expect(fake.markers, hasLength(1));
    });

    testWidgets('equivalent markers in a new list keep the spider open', (tester) async {
      await openSpider(tester);
      await tester.pumpWidget(cluster(options(markers: [for (var i = 0; i < 10; i++) _marker('s$i', spot)])));
      await settle(tester);
      expect(fake.markers, hasLength(11));
    });

    group('off center', () {
      const offCenter = LatLng(48.0, 2.01);

      Future<(String, LatLng, Completer<void>)> tapCluster(WidgetTester tester) async {
        await tester.pumpWidget(cluster(options(markers: stack)));
        fake.ready(camera: _at(12, center: offCenter));
        await settle(tester);
        final clusterId = fake.markers.keys.single;
        final move = Completer<void>();
        fake.moveCameraGate = () => move.future;
        fake.tapMarker(clusterId);
        await tester.pump();
        final update = fake.cameraMoves.last.update as PlatformCameraUpdateNewCamera;
        expect(update.center!.latitude, closeTo(spot.latitude, 1e-9));
        expect(update.center!.longitude, closeTo(spot.longitude, 1e-9));
        expect(update.zoom, 12, reason: 'a cluster that cannot be divided is only centered');
        return (clusterId, update.center!, move);
      }

      testWidgets('the camera centers the cluster, then the spider opens on the camera that arrived', (tester) async {
        final (clusterId, target, move) = await tapCluster(tester);
        await tester.pumpWidget(cluster(options(markers: [for (var i = 0; i < 10; i++) _marker('s$i', spot)])));
        move.complete();
        await settle(tester);
        expect(fake.markers.keys, [clusterId], reason: 'the platform has not reported the final camera yet');

        fake.moveTo(_at(12, center: target));
        await settle(tester);
        expect(fake.markers, hasLength(11));
        await tester.pump(const Duration(milliseconds: 600));
        await settle(tester);
        expect(fake.markers, hasLength(11), reason: 'still open once the camera settled');
        expect(fake.polylines, hasLength(10));
      });

      testWidgets('a move the user takes elsewhere does not open the spider', (tester) async {
        final (clusterId, _, move) = await tapCluster(tester);
        move.complete();
        await settle(tester);
        fake.moveTo(_at(12, center: const LatLng(48.0, 2.02)));
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(fake.markers.keys, [clusterId]);
      });
    });

    test('the spiral and circle match flutter_map_marker_cluster', () {
      for (final count in [2, 5, 9, 30]) {
        expect(
          Spiderfy.spiral(2, count, const ui.Offset(10, 20)),
          upstream.Spiderfy.spiral(2, count, const ui.Offset(10, 20)),
        );
        expect(
          Spiderfy.circle(40, count, const ui.Offset(10, 20)),
          upstream.Spiderfy.circle(40, count, const ui.Offset(10, 20)),
        );
      }
    });
  });
}
