import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart';

void main() => runApp(const MaterialApp(home: Scaffold(body: ClusterMap())));

/// A hundred markers around Paris, clustered with flutter_map_marker_cluster's options.
class ClusterMap extends StatelessWidget {
  const ClusterMap({super.key});

  static final markers = [
    for (var i = 0; i < 100; i++)
      Marker(
        key: ValueKey('m$i'),
        point: LatLng(48.7 + (i % 10) * 0.03, 2.2 + (i ~/ 10) * 0.03),
        iconKey: 'pin',
        child: const Icon(Icons.place, color: Color(0xFF52616F)),
      ),
  ];

  @override
  Widget build(BuildContext context) => UnifiedMap(
    options: const MapOptions(initialCenter: LatLng(48.85, 2.35), initialZoom: 10),
    children: [
      MarkerClusterLayerWidget(
        options: MarkerClusterLayerOptions(
          markers: markers,
          size: const Size(40, 40),
          builder: (context, markers) => CircleAvatar(child: Text('${markers.length}')),
          onMarkerTap: (marker) => debugPrint('tapped ${marker.key}'),
        ),
      ),
    ],
  );
}
