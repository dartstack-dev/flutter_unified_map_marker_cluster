import 'dart:ui';

import 'package:flutter_unified_map/flutter_unified_map.dart';

import '../core/cluster_index.dart';
import '../core/spiderfy.dart';
import '../marker_cluster_layer_options.dart';
import '../node/marker_cluster_node.dart';

/// A spiderfied cluster: where each of its markers is drawn, by object id.
class Spider {
  final MarkerClusterNode cluster;
  final String clusterId;
  final int level;
  final double zoom;
  final LatLng center;
  final Map<String, LatLng> positions;

  /// Whether the legs are drawn: once the markers arrived.
  bool legs;

  Spider({
    required this.cluster,
    required this.clusterId,
    required this.level,
    required this.zoom,
    required this.center,
    required this.positions,
    this.legs = false,
  });

  /// Spreads [cluster]'s markers around it as flutter_map_marker_cluster does, in unrotated screen pixels of
  /// [camera]: on [MarkerClusterLayerOptions.spiderfyShapePositions], or on a circle below
  /// [MarkerClusterLayerOptions.circleSpiralSwitchover] markers and a spiral from it on.
  factory Spider.open({
    required ClusterIndex index,
    required MarkerClusterNode cluster,
    required int level,
    required MapCamera camera,
    required MarkerClusterLayerOptions options,
  }) {
    final zoom = camera.zoom;
    final origin = camera.projectAtZoom(camera.center, zoom) - camera.nonRotatedSize.center(Offset.zero);
    final center = camera.projectAtZoom(cluster.bounds.center, zoom) - origin;
    final markers = cluster.markers;
    final count = markers.length;
    final shape = options.spiderfyShapePositions;
    final List<Offset?> points = shape != null
        ? shape(count, center)
        : count >= options.circleSpiralSwitchover
        ? Spiderfy.spiral(options.spiderfySpiralDistanceMultiplier, count, center)
        : Spiderfy.circle(options.spiderfyCircleRadius, count, center);
    return Spider(
      cluster: cluster,
      clusterId: index.idOf(cluster),
      level: level,
      zoom: zoom,
      center: cluster.position,
      positions: {
        for (var i = 0; i < count; i++)
          index.idOf(markers[i]): camera.unprojectAtZoom((points[i] ?? center) + origin, zoom),
      },
    );
  }

  /// This spider on [index], a rebuilt cluster tree, when its cluster still holds the same markers there.
  Spider? within(ClusterIndex? index) {
    final node = index?.nodes[clusterId];
    if (node is! MarkerClusterNode) return null;
    final markers = node.markers;
    if (markers.length != positions.length || !markers.every((m) => positions.containsKey(index!.idOf(m)))) {
      return null;
    }
    return Spider(
      cluster: node,
      clusterId: clusterId,
      level: level,
      zoom: zoom,
      center: center,
      positions: positions,
      legs: legs,
    );
  }

  List<Polyline> legsWith(SpiderLegOptions style) => [
    for (final position in positions.values)
      Polyline(points: [center, position], color: style.color, strokeWidth: style.strokeWidth),
  ];
}

/// A cluster to spiderfy once the camera reached [center] at [zoom].
class SpiderTarget {
  /// How close the camera must end to the target, in screen pixels and zoom, for the spider to open: a move the
  /// user interrupted ends elsewhere.
  static const _arrivalPixels = 8.0;
  static const _arrivalZoom = 1e-2;

  final String clusterId;
  final LatLng center;
  final double zoom;

  const SpiderTarget(this.clusterId, this.center, this.zoom);

  bool reachedBy(MapCamera camera) =>
      (camera.zoom - zoom).abs() <= _arrivalZoom &&
      (camera.projectAtZoom(camera.center) - camera.projectAtZoom(center)).distance <= _arrivalPixels;
}
