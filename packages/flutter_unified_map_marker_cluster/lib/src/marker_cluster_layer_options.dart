import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

import 'node/marker_cluster_node.dart';

/// Style of the convex hull shown over a cluster's markers while the map zooms to it
/// ([MarkerClusterLayerOptions.showPolygon]). Same fields as flutter_map_marker_cluster's. Native maps draw
/// [pattern] solid.
class PolygonOptions {
  /// Fill color of the hull.
  final Color color;

  /// Width of the hull's outline in logical pixels; 0 draws none.
  final double borderStrokeWidth;

  /// Color of the hull's outline.
  final Color borderColor;

  /// Dash pattern of the outline, on flutter_map only.
  final StrokePattern pattern;

  const PolygonOptions({
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.pattern = const StrokePattern.solid(),
  });
}

/// Durations and curves of the layer's animations. Same fields and defaults as flutter_map_marker_cluster's.
///
/// [zoom] animates clusters splitting and merging when the zoom level changes ([Duration.zero] turns it off),
/// [spiderfy] the markers of a spiderfied cluster gliding out and back, [fitBound] the camera moving to a tapped
/// cluster, [centerMarker] the camera centering a tapped marker. On Android, iOS and macOS the markers move with the
/// map's own ease-in-out curve, so [fadeInCurve], [fadeOutCurve], [clusterExpandCurve], [clusterCollapseCurve] and
/// [spiderifyCurve] apply only on the platforms drawn with flutter_map (web, Windows, Linux).
class AnimationsOptions {
  /// Curve of the elements fading in, on flutter_map only.
  final Curve fadeInCurve;

  /// Curve of the elements fading out, on flutter_map only.
  final Curve fadeOutCurve;

  /// Curve of a cluster's markers moving out of it, on flutter_map only.
  final Curve clusterExpandCurve;

  /// Curve of markers moving into their cluster, on flutter_map only.
  final Curve clusterCollapseCurve;

  /// Curve of a spiderfied cluster's markers moving out and back, on flutter_map only.
  final Curve spiderifyCurve;

  /// Duration of clusters splitting and merging when the zoom level changes.
  final Duration zoom;

  /// Duration of the camera move to a tapped cluster.
  final Duration fitBound;

  /// Curve of the camera move to a tapped cluster.
  final Curve fitBoundCurves;

  /// Duration of the camera move centering a tapped marker.
  final Duration centerMarker;

  /// Curve of the camera move centering a tapped marker.
  final Curve centerMarkerCurves;

  /// Duration of a spiderfied cluster's markers moving out and back.
  final Duration spiderfy;

  const AnimationsOptions({
    this.zoom = const Duration(milliseconds: 500),
    this.fitBound = const Duration(milliseconds: 500),
    this.fadeInCurve = Curves.easeInCubic,
    this.fadeOutCurve = Curves.easeInCubic,
    this.clusterExpandCurve = Curves.easeInCubic,
    this.clusterCollapseCurve = Curves.easeInCubic,
    this.spiderifyCurve = Curves.fastOutSlowIn,
    this.centerMarker = const Duration(milliseconds: 500),
    this.spiderfy = const Duration(milliseconds: 500),
    this.fitBoundCurves = Curves.fastOutSlowIn,
    this.centerMarkerCurves = Curves.fastOutSlowIn,
  });
}

/// Native maps only: style of the lines joining the markers of a spiderfied cluster to it, drawn once the markers
/// arrived. flutter_map_marker_cluster draws no legs, so there are none on web, Windows and Linux.
class SpiderLegOptions {
  final Color color;

  /// Width in logical pixels.
  final double strokeWidth;

  const SpiderLegOptions({this.color = const Color(0x99222222), this.strokeWidth = 1.5});
}

/// Builds the widget of a cluster from all the markers below it.
typedef ClusterWidgetBuilder = Widget Function(BuildContext context, List<Marker> markers);

/// Options of [MarkerClusterLayerWidget]: the fields, types and defaults of flutter_map_marker_cluster 8.2's
/// `MarkerClusterLayerOptions`, plus [clusterIconKey] and [spiderLegs].
///
/// On Android, iOS and macOS the markers and clusters are native map markers: every widget ([Marker.child], the
/// [builder]'s cluster widget) is rasterised into a bitmap, so it cannot react to gestures or animate by itself. The
/// options that need a Flutter widget on the map behave as follows there:
/// - [onMarkerDoubleTap], [onMarkerHoverEnter] and [onMarkerHoverExit] are never called (native markers report
///   single taps only);
/// - [markerChildBehavior] true skips [onMarkerTap] and [centerMarkerOnClick] (as on flutter_map); the marker's own
///   [Marker.onTap] is still called;
/// - [polygonOptions]'s pattern is drawn solid.
///
/// flutter_map_marker_cluster's `popupOptions` (flutter_map_marker_popup) is not available: show a popup from
/// [onMarkerTap] with a `MarkerLayer` or a Flutter overlay instead.
class MarkerClusterLayerOptions {
  /// Builds the widget of a cluster from its markers.
  final ClusterWidgetBuilder builder;

