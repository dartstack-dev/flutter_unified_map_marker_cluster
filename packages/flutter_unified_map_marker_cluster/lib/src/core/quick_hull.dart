// Port of flutter_map_marker_cluster 8.2.2's QuickHull (BSD-3-Clause, Copyright (c) 2018 Lorenzo Pongetti; see
// LICENSE).
import 'package:flutter_unified_map/flutter_unified_map.dart';

abstract final class QuickHull {
  static double _distance(LatLng point, List<LatLng> baseLine) {
    final vY = baseLine[1].latitude - baseLine[0].latitude;
    final vX = baseLine[0].longitude - baseLine[1].longitude;
    return vX * (point.latitude - baseLine[0].latitude) + vY * (point.longitude - baseLine[0].longitude);
  }

  static List<LatLng> _build(List<LatLng> baseLine, List<LatLng> points) {
    var maxD = 0.0;
    LatLng? maxPoint;
    final outside = <LatLng>[];
    for (var i = points.length - 1; i >= 0; i--) {
      final point = points[i];
      final d = _distance(point, baseLine);
      if (d <= 0) continue;
      outside.add(point);
      if (d > maxD) {
        maxD = d;
        maxPoint = point;
      }
    }
    if (maxPoint == null) return [baseLine[0]];
    return [
      ..._build([baseLine[0], maxPoint], outside),
      ..._build([maxPoint, baseLine[1]], outside),
    ];
  }

  static List<LatLng> getConvexHull(List<LatLng> points) {
    double? maxLat, minLat, maxLng, minLng;
    LatLng? maxLatPoint, minLatPoint, maxLngPoint, minLngPoint;
    for (var i = points.length - 1; i >= 0; i--) {
      final point = points[i];
      if (maxLat == null || point.latitude > maxLat) {
        maxLatPoint = point;
        maxLat = point.latitude;
      }
      if (minLat == null || point.latitude < minLat) {
        minLatPoint = point;
        minLat = point.latitude;
      }
      if (maxLng == null || point.longitude > maxLng) {
        maxLngPoint = point;
        maxLng = point.longitude;
      }
      if (minLng == null || point.longitude < minLng) {
        minLngPoint = point;
        minLng = point.longitude;
      }
    }
    final (minPoint, maxPoint) = minLat != maxLat ? (minLatPoint!, maxLatPoint!) : (minLngPoint!, maxLngPoint!);
    return [
      ..._build([minPoint, maxPoint], points),
      ..._build([maxPoint, minPoint], points),
    ];
  }
}
