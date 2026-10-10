import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart';

import 'demo_data.dart';
import 'map_widgets.dart';

/// The Brussels city network under a single cluster: zoom in and its pins dispatch over the area, zoom
/// out and they pack back into one cluster.
class PinsMap extends StatefulWidget {
  const PinsMap({
    super.key,
    this.controller,
    this.animations = const AnimationsOptions(),
    this.pins,
    this.onMapReady,
    this.initialCenter = brussels,
    this.initialZoom = 8.0,
    this.overlays = const [],
    this.mapStyle = MapStyle.standard,
  });

  final MapController? controller;
  final AnimationsOptions animations;
  final List<Pin>? pins;
  final VoidCallback? onMapReady;
  final LatLng initialCenter;
  final double initialZoom;
  final List<Widget> overlays;
  final MapStyle mapStyle;

  @override
  State<PinsMap> createState() => _PinsMapState();
}

class _PinsMapState extends State<PinsMap> {
  late final _pins = widget.pins ?? generatePins(count: brusselsNetwork);
  late final _byId = {for (final pin in _pins) pin.id: pin};
  late final _markers = [
    for (final pin in _pins) Marker(key: ValueKey(pin.id), point: pin.point, iconKey: 'pin', child: const DemoPin()),
  ];
  Pin? _selected;

  void _onMarkerTap(Marker marker) {
    final pin = _byId[(marker.key! as ValueKey<String>).value];
    if (pin == null) return;
    setState(() => _selected = pin);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(pin.id)));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return UnifiedMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        onMapReady: widget.onMapReady,
        mapStyle: widget.mapStyle,
        onTap: (_, _) => setState(() => _selected = null),
      ),
      children: [
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            markers: _markers,
            size: const Size(44, 44),
            disableClusteringAtZoom: 10,
            animationsOptions: widget.animations,
            showPolygon: false,
            clusterIconKey: (markers) => markers.length,
            builder: (context, markers) => ClusterBadge(count: markers.length),
            onMarkerTap: _onMarkerTap,
          ),
        ),
        if (selected != null)
          MarkerLayer(
            markers: [
              Marker(
                point: selected.point,
                width: 30,
                height: 40,
                alignment: Alignment.topCenter,
                iconKey: 'selected',
                child: const SelectedPin(),
              ),
            ],
          ),
        ...widget.overlays,
        const OsmAttribution(),
      ],
    );
  }
}

class PinsHeader extends StatelessWidget {
  const PinsHeader({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MapCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count pins', style: text.titleSmall),
          const SizedBox(height: 6),
          Text('Tap the Brussels cluster to zoom into its pins', style: text.labelSmall),
        ],
      ),
    );
  }
}
