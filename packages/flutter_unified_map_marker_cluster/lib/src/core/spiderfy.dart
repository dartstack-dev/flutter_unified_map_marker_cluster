// Port of flutter_map_marker_cluster 8.2.2's Spiderfy (BSD-3-Clause, Copyright (c) 2018 Lorenzo Pongetti; see
// LICENSE), kept identical so that native spiders have the same shape.
import 'dart:math';
import 'dart:ui';

abstract final class Spiderfy {
  static const pi2 = pi * 2;
  static const spiralFootSeparation = 28;
  static const spiralLengthStart = 11;
  static const spiralLengthFactor = 5;
  static const circleStartAngle = 0;

  static List<Offset?> spiral(int distanceMultiplier, int count, Offset center) {
    num legLength = distanceMultiplier * spiralLengthStart;
    final separation = distanceMultiplier * spiralFootSeparation;
    final lengthFactor = distanceMultiplier * spiralLengthFactor * pi2;
    num angle = 0;
    final result = List<Offset?>.filled(count, null);
    // Higher index, closer to the center; the first position is skipped so that no marker sits under the cluster.
    for (var i = count; i >= 0; i--) {
      if (i < count) result[i] = Offset(center.dx + legLength * cos(angle), center.dy + legLength * sin(angle));
      angle += separation / legLength + i * 0.0005;
      legLength += lengthFactor / angle;
    }
    return result;
  }

  static List<Offset?> circle(int radius, int count, Offset center) {
    final angleStep = pi2 / count;
    return List<Offset>.generate(count, (index) {
      final angle = circleStartAngle + index * angleStep;
      return Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
    });
  }
}
