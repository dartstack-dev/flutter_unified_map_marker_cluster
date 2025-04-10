import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'marker_cluster_node.dart';

/// A node of the cluster tree: a [MarkerNode] or a [MarkerClusterNode]. Same role as flutter_map_marker_cluster's.
abstract class MarkerOrClusterNode {
  MarkerClusterNode? parent;

  MarkerOrClusterNode({required this.parent});

  /// Where the node is drawn: the marker's point, or the center of the cluster's bounds.
  LatLng get position;

  /// The node's box on the map in projected pixels at the camera's zoom, as flutter_map_marker_cluster computes it.
  Rect pixelBounds(MapCamera camera);
}
