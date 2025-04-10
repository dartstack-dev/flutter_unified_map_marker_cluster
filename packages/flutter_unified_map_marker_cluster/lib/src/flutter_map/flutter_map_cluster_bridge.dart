import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart' as fmmc;
import 'package:flutter_unified_map/flutter_unified_map.dart';

import '../marker_cluster_layer_options.dart';
import '../markers.dart';
import '../node/marker_cluster_node.dart';
import '../node/marker_node.dart';

/// Builds the real flutter_map_marker_cluster layer for the platforms drawn with flutter_map, converting this
/// package's options and markers to flutter_map's and the callbacks' arguments back.
class FlutterMapClusterBridge {
  final String layerId;
  var _converted = Expando<fm.Marker>();
  final _original = Expando<Marker>();
  List<Marker>? _sourceMarkers;
  List<fm.Marker> _markers = const [];
  bool? _childBehavior;
  _TreeShape? _shape;

  FlutterMapClusterBridge(this.layerId);

  /// flutter_map_marker_cluster reads the animation durations only when its state is created: the key gives it a new
  /// state when they change, and keeps it with this layer among the map's other flutter_map layers. It reads the
  /// map's min and max zoom only then too: a change of those takes effect with the next state.
  Widget build(MarkerClusterLayerOptions options) {
    final a = options.animationsOptions;
    return fmmc.MarkerClusterLayerWidget(
      key: ValueKey((layerId, a.zoom, a.fitBound, a.centerMarker, a.spiderfy)),
      options: _options(options),
    );
  }

  fmmc.MarkerClusterLayerOptions _options(MarkerClusterLayerOptions o) {
    final animations = o.animationsOptions;
    final polygon = o.polygonOptions;
    final computeSize = o.computeSize;
    final onMarkerDoubleTap = o.onMarkerDoubleTap;
    final onMarkerHoverEnter = o.onMarkerHoverEnter;
    final onMarkerHoverExit = o.onMarkerHoverExit;
    final onClusterTap = o.onClusterTap;
    final onMarkersClustered = o.onMarkersClustered;
    return fmmc.MarkerClusterLayerOptions(
      builder: (context, markers) => o.builder(context, _back(markers)),
      rotate: o.rotate,
      markers: _markersOf(o),
      size: o.size,
      computeSize: computeSize == null ? null : (markers) => computeSize(_back(markers)),
      alignment: o.alignment,
      maxClusterRadius: o.maxClusterRadius,
      disableClusteringAtZoom: o.disableClusteringAtZoom,
      animationsOptions: fmmc.AnimationsOptions(
        zoom: animations.zoom,
        fitBound: animations.fitBound,
        fadeInCurve: animations.fadeInCurve,
        fadeOutCurve: animations.fadeOutCurve,
        clusterExpandCurve: animations.clusterExpandCurve,
        clusterCollapseCurve: animations.clusterCollapseCurve,
        spiderifyCurve: animations.spiderifyCurve,
        centerMarker: animations.centerMarker,
        spiderfy: animations.spiderfy,
        fitBoundCurves: animations.fitBoundCurves,
        centerMarkerCurves: animations.centerMarkerCurves,
      ),
      padding: o.padding,
      maxZoom: o.maxZoom,
      inside: o.inside,
      forceIntegerZoomLevel: o.forceIntegerZoomLevel,
      zoomToBoundsOnClick: o.zoomToBoundsOnClick,
      centerMarkerOnClick: o.centerMarkerOnClick,
      spiderfyCircleRadius: o.spiderfyCircleRadius,
      spiderfySpiralDistanceMultiplier: o.spiderfySpiralDistanceMultiplier,
      circleSpiralSwitchover: o.circleSpiralSwitchover,
      spiderfyShapePositions: o.spiderfyShapePositions,
      spiderfyCluster: o.spiderfyCluster,
      polygonOptions: fmmc.PolygonOptions(
        color: polygon.color,
        borderStrokeWidth: polygon.borderStrokeWidth,
        borderColor: polygon.borderColor,
        pattern: toFlutterMapPattern(polygon.pattern),
      ),
      showPolygon: o.showPolygon,
      onMarkerTap: (marker) {
        final original = _original[marker]!;
        o.onMarkerTap?.call(original);
        original.onTap?.call();
      },
      onMarkerDoubleTap: onMarkerDoubleTap == null ? null : (marker) => onMarkerDoubleTap(_original[marker]!),
      onMarkerHoverEnter: onMarkerHoverEnter == null ? null : (marker) => onMarkerHoverEnter(_original[marker]!),
      onMarkerHoverExit: onMarkerHoverExit == null ? null : (marker) => onMarkerHoverExit(_original[marker]!),
      onClusterTap: onClusterTap == null ? null : (cluster) => onClusterTap(_cluster(cluster, o)),
      onMarkersClustered: onMarkersClustered == null ? null : (markers) => onMarkersClustered(_back(markers)),
      markerChildBehavior: o.markerChildBehavior,
    );
  }

