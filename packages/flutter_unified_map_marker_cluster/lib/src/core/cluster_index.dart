// The tree construction is a port of flutter_map_marker_cluster 8.2.2's ClusterManager (BSD-3-Clause, Copyright (c)
// 2018 Lorenzo Pongetti; see LICENSE), kept identical so that native clusters match flutter_map_marker_cluster's.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import '../markers.dart';
import '../node/marker_cluster_node.dart';
import '../node/marker_node.dart';
import '../node/marker_or_cluster_node.dart';
import 'distance_grid.dart';

/// Web Mercator pixel of [point] at [zoom] (256 px tiles), as flutter_map's EPSG:3857 projects it.
Offset _project(LatLng point, double zoom) {
  final worldWidth = 256 * math.pow(2, zoom).toDouble();
  final lat = point.latitude.clamp(-85.05112878, 85.05112878);
  final sinLat = math.sin(lat * math.pi / 180);
  return Offset(
    (point.longitude + 180) / 360 * worldWidth,
    (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * worldWidth,
  );
}

/// The clustering configuration an index was built with; a different one needs a new index. Like
/// flutter_map_marker_cluster, a new `computeSize` alone does not rebuild the clusters.
@immutable
class ClusterConfig {
  final int minZoom;
  final int maxZoom;
  final int maxClusterRadius;
  final int disableClusteringAtZoom;
  final Alignment? alignment;
  final Size size;

  const ClusterConfig({
    required this.minZoom,
    required this.maxZoom,
    required this.maxClusterRadius,
    required this.disableClusteringAtZoom,
    required this.alignment,
    required this.size,
  });

  @override
  bool operator ==(Object other) =>
      other is ClusterConfig &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.maxClusterRadius == maxClusterRadius &&
      other.disableClusteringAtZoom == disableClusteringAtZoom &&
      other.alignment == alignment &&
      other.size == size;

  @override
  int get hashCode => Object.hash(minZoom, maxZoom, maxClusterRadius, disableClusteringAtZoom, alignment, size);
}

/// The cluster tree of a list of markers over every zoom level, with an object id per node that only depends on the
/// markers' keys (their index for markers without a key): an index built again from equivalent markers gives the
/// same ids.
class ClusterIndex {
  final ClusterConfig config;
  final MarkerClusterNode top;
  final Map<String, MarkerOrClusterNode> nodes;
  final Expando<String> _ids;

  /// The markers the tree stands for, and the node of each (null for a marker left out).
  final List<Marker> _source;
  final List<MarkerNode?> _leaves;

  ClusterIndex._(this.config, this.top, this.nodes, this._ids, this._source, this._leaves);

  /// Builds the tree of [markers]. [markerId] gives the object id of the marker at an index. A cluster is
  /// `'<clusterIdPrefix><zoom>:<id of its first marker>'`, without the first marker id's part up to its first `/`
  /// (the layer id): a marker belongs to one cluster per zoom level. Markers whose coordinates are not finite are
  /// left out (and reported), the others keep the id of their index.
  factory ClusterIndex.build({
    required List<Marker> markers,
    required ClusterConfig config,
    required String Function(Marker marker, int index) markerId,
    required String clusterIdPrefix,
    Size Function(List<Marker>)? computeSize,
  }) {
    final minZoom = config.minZoom;
    final maxZoom = math.max(config.maxZoom, minZoom);
    final levels = maxZoom - minZoom + 1;
    final gridClusters = List.generate(levels, (_) => DistanceGrid<MarkerClusterNode>(config.maxClusterRadius));
    final gridUnclustered = List.generate(levels, (_) => DistanceGrid<MarkerNode>(config.maxClusterRadius));
    MarkerClusterNode newCluster(int zoom) => MarkerClusterNode(
      zoom: zoom,
      alignment: config.alignment,
      predefinedSize: config.size,
      computeSize: computeSize,
    );
    final top = newCluster(minZoom - 1);

    void removeFromUnclustered(MarkerNode marker, int zoom) {
      for (; zoom >= minZoom; zoom--) {
        if (!gridUnclustered[zoom - minZoom].removeObject(marker)) break;
      }
    }

    void add(MarkerNode marker) {
      for (var zoom = maxZoom; zoom >= minZoom; zoom--) {
        final markerPoint = _project(marker.point, zoom.toDouble());
        if (zoom <= config.disableClusteringAtZoom) {
          final cluster = gridClusters[zoom - minZoom].getNearObject(markerPoint);
          if (cluster != null) {
            cluster.addChild(marker, marker.point);
            return;
          }
          final closest = gridUnclustered[zoom - minZoom].getNearObject(markerPoint);
          if (closest != null) {
            final parent = closest.parent!..removeChild(closest);
            final cluster = newCluster(zoom)
              ..addChild(closest, closest.point)
              ..addChild(marker, closest.point);
            gridClusters[zoom - minZoom].addObject(cluster, _project(cluster.bounds.center, zoom.toDouble()));
            var lastParent = cluster;
            for (var z = zoom - 1; z > parent.zoom; z--) {
              lastParent = newCluster(z)..addChild(lastParent, lastParent.bounds.center);
              gridClusters[z - minZoom].addObject(lastParent, _project(closest.point, z.toDouble()));
            }
            parent.addChild(lastParent, lastParent.bounds.center);
            removeFromUnclustered(closest, zoom);
            return;
          }
        }
        gridUnclustered[zoom - minZoom].addObject(marker, markerPoint);
      }
      top.addChild(marker, marker.point);
    }

    final ids = Expando<String>();
    final nodes = <String, MarkerOrClusterNode>{};
    final leaves = List<MarkerNode?>.filled(markers.length, null);
    var skipped = 0;
    for (final (index, marker) in markers.indexed) {
      if (!hasFinitePoint(marker)) {
        skipped++;
        continue;
      }
      final node = MarkerNode(marker);
      final id = markerId(marker, index);
      assert(!nodes.containsKey(id), 'Duplicate marker key ${marker.key} in MarkerClusterLayerOptions.markers');
      ids[node] = id;
      nodes[id] = node;
      leaves[index] = node;
      add(node);
    }
    if (skipped > 0) reportNonFinite(skipped, markers.length);
    MarkerNode firstMarker(MarkerClusterNode cluster) =>
        cluster.children.whereType<MarkerNode>().firstOrNull ??
        firstMarker(cluster.children.whereType<MarkerClusterNode>().first);
    void name(MarkerClusterNode cluster) {
      for (final child in cluster.children) {
        if (child is MarkerClusterNode) {
          final leaf = ids[firstMarker(child)]!;
          final id = '$clusterIdPrefix${child.zoom}:${leaf.substring(leaf.indexOf('/') + 1)}';
          ids[child] = id;
          nodes[id] = child;
          name(child);
        }
      }
    }

    name(top);
    return ClusterIndex._(config, top, nodes, ids, List.of(markers), leaves);
  }

  /// Takes [markers] instead of the markers the tree was built from when they have the same keys and points, which
  /// is all the tree and its ids depend on; the nodes then hand out the new markers. False when the tree must be
  /// built again.
  bool adopt(List<Marker> markers) {
    final source = _source;
    if (markers.length != source.length) return false;
    var changed = false;
    for (var i = 0; i < markers.length; i++) {
      final current = source[i];
      final marker = markers[i];
      if (identical(current, marker)) continue;
      if (current.key != marker.key || !_samePoint(current.point, marker.point)) return false;
      changed = true;
    }
    if (!changed) return true;
    for (var i = 0; i < markers.length; i++) {
      source[i] = markers[i];
      final leaf = _leaves[i];
      if (leaf != null) replaceMarkerOf(leaf, markers[i]);
    }
    top.recalculate(recursively: true);
    return true;
  }

  /// Equal coordinates, NaN included: a marker left out stays left out.
  static bool _samePoint(LatLng a, LatLng b) =>
      (a.latitude == b.latitude || (a.latitude.isNaN && b.latitude.isNaN)) &&
      (a.longitude == b.longitude || (a.longitude.isNaN && b.longitude.isNaN));

  String idOf(MarkerOrClusterNode node) => _ids[node]!;

  /// The nodes shown at [level] whose position lies in [area], as flutter_map_marker_cluster lists them.
  List<MarkerOrClusterNode> visible(int level, LatLngBounds area) {
    final result = <MarkerOrClusterNode>[];
    top.recursively(level, config.disableClusteringAtZoom, area, (node) {
      if (area.contains(node.position)) result.add(node);
    });
    return result;
  }
}
