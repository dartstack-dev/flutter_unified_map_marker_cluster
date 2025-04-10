import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

/// Where flutter_map's `CameraFit.bounds(...).fit(camera)` puts the camera, so that a cluster tap decides between
/// zooming and spiderfying exactly as flutter_map_marker_cluster does.
({LatLng center, double zoom}) fitBounds(
  MapCamera camera,
  LatLngBounds bounds, {
  EdgeInsets padding = EdgeInsets.zero,
  double? maxZoom,
  bool forceIntegerZoomLevel = false,
  double? zoom,
}) {
  final paddingTL = Offset(padding.left, padding.top);
  final paddingBR = Offset(padding.right, padding.bottom);
  final newZoom = zoom ?? _boundsZoom(camera, bounds, paddingTL + paddingBR, maxZoom, forceIntegerZoomLevel);
  final paddingOffset = (paddingBR - paddingTL) / 2;
  final sw = camera.projectAtZoom(bounds.southWest, newZoom);
  final ne = camera.projectAtZoom(bounds.northEast, newZoom);
  final rad = camera.rotationRad;
  final projectedCenter = rad == 0
      ? (sw + ne) / 2 + paddingOffset
      : rotatePoint((rotatePoint(sw, rad) + rotatePoint(ne, rad)) / 2 + paddingOffset, -rad);
  return (center: camera.unprojectAtZoom(projectedCenter, newZoom), zoom: newZoom);
}

double _boundsZoom(MapCamera camera, LatLngBounds bounds, Offset padding, double? maxZoom, bool forceInteger) {
  final size = Size(
    math.max(0, camera.nonRotatedSize.width - padding.dx),
    math.max(0, camera.nonRotatedSize.height - padding.dy),
  );
  var boundsSize = Rect.fromPoints(camera.projectAtZoom(bounds.southEast), camera.projectAtZoom(bounds.northWest)).size;
  if (camera.rotation != 0) {
    final cos = math.cos(camera.rotationRad).abs();
    final sin = math.sin(camera.rotationRad).abs();
    boundsSize = Size(
      boundsSize.width * cos + boundsSize.height * sin,
      boundsSize.height * cos + boundsSize.width * sin,
    );
  }
  final scale = math.min(size.width / boundsSize.width, size.height / boundsSize.height);
  var zoom = camera.zoom + math.log(scale) / math.ln2;
  if (forceInteger) zoom = zoom.floorToDouble();
  final upper = math.min(camera.maxZoom ?? double.infinity, maxZoom ?? double.infinity);
  return zoom.clamp(camera.minZoom ?? 0, upper);
}

/// [p] rotated by [rad] radians, as `MapCamera` turns projected offsets into screen offsets.
Offset rotatePoint(Offset p, double rad) {
  final cos = math.cos(rad);
  final sin = math.sin(rad);
  return Offset(p.dx * cos - p.dy * sin, p.dx * sin + p.dy * cos);
}
