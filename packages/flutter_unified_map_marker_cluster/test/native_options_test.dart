import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart';
import 'package:flutter_unified_map_marker_cluster/src/core/cluster_index.dart';
import 'package:flutter_unified_map_marker_cluster/src/core/spiderfy.dart';
import 'package:flutter_unified_map_marker_cluster/src/native/native_cluster_engine.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;

import 'support/fake_platform.dart';
import 'support/harness.dart';

const _red = Color(0xFFFF0000);
const _center = LatLng(48.0, 2.5);

Marker _marker(String? name, LatLng point, {VoidCallback? onTap, Object iconKey = 'dot', bool? rotate}) => Marker(
  key: name == null ? null : ValueKey(name),
  point: point,
  iconKey: iconKey,
  onTap: onTap,
  rotate: rotate,
  child: const Dot(_red),
);

List<Marker> _trio({void Function(String)? onTap}) => [
  for (final (name, point) in [
    ('p1', const LatLng(48.0, 2.0)),
    ('p2', const LatLng(48.0, 2.2)),
    ('p3', const LatLng(48.05, 3.0)),
  ])
    _marker(name, point, onTap: onTap == null ? null : () => onTap(name)),
];

PlatformCamera _at(double zoom, {LatLng center = _center}) => PlatformCamera(center: center, zoom: zoom);

bool _isCluster(String id) => id.contains('/c');

String _name(String id) => id.substring(id.indexOf('/') + 1);

MarkerClusterLayerOptions _options({
  List<Marker>? markers,
  bool zoomToBoundsOnClick = true,
  bool spiderfyCluster = true,
  bool centerMarkerOnClick = true,
  bool markerChildBehavior = false,
  bool showPolygon = true,
  bool? rotate,
  int disableClusteringAtZoom = 20,
  SpiderLegOptions? spiderLegs = const SpiderLegOptions(),
  void Function(Marker)? onMarkerTap,
  void Function(MarkerClusterNode)? onClusterTap,
}) => MarkerClusterLayerOptions(
  markers: markers ?? _trio(),
  zoomToBoundsOnClick: zoomToBoundsOnClick,
  spiderfyCluster: spiderfyCluster,
  centerMarkerOnClick: centerMarkerOnClick,
  markerChildBehavior: markerChildBehavior,
  showPolygon: showPolygon,
  rotate: rotate,
  disableClusteringAtZoom: disableClusteringAtZoom,
  spiderLegs: spiderLegs,
  onMarkerTap: onMarkerTap,
  onClusterTap: onClusterTap,
  builder: (context, markers) => Text('${markers.length}'),
);

Widget _cluster(MarkerClusterLayerOptions options, {Size size = const Size(800, 600), ThemeData? theme}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(800, 600), devicePixelRatio: 2),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: UnifiedMap(children: [MarkerClusterLayerWidget(options: options)]),
      ),
    ),
  ),
);