  /// The converted markers, kept identical while the source markers and the options the tree depends on are
  /// unchanged, so that flutter_map_marker_cluster does not rebuild its clusters on every rebuild. A new list makes
  /// it rebuild them: flutter_map_marker_cluster reads the clustering options only then.
  List<fm.Marker> _markersOf(MarkerClusterLayerOptions o) {
    final source = o.markers;
    final previous = _sourceMarkers;
    final shape = (
      maxClusterRadius: o.maxClusterRadius,
      disableClusteringAtZoom: o.disableClusteringAtZoom,
      size: o.size,
      alignment: o.alignment,
    );
    if (o.markerChildBehavior == _childBehavior &&
        shape == _shape &&
        previous != null &&
        _sameMarkers(previous, source)) {
      return _markers;
    }
    if (o.markerChildBehavior != _childBehavior) _converted = Expando<fm.Marker>();
    _childBehavior = o.markerChildBehavior;
    _shape = shape;
    _sourceMarkers = List.of(source);
    final markers = [
      for (final marker in source)
        if (hasFinitePoint(marker)) _converted[marker] ??= _convert(marker, o.markerChildBehavior),
    ];
    if (markers.length < source.length) reportNonFinite(source.length - markers.length, source.length);
    return _markers = markers;
  }

  fm.Marker _convert(Marker marker, bool childBehavior) {
    final onTap = marker.onTap;
    final converted = fm.Marker(
      key: marker.key,
      point: marker.point,
      width: marker.width,
      height: marker.height,
      alignment: marker.alignment,
      rotate: marker.rotate,
      // With markerChildBehavior, flutter_map_marker_cluster leaves taps to the child: Marker.onTap still fires.
      child: childBehavior && onTap != null
          ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: marker.child)
          : marker.child,
    );
    _original[converted] = marker;
    return converted;
  }

  List<Marker> _back(List<fm.Marker> markers) => [for (final marker in markers) _original[marker]!];

  MarkerClusterNode _cluster(fmmc.MarkerClusterNode source, MarkerClusterLayerOptions o) {
    final computeSize = o.computeSize;
    final node = MarkerClusterNode(
      zoom: source.zoom,
      alignment: source.alignment,
      predefinedSize: source.predefinedSize,
      computeSize: computeSize,
    );
    final clusters = source.children.whereType<fmmc.MarkerClusterNode>().toList();
    // flutter_map_marker_cluster lists a cluster's own markers first; its MarkerNode type is not exported.
    final own = source.mapMarkers.length - clusters.fold<int>(0, (sum, cluster) => sum + cluster.mapMarkers.length);
    for (final marker in source.mapMarkers.take(own)) {
      final original = _original[marker]!;
      node.addChild(MarkerNode(original), original.point);
    }
    for (final cluster in clusters) {
      node.addChild(_cluster(cluster, o), cluster.bounds.center);
    }
    return node;
  }

  static bool _sameMarkers(List<Marker> a, List<Marker> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

typedef _TreeShape = ({int maxClusterRadius, int disableClusteringAtZoom, Size size, Alignment? alignment});

fm.StrokePattern toFlutterMapPattern(StrokePattern pattern) {
  final segments = pattern.segments;
  if (segments == null) return const fm.StrokePattern.solid();
  if (segments.length == 2 && segments[0] == 0 && segments[1] == 0) {
    return fm.StrokePattern.dotted(spacingFactor: pattern.toDashPattern(1)![1]);
  }
  return fm.StrokePattern.dashed(segments: segments);
}
