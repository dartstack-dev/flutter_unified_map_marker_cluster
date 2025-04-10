import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart' as fmmc;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart';
import 'package:flutter_unified_map_marker_cluster/src/core/cluster_index.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show UnifiedMapsPlatform;

import 'support/harness.dart';

/// A marker child that says which marker it belongs to.
class _Pin extends StatelessWidget {
  const _Pin(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFFDC2626));
}

Marker _marker(String name, LatLng point, {VoidCallback? onTap}) =>
    Marker(key: ValueKey(name), point: point, onTap: onTap, child: _Pin(name));

Widget _app(MarkerClusterLayerOptions options, {double zoom = 6, LatLng center = const LatLng(48.0, 2.5)}) => mapApp(
  options: MapOptions(initialCenter: center, initialZoom: zoom, mapStyle: MapStyle.none),
  children: [MarkerClusterLayerWidget(options: options)],
);

void main() {
  setUp(() => UnifiedMapsPlatform.instance = UnifiedMapsFlutterMap());

  final trio = [
    _marker('p1', const LatLng(48.0, 2.0)),
    _marker('p2', const LatLng(48.0, 2.2)),
    _marker('p3', const LatLng(48.05, 3.0)),
  ];

  testWidgets('draws the real flutter_map_marker_cluster layer and maps callbacks back', (tester) async {
    MarkerClusterNode? tappedCluster;
    await tester.pumpWidget(
      _app(
        MarkerClusterLayerOptions(
          markers: trio,
          onClusterTap: (node) => tappedCluster = node,
          builder: (context, markers) => Text('${markers.length}', textDirection: TextDirection.ltr),
        ),
      ),
    );
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(fmmc.MarkerClusterLayerWidget), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byType(_Pin), findsNothing);

    await tester.tap(find.text('3'));
    await tester.pump();
    expect(tappedCluster!.mapMarkers, unorderedEquals(trio));
    expect(tappedCluster!.bounds, LatLngBounds.fromPoints([for (final m in trio) m.point]));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('marker taps reach onMarkerTap and Marker.onTap with the original markers', (tester) async {
    final tapped = <String>[];
    Marker? seen;
    final markers = [_marker('solo', const LatLng(48.0, 2.5), onTap: () => tapped.add('solo'))];
    await tester.pumpWidget(
      _app(
        MarkerClusterLayerOptions(
          markers: markers,
          onMarkerTap: (marker) => seen = marker,
          builder: (context, markers) => Text('${markers.length}', textDirection: TextDirection.ltr),
        ),
        zoom: 10,
      ),
    );
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(_Pin));
    await tester.pump();
    expect(seen, same(markers.single));
    expect(tapped, ['solo']);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new animation durations give flutter_map_marker_cluster a new state', (tester) async {
    Widget app(Duration zoom) => _app(
      MarkerClusterLayerOptions(
        markers: trio,
        animationsOptions: AnimationsOptions(zoom: zoom),
        builder: (context, markers) => Text('${markers.length}', textDirection: TextDirection.ltr),
      ),
    );
    await tester.pumpWidget(app(const Duration(milliseconds: 500)));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    final first = tester.element(find.byType(fmmc.MarkerClusterLayerWidget));

    await tester.pumpWidget(app(const Duration(milliseconds: 500)));
    await settle(tester);
    expect(tester.element(find.byType(fmmc.MarkerClusterLayerWidget)), same(first));

    await tester.pumpWidget(app(const Duration(milliseconds: 120)));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    final second = tester.element(find.byType(fmmc.MarkerClusterLayerWidget));
    expect(second, isNot(same(first)));
    expect(
      (second.widget as fmmc.MarkerClusterLayerWidget).options.animationsOptions.zoom,
      const Duration(milliseconds: 120),
    );
    expect(find.text('3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new maxClusterRadius reclusters, as natively', (tester) async {
    Widget app(int radius) => _app(
      MarkerClusterLayerOptions(
        markers: trio,
        maxClusterRadius: radius,
        builder: (context, markers) => Text('${markers.length}', textDirection: TextDirection.ltr),
      ),
    );
    await tester.pumpWidget(app(80));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(app(1));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3'), findsNothing);
    expect(find.byType(_Pin), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('markerChildBehavior: Marker.onTap fires from the child, onMarkerTap is skipped', (tester) async {
    final tapped = <String>[];
    Marker? seen;
    await tester.pumpWidget(
      _app(
        MarkerClusterLayerOptions(
          markers: [_marker('solo', const LatLng(48.0, 2.5), onTap: () => tapped.add('solo'))],
          markerChildBehavior: true,
          onMarkerTap: (marker) => seen = marker,
          builder: (context, markers) => Text('${markers.length}', textDirection: TextDirection.ltr),
        ),
        zoom: 10,
      ),
    );
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(_Pin));
    await tester.pump();
    expect(tapped, ['solo']);
    expect(seen, isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a marker with a coordinate that is not finite is left out and reported, as natively', (tester) async {
    await tester.pumpWidget(
      _app(
        MarkerClusterLayerOptions(
          markers: [_marker('solo', const LatLng(48.0, 2.5)), _marker('nan', const LatLng(double.nan, 2.5))],
          builder: (context, markers) => Text('${markers.length}', textDirection: TextDirection.ltr),
        ),
        zoom: 10,
      ),
    );
    expect(tester.takeException(), isA<ArgumentError>());
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widgetList<_Pin>(find.byType(_Pin)).map((pin) => pin.name), ['solo']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native clustering finds the same clusters as flutter_map_marker_cluster', (tester) async {
    final random = math.Random(3);
    final markers = [
      for (var i = 0; i < 400; i++)
        _marker('m$i', LatLng(46 + random.nextDouble() * 4 + (i.isEven ? 0 : 0.0001), 1 + random.nextDouble() * 6)),
    ];
    final index = ClusterIndex.build(
      markers: markers,
      config: const ClusterConfig(
        minZoom: 1,
        maxZoom: 20,
        maxClusterRadius: 80,
        disableClusteringAtZoom: 20,
        alignment: null,
        size: Size(30, 30),
      ),
      markerId: (marker, i) => '$i',
      clusterIdPrefix: 'c',
    );

    for (final zoom in [5.0, 6.4, 7.0, 8.7, 10.2]) {
      final drawn = <(int, LatLng)>[];
      await tester.pumpWidget(
        _app(
          MarkerClusterLayerOptions(
            markers: markers,
            builder: (context, markers) {
              drawn.add((markers.length, LatLngBounds.fromPoints([for (final m in markers) m.point]).center));
              return const SizedBox();
            },
          ),
          zoom: zoom,
          center: const LatLng(48, 4),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      drawn.clear();
      tester.element(find.byType(fmmc.MarkerClusterLayerWidget)).markNeedsBuild();
      await tester.pump();
      final singles = {for (final pin in tester.widgetList<_Pin>(find.byType(_Pin))) pin.name};

      final camera = MapCamera(
        crs: const Epsg3857(),
        rotation: 0,
        center: const LatLng(48, 4),
        zoom: zoom,
        nonRotatedSize: const Size(800, 600),
      );
      final screen = Rect.fromCenter(center: camera.projectAtZoom(camera.center), width: 800, height: 600);
      final ours = index
          .visible(zoom.ceil(), LatLngBounds.unsafe(north: 90, south: -90, east: 180, west: -180))
          .where((node) => node.pixelBounds(camera).overlaps(screen))
          .toList();
      final ourClusters = [
        for (final node in ours.whereType<MarkerClusterNode>()) (node.markers.length, node.position),
      ];
      final ourSingles = {for (final node in ours.whereType<MarkerNode>()) (node.marker.child as _Pin).name};

      String describe(Iterable<(int, LatLng)> clusters) => ([
        for (final (count, p) in clusters) '$count@${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}',
      ]..sort()).join(' ');
      expect(describe(ourClusters), describe(drawn), reason: 'clusters at zoom $zoom');
      expect(ourSingles, singles, reason: 'single markers at zoom $zoom');
      expect(ourClusters.length + ourSingles.length, greaterThanOrEqualTo(3));
      await tester.pumpWidget(const SizedBox());
    }
  });
}