void main() {
  late FakeUnifiedMapsPlatform fake;

  setUp(() => fake = installFakePlatform());

  Future<void> show(WidgetTester tester, MarkerClusterLayerOptions options, PlatformCamera camera) async {
    await tester.pumpWidget(_cluster(options));
    fake.ready(camera: camera);
    await settle(tester);
  }

  Future<void> moveTo(WidgetTester tester, double zoom, {LatLng center = _center}) async {
    fake.moveTo(_at(zoom, center: center));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('markers', () {
    testWidgets('a marker with a coordinate that is not finite is left out and reported', (tester) async {
      final markers = [..._trio(), _marker('nan', const LatLng(48.0, double.nan))];
      await tester.pumpWidget(_cluster(_options(markers: markers)));
      fake.ready(camera: _at(10));
      await settle(tester);
      expect(tester.takeException(), isA<ArgumentError>());
      expect(fake.markers.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']));

      await tester.pumpWidget(_cluster(_options(markers: [_marker('solo', _center)])));
      await settle(tester);
      expect(fake.markers.keys.map(_name), ['k:solo'], reason: 'the next list is clustered, not a stale tree');
    });

    test('duplicate marker keys are an error', () {
      expect(
        () => ClusterIndex.build(
          markers: [_marker('twin', _center), _marker('twin', const LatLng(48.1, 2.5))],
          config: const ClusterConfig(
            minZoom: 1,
            maxZoom: 20,
            maxClusterRadius: 80,
            disableClusteringAtZoom: 20,
            alignment: null,
            size: Size(30, 30),
          ),
          markerId: (marker, i) => 'L/${(marker.key! as ValueKey<String>).value}',
          clusterIdPrefix: 'L/c',
        ),
        throwsAssertionError,
      );
    });

    testWidgets('new markers with the same keys and points keep the tree and hand out the new markers', (tester) async {
      final tapped = <String>[];
      await show(tester, _options(markers: _trio(onTap: (name) => tapped.add('old $name'))), _at(10));
      final updates = fake.markerUpdates.length;
      await tester.pumpWidget(_cluster(_options(markers: _trio(onTap: (name) => tapped.add('new $name')))));
      await settle(tester);
      expect(fake.markerUpdates.skip(updates).where((u) => u.isNotEmpty), isEmpty);
      fake.tapMarker(fake.markers.keys.firstWhere((id) => id.endsWith('k:p1')));
      expect(tapped, ['new p1']);
    });

    testWidgets('a marker moved in a new list rebuilds the tree', (tester) async {
      await show(tester, _options(), _at(6));
      expect(fake.markers.keys.single, contains('/c'));
      await tester.pumpWidget(
        _cluster(_options(markers: [..._trio().take(2), _marker('p3', const LatLng(48.05, 7.0))])),
      );
      await settle(tester);
      expect(fake.markers.keys.map(_name), contains('k:p3'), reason: 'p3 no longer joins the cluster at level 6');
    });

    testWidgets('a tap resolves against the generation on the map, not one still waiting for its icons', (
      tester,
    ) async {
      final tapped = <String>[];
      final first = [
        _marker(null, const LatLng(48.0, 2.4), iconKey: 'a', onTap: () => tapped.add('A')),
        _marker(null, const LatLng(48.0, 2.6), iconKey: 'b', onTap: () => tapped.add('B')),
      ];
      await show(tester, _options(markers: first, centerMarkerOnClick: false), _at(12));
      final idA = fake.markers.entries.firstWhere((e) => e.value.position == first[0].point).key;

      await tester.pumpWidget(
        _cluster(
          _options(
            centerMarkerOnClick: false,
            markers: [
              _marker(null, const LatLng(48.0, 2.6), iconKey: 'b2', onTap: () => tapped.add('B2')),
              _marker(null, const LatLng(48.0, 2.4), iconKey: 'a2', onTap: () => tapped.add('A2')),
            ],
          ),
        ),
      );
      fake.tapMarker(idA);
      expect(tapped, ['A'], reason: 'the map still shows A under that id');
      await settle(tester);
      fake.tapMarker(idA);
      expect(tapped, ['A', 'B2'], reason: 'the new generation reached the map');
    });
  });

  group('appearance', () {
    testWidgets('clusters are rasterised again when the theme changes', (tester) async {
      Widget app(Brightness brightness) => _cluster(
        MarkerClusterLayerOptions(
          markers: _trio(),
          builder: (context, markers) => ColoredBox(color: Theme.of(context).colorScheme.primary),
        ),
        theme: ThemeData(brightness: brightness),
      );
      await tester.pumpWidget(app(Brightness.light));
      fake.ready(camera: _at(6));
      await settle(tester);
      final light = fake.markers.values.single;
      await tester.pumpWidget(app(Brightness.dark));
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      final dark = fake.markers.values.single;
      expect(dark.id, light.id);
      expect(dark.icon.key, isNot(light.icon.key));
    });
  });

  group('area', () {
    testWidgets('a map without a size publishes nothing until it has one', (tester) async {
      await tester.pumpWidget(_cluster(_options(), size: const Size(800, 0)));
      fake.ready(camera: _at(10));
      await settle(tester);
      expect(fake.markers, isEmpty);
      await tester.pumpWidget(_cluster(_options()));
      await settle(tester);
      expect(fake.markers.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']));
    });

    testWidgets('beyond ${NativeClusterEngine.maxPublished} elements, every marker on screen is published first', (
      tester,
    ) async {
      const columns = 70;
      final markers = [
        for (var i = 0; i < columns; i++)
          for (var j = 0; j < columns; j++)
            _marker('g$i.$j', LatLng(47.4 + 1.2 * j / (columns - 1), 1.6 + 1.8 * i / (columns - 1))),
      ];
      await show(tester, _options(markers: markers, disableClusteringAtZoom: 1), _at(10));
      expect(fake.markers, hasLength(NativeClusterEngine.maxPublished));
      final camera = MapCamera(
        crs: const Epsg3857(),
        rotation: 0,
        center: _center,
        zoom: 10,
        nonRotatedSize: const Size(800, 600),
      );
      final onScreen = [
        for (final marker in markers)
          if ((Offset.zero & const Size(800, 600)).contains(camera.latLngToScreenOffset(marker.point)))
            (marker.key! as ValueKey<String>).value,
      ];
      expect(onScreen.length, inInclusiveRange(1000, NativeClusterEngine.maxPublished - 1));
      final published = fake.markers.keys.map(_name).toSet();
      expect(published, containsAll([for (final name in onScreen) 'k:$name']));
    });

    testWidgets('disableClusteringAtZoom: every marker alone above it', (tester) async {
      await show(tester, _options(disableClusteringAtZoom: 5), _at(6));
      expect(fake.markers.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']));
      await moveTo(tester, 5);
      expect(fake.markers.keys.single, contains('/c'));
    });
  });

  group('levels', () {
    void gestureTo(double zoom) {
      fake.emit(PlatformCameraMoveStartedEvent(fake.lastViewId, byGesture: true));
      fake.emit(PlatformCameraMoveEvent(fake.lastViewId, _at(zoom)));
    }

    testWidgets('a pinch hovering on an integer zoom keeps its level; a settled camera shows the exact one', (
      tester,
    ) async {
      await show(tester, _options(), _at(9));
      final level9 = fake.markers.keys.toSet();
      expect(level9.where(_isCluster), hasLength(1));
      final updates = fake.markerUpdates.length;
      for (final zoom in [9.02, 8.99, 9.04, 8.96]) {
        gestureTo(zoom);
        await settle(tester);
      }
      expect(fake.markerUpdates.skip(updates).where((u) => u.isNotEmpty), isEmpty);
      fake.emit(PlatformCameraIdleEvent(fake.lastViewId, _at(9.02)));
      await settle(tester);
      expect(fake.markers.keys.map(_name), unorderedEquals(['k:p1', 'k:p2', 'k:p3']), reason: 'level 10');

      gestureTo(8.97);
      await settle(tester);
      expect(fake.markers.keys.where(_isCluster), isEmpty, reason: 'still level 10 during the gesture');
      gestureTo(8.94);
      await settle(tester);
      expect(fake.markers.keys.toSet(), level9);
    });
  });

  group('rotate', () {
    testWidgets('a marker stays upright when the options or the marker ask for it', (tester) async {
      final markers = [
        _marker('own', const LatLng(48.0, 2.4), rotate: true),
        _marker('off', const LatLng(48.0, 2.6), rotate: false),
      ];
      await show(tester, _options(markers: markers, rotate: true), _at(12));
      expect(fake.markers.values.map((m) => m.flat), everyElement(isFalse));

      await tester.pumpWidget(_cluster(_options(markers: markers)));
      await settle(tester);
      final flat = {for (final m in fake.markers.values) _name(m.id): m.flat};
      expect(flat, {'k:own': false, 'k:off': true});
    });
  });

  group('taps', () {
    testWidgets('centerMarkerOnClick false: the camera stays', (tester) async {
      Marker? seen;
      await show(tester, _options(centerMarkerOnClick: false, onMarkerTap: (m) => seen = m), _at(10));
      fake.tapMarker(fake.markers.keys.first);
      expect(seen, isNotNull);
      expect(fake.cameraMoves, isEmpty);
    });

    testWidgets('markerChildBehavior: only Marker.onTap is called and the camera stays', (tester) async {
      final tapped = <String>[];
      Marker? seen;
      await show(
        tester,
        _options(
          markers: _trio(onTap: tapped.add),
          markerChildBehavior: true,
          onMarkerTap: (m) => seen = m,
        ),
        _at(10),
      );
      fake.tapMarker(fake.markers.keys.firstWhere((id) => id.endsWith('k:p2')));
      expect(tapped, ['p2']);
      expect(seen, isNull);
      expect(fake.cameraMoves, isEmpty);
    });

    testWidgets('showPolygon: the hull is removed AnimationsOptions.zoom after the fit', (tester) async {
      await show(tester, _options(), _at(6));
      fake.tapMarker(fake.markers.keys.single);
      await tester.pump();
      expect(fake.polygons, hasLength(1));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(fake.polygons, isEmpty);
    });

    testWidgets('showPolygon false: no hull', (tester) async {
      await show(tester, _options(showPolygon: false), _at(6));
      fake.tapMarker(fake.markers.keys.single);
      await tester.pump();
      expect(fake.polygons, isEmpty);
      expect(fake.cameraMoves, isNotEmpty);
    });

    testWidgets('disposed while the fit animation runs: nothing happens when it ends', (tester) async {
      final move = Completer<void>();
      fake.moveCameraGate = () => move.future;
      await show(tester, _options(), _at(6));
      fake.tapMarker(fake.markers.keys.single);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      move.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('spiderfy', () {
    const spot = LatLng(48.0, 2.0);
    List<Marker> stack(int count) => [for (var i = 0; i < count; i++) _marker('s$i', spot)];

    Future<String> showStack(WidgetTester tester, MarkerClusterLayerOptions options) async {
      await show(tester, options, _at(12, center: spot));
      final clusterId = fake.markers.keys.single;
      expect(_isCluster(clusterId), isTrue);
      return clusterId;
    }

    testWidgets('fewer than circleSpiralSwitchover markers spread on a circle', (tester) async {
      final clusterId = await showStack(tester, _options(markers: stack(5)));
      fake.tapMarker(clusterId);
      await settle(tester);
      final leaves = fake.markers.keys.where((id) => !_isCluster(id)).toList();
      expect(leaves, hasLength(5));
      final camera = MapCamera(
        crs: const Epsg3857(),
        rotation: 0,
        center: spot,
        zoom: 12,
        nonRotatedSize: const Size(800, 600),
      );
      final expected = Spiderfy.circle(40, 5, const ui.Offset(400, 300));
      for (var i = 0; i < 5; i++) {
        final screen = camera.latLngToScreenOffset(
          fake.markers[leaves.firstWhere((id) => id.endsWith('k:s$i'))]!.position,
        );
        expect(screen.dx, closeTo(expected[i]!.dx, 1e-6));
        expect(screen.dy, closeTo(expected[i]!.dy, 1e-6));
      }
    });

    testWidgets('zoomToBoundsOnClick false: a tap spiderfies without moving the camera, a second tap closes', (
      tester,
    ) async {
      final clusterId = await showStack(tester, _options(markers: stack(5), zoomToBoundsOnClick: false));
      fake.tapMarker(clusterId);
      await settle(tester);
      expect(fake.markers, hasLength(6));
      expect(fake.cameraMoves, isEmpty);
      fake.tapMarker(clusterId);
      await settle(tester);
      expect(fake.markers.keys, [clusterId]);
    });

    testWidgets('spiderfyCluster false: a tap only calls onClusterTap', (tester) async {
      final tapped = <MarkerClusterNode>[];
      final clusterId = await showStack(
        tester,
        _options(markers: stack(5), zoomToBoundsOnClick: false, spiderfyCluster: false, onClusterTap: tapped.add),
      );
      fake.tapMarker(clusterId);
      await settle(tester);
      expect(tapped, hasLength(1));
      expect(fake.markers.keys, [clusterId]);
      expect(fake.cameraMoves, isEmpty);
    });

    testWidgets('spiderLegs null draws no legs; reclusters without a spider leave the polylines alone', (tester) async {
      final clusterId = await showStack(tester, _options(markers: stack(5), spiderLegs: null));
      await moveTo(tester, 13, center: spot);
      await moveTo(tester, 12, center: spot);
      expect(fake.polylineUpdates, isEmpty, reason: 'no spider, no polylines sent');
      fake.tapMarker(clusterId);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(fake.markers, hasLength(6));
      expect(fake.polylines, isEmpty);
    });
  });
}