  /// The markers to cluster. Give them a [Marker.key]: object ids (and so the native transitions) follow the keys,
  /// while a marker without one is identified by its index, which shifts when the list changes. Keys must be
  /// unique. A marker whose coordinates are not finite is left out and reported.
  final List<Marker> markers;

  /// When true, markers and clusters stay upright when the map rotates. A marker stays upright when either this or
  /// its own [Marker.rotate] is true.
  final bool? rotate;

  /// Size of a cluster widget.
  final Size size;

  /// Size of a cluster widget computed from its markers; overrides [size].
  final Size Function(List<Marker>)? computeSize;

  /// Alignment of a cluster widget on its position (flutter_map `Marker.alignment` semantics).
  final Alignment? alignment;

  /// A cluster covers at most this many pixels from its center.
  final int maxClusterRadius;

  /// Tapping a cluster zooms the map to its markers' bounds.
  final bool zoomToBoundsOnClick;

  /// Durations and curves of the clusters' and the camera's animations.
  final AnimationsOptions animationsOptions;

  /// Tapping a marker centers the map on it.
  final bool centerMarkerOnClick;

  /// Tapping a cluster that cannot be split by zooming spreads its markers around it.
  final bool spiderfyCluster;

  /// Distance in pixels of the markers of a spiderfied cluster laid out on a circle.
  final int spiderfyCircleRadius;

  /// Above this zoom level markers are no longer clustered.
  final int disableClusteringAtZoom;

  /// Spacing multiplier of the markers of a spiderfied cluster laid out on a spiral.
  final int spiderfySpiralDistanceMultiplier;

  /// From this many markers on, a spiderfied cluster uses a spiral instead of a circle.
  final int circleSpiralSwitchover;

  /// Custom positions (in pixels, around the given center) of the markers of a spiderfied cluster.
  final List<Offset> Function(int, Offset)? spiderfyShapePositions;

  /// Shows the convex hull of a cluster's markers while the map zooms to it.
  final bool showPolygon;

  /// Style of the convex hull of [showPolygon].
  final PolygonOptions polygonOptions;

  /// Called with the tapped marker.
  final void Function(Marker)? onMarkerTap;

  /// Not called on Android, iOS and macOS.
  final void Function(Marker)? onMarkerDoubleTap;

  /// Not called on Android, iOS and macOS.
  final void Function(Marker)? onMarkerHoverEnter;

  /// Not called on Android, iOS and macOS.
  final void Function(Marker)? onMarkerHoverExit;

  /// Called with the markers that join a cluster when the map zooms out or a spiderfied cluster closes.
  final void Function(List<Marker>)? onMarkersClustered;

  /// Called with the tapped cluster, before the camera moves or the cluster spiderfies.
  final void Function(MarkerClusterNode)? onClusterTap;

  /// When true, a marker's taps are left to its child (flutter_map) and [onMarkerTap], hover and
  /// [centerMarkerOnClick] are skipped.
  final bool markerChildBehavior;

  /// Padding of the camera fit when a cluster is tapped.
  final EdgeInsets padding;

  /// Highest zoom of the camera fit when a cluster is tapped.
  final double maxZoom;

  /// Accepted for compatibility; unused, as in flutter_map_marker_cluster.
  final bool inside;

  /// Rounds the zoom of the camera fit when a cluster is tapped down to an integer.
  final bool forceIntegerZoomLevel;

  /// Native maps only: key of the bitmap of a cluster widget, so equal keys share one rasterised bitmap. Defaults to
  /// the number of markers, which is right when [builder] depends only on the count; return a key that captures
  /// everything the cluster widget shows otherwise (e.g. `(markers.length, colorOf(markers))`). The theme, text
  /// style, text direction, brightness and text scale need not be in it: when they change, the map rasterises every
  /// icon again.
  final Object Function(List<Marker> markers)? clusterIconKey;

  /// Native maps only: the legs of a spiderfied cluster; null draws none.
  final SpiderLegOptions? spiderLegs;

  const MarkerClusterLayerOptions({
    required this.builder,
    this.rotate,
    this.markers = const [],
    this.size = const Size(30, 30),
    this.computeSize,
    this.alignment,
    this.maxClusterRadius = 80,
    this.disableClusteringAtZoom = 20,
    this.animationsOptions = const AnimationsOptions(),
    this.padding = EdgeInsets.zero,
    this.maxZoom = 17.0,
    this.inside = false,
    this.forceIntegerZoomLevel = false,
    this.zoomToBoundsOnClick = true,
    this.centerMarkerOnClick = true,
    this.spiderfyCircleRadius = 40,
    this.spiderfySpiralDistanceMultiplier = 1,
    this.circleSpiralSwitchover = 9,
    this.spiderfyShapePositions,
    this.spiderfyCluster = true,
    this.polygonOptions = const PolygonOptions(),
    this.showPolygon = true,
    this.onMarkerTap,
    this.onMarkerDoubleTap,
    this.onMarkerHoverEnter,
    this.onMarkerHoverExit,
    this.onClusterTap,
    this.onMarkersClustered,
    this.markerChildBehavior = false,
    this.clusterIconKey,
    this.spiderLegs = const SpiderLegOptions(),
  });
}
