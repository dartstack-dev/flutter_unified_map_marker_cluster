import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

const brussels = LatLng(50.8503, 4.3517);

@immutable
class Pin {
  const Pin({required this.id, required this.point});

  final String id;
  final LatLng point;
}

const _hubs = [
  LatLng(48.86, 2.35),
  LatLng(51.51, -0.13),
  LatLng(52.52, 13.40),
  LatLng(40.42, -3.70),
  LatLng(41.90, 12.50),
  LatLng(45.46, 9.19),
  LatLng(48.14, 11.58),
  LatLng(50.85, 4.35),
  LatLng(52.37, 4.90),
  LatLng(48.21, 16.37),
  LatLng(50.08, 14.44),
  LatLng(52.23, 21.01),
  LatLng(47.50, 19.04),
  LatLng(41.39, 2.17),
  LatLng(45.76, 4.84),
  LatLng(43.30, 5.37),
  LatLng(53.55, 9.99),
  LatLng(50.94, 6.96),
  LatLng(47.38, 8.54),
  LatLng(38.72, -9.14),
  LatLng(55.68, 12.57),
  LatLng(59.33, 18.07),
  LatLng(44.43, 26.10),
  LatLng(37.98, 23.73),
];

/// How many pins the demo shows.
const demoPinCount = 500;

/// The dense Brussels city network: it sits well inside one cluster radius at the demo's opening zoom, so the map
/// opens on a single cluster over Brussels that one tap spreads into every pin below it.
const brusselsNetwork = 120;

/// Deterministic pseudo-random pins: the Brussels city network first, then three quarters of the rest clustered
/// around large cities and the remainder spread over the continent, so every run (and every platform) shows the
/// same map.
List<Pin> generatePins({int count = demoPinCount, int seed = 42}) {
  final random = math.Random(seed);
  double gaussian() {
    final u = 1 - random.nextDouble();
    final v = random.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  return List.generate(count, (i) {
    final LatLng point;
    if (i < brusselsNetwork) {
      point = LatLng(brussels.latitude + gaussian() * 0.05, brussels.longitude + gaussian() * 0.08);
    } else if (random.nextDouble() < 0.75) {
      final hub = _hubs[random.nextInt(_hubs.length)];
      point = LatLng(hub.latitude + gaussian() * 0.6, hub.longitude + gaussian() * 0.9);
    } else {
      point = LatLng(37 + random.nextDouble() * 22, -8 + random.nextDouble() * 33);
    }
    return Pin(id: 'PIN-${(i + 1).toString().padLeft(4, '0')}', point: point);
  });
}

/// The Spiderfy page's single stack: every pin sits on the exact same point of Brussels, so the whole page shows
/// one cluster — a tap spreads the pins on a spiral around it.
const spiderfySpot = (name: 'Grand-Place', point: LatLng(50.8467, 4.3524), count: 30);

/// The Spiderfy page's pins: all stacked on [spiderfySpot].
List<Pin> generateSpiderfyPins() => [
  for (var i = 0; i < spiderfySpot.count; i++)
    Pin(id: 'SP-${(i + 1).toString().padLeft(3, '0')}', point: spiderfySpot.point),
];
