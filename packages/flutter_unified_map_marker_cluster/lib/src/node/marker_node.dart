import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'marker_or_cluster_node.dart';

/// A single [Marker] in the cluster tree. It is a [Marker] itself, like flutter_map_marker_cluster's `MarkerNode`.
// The node is linked into the tree through its mutable parent, as in flutter_map_marker_cluster.
// ignore: must_be_immutable
class MarkerNode extends MarkerOrClusterNode implements Marker {
  Marker _marker;

  MarkerNode(Marker marker) : _marker = marker, super(parent: null);

  /// The marker of `MarkerClusterLayerOptions.markers` this node stands for.
  Marker get marker => _marker;

  @override
  Key? get key => marker.key;

  @override
  Widget get child => marker.child;

  @override
  double get height => marker.height;

  @override
  double get width => marker.width;

  @override
  LatLng get point => marker.point;

  @override
  bool? get rotate => marker.rotate;

  @override
  Alignment? get alignment => marker.alignment;

  @override
  Object? get iconKey => marker.iconKey;

  @override
  Object get effectiveIconKey => marker.effectiveIconKey;

  @override
  NativeMarkerParams? get nativeParams => marker.nativeParams;

  @override
  VoidCallback? get onTap => marker.onTap;

  @override
  LatLng get position => marker.point;

  @override
  Rect pixelBounds(MapCamera camera) {
    final center = camera.projectAtZoom(point);
    final alignment = this.alignment ?? Alignment.center;
    final topLeft = Offset(center.dx + width * alignment.x * 0.5, center.dy + height * alignment.y * 0.5);
    return Rect.fromPoints(topLeft, topLeft + Offset(width, height));
  }
}

/// Points [node] to [marker], an equivalent marker of a new list, without rebuilding the tree.
void replaceMarkerOf(MarkerNode node, Marker marker) => node._marker = marker;
