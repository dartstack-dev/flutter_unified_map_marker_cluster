import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart';

import 'demo_data.dart';
import 'map_widgets.dart';

/// One stack of pins on the exact same point of Brussels: the page shows a single cluster, and a tap spreads its
/// pins on a spiral.
class SpiderfyMap extends StatelessWidget {
  const SpiderfyMap({
    super.key,
    this.controller,
    this.animations = const AnimationsOptions(),
    this.onMapReady,
    this.onMarkerTap,
    this.onClusterTap,
    this.overlays = const [],
    this.mapStyle = MapStyle.standard,
  });

  final MapController? controller;
  final AnimationsOptions animations;
  final VoidCallback? onMapReady;
  final void Function(Marker)? onMarkerTap;
  final void Function(MarkerClusterNode)? onClusterTap;
  final List<Widget> overlays;
  final MapStyle mapStyle;

  static final pins = generateSpiderfyPins();
  static final markers = [
    for (final pin in pins) Marker(key: ValueKey(pin.id), point: pin.point, iconKey: 'pin', child: const DemoPin()),
  ];

  @override
  Widget build(BuildContext context) => UnifiedMap(
    mapController: controller,
    options: MapOptions(initialCenter: brussels, initialZoom: 12, onMapReady: onMapReady, mapStyle: mapStyle),
    children: [
      MarkerClusterLayerWidget(
        options: MarkerClusterLayerOptions(
          markers: markers,
          size: const Size(40, 40),
          maxClusterRadius: 60,
          animationsOptions: animations,
          showPolygon: false,
          clusterIconKey: (markers) => markers.length,
          builder: (context, markers) => ClusterBadge(count: markers.length),
          onMarkerTap: onMarkerTap,
          onClusterTap: onClusterTap,
        ),
      ),
      ...overlays,
      const OsmAttribution(),
    ],
  );
}
