import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'marker_node.dart';
import 'marker_or_cluster_node.dart';

/// A cluster of the tree built by `MarkerClusterLayerWidget`, as handed to `onClusterTap`. Same API as
/// flutter_map_marker_cluster's `MarkerClusterNode`.
///
/// [zoom] is the zoom level the cluster is shown at; [children] are the clusters of the next level and the markers
/// that are no longer clustered there; [markers] lists every marker below it, direct children first.
class MarkerClusterNode extends MarkerOrClusterNode {
  final int zoom;

  /// Alignment of the cluster widget on [position] (flutter_map `Marker.alignment` semantics).
  final Alignment? alignment;

  /// Size of the cluster widget when [computeSize] is null.
  final Size predefinedSize;

  /// Size of the cluster widget from [mapMarkers].
  final Size Function(List<Marker>)? computeSize;
  final children = <MarkerOrClusterNode>[];

  _Derived? _derived;

  MarkerClusterNode({required this.zoom, required this.alignment, required this.predefinedSize, this.computeSize})
    : super(parent: null);

  _Derived get _data => _derived ??= _Derived(children, computeSize);

  /// Every marker node below this cluster, direct children first.
  List<MarkerNode> get markers => _data.markerNodes;

  /// The [Marker]s of [markers].
  List<Marker> get mapMarkers => _data.markers;

  /// Bounds of every marker below this cluster.
  LatLngBounds get bounds => _data.bounds ?? LatLngBounds(const LatLng(0, 0), const LatLng(0, 0));

  Size size() => _data.size ?? predefinedSize;

  @override
  LatLng get position => bounds.center;

  /// Adds [child] below this cluster. [childPoint] is accepted for flutter_map_marker_cluster's signature.
  void addChild(MarkerOrClusterNode child, LatLng childPoint) {
    children.add(child);
    child.parent = this;
    _invalidate();
  }

  /// Removes [child] from below this cluster.
  void removeChild(MarkerOrClusterNode child) {
    children.remove(child);
    _invalidate();
  }

  /// Drops the cached markers, bounds and size; they are computed again on next use.
  void recalculate({required bool recursively}) {
    if (recursively) {
      for (final child in children) {
        if (child is MarkerClusterNode) child.recalculate(recursively: true);
      }
    }
    _invalidate();
  }

  void _invalidate() {
    for (MarkerClusterNode? node = this; node != null; node = node.parent) {
      node._derived = null;
    }
  }

  /// Calls [fn] for every node shown at [zoomLevel] whose bounds overlap [recursionBounds], like
  /// flutter_map_marker_cluster: the clusters of that level (when it is at most [disableClusteringAtZoom]) and the
  /// markers that are not clustered there.
  void recursively(
    int zoomLevel,
    int disableClusteringAtZoom,
    LatLngBounds recursionBounds,
    void Function(MarkerOrClusterNode node) fn,
  ) {
    if (zoom == zoomLevel && zoomLevel <= disableClusteringAtZoom) {
      fn(this);
      return;
    }
    for (final child in children) {
      if (child is MarkerNode) {
        fn(child);
      } else if (child is MarkerClusterNode && recursionBounds.isOverlapping(child.bounds)) {
        child.recursively(zoomLevel, disableClusteringAtZoom, recursionBounds, fn);
      }
    }
  }

  @override
  Rect pixelBounds(MapCamera camera) {
    final center = camera.projectAtZoom(bounds.center);
    final alignment = this.alignment ?? Alignment.center;
    final size = this.size();
    final topLeft = Offset(center.dx + size.width * alignment.x * 0.5, center.dy + size.height * alignment.y * 0.5);
    return Rect.fromPoints(topLeft, topLeft + Offset(size.width, size.height));
  }
}

class _Derived {
  final markerNodes = <MarkerNode>[];
  late final LatLngBounds? bounds;
  late final List<Marker> markers;
  late final Size? size;

  _Derived(List<MarkerOrClusterNode> children, Size Function(List<Marker>)? computeSize) {
    markerNodes.addAll(children.whereType<MarkerNode>());
    for (final child in children.whereType<MarkerClusterNode>()) {
      markerNodes.addAll(child.markers);
    }
    bounds = markerNodes.isEmpty ? null : LatLngBounds.fromPoints([for (final node in markerNodes) node.point]);
    markers = [for (final node in markerNodes) node.marker];
    size = computeSize?.call(markers);
  }
}
