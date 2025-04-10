import 'package:flutter/foundation.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

/// Whether [marker] can be clustered: a NaN or infinite coordinate has no place in the grid.
bool hasFinitePoint(Marker marker) => marker.point.latitude.isFinite && marker.point.longitude.isFinite;

/// Reports the markers of `MarkerClusterLayerOptions.markers` left out by [hasFinitePoint].
void reportNonFinite(int skipped, int total) => FlutterError.reportError(
  FlutterErrorDetails(
    exception: ArgumentError('$skipped of $total markers have a coordinate that is not finite'),
    library: 'flutter_unified_map_marker_cluster',
    context: ErrorDescription('while clustering MarkerClusterLayerOptions.markers; they are not shown'),
  ),
);
