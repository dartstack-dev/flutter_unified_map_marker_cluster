import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';
import 'pixels.dart';
import 'recording_platform.dart';

@immutable
class VisibilityReport {
  const VisibilityReport({
    required this.published,
    required this.expected,
    required this.snapshotMissing,
    required this.screenMissing,
    required this.ghostPixels,
    required this.ghostLimit,
    required this.unpublished,
  });

  final int published;
  final int expected;

  /// Markers fully on screen whose color is not found in the native snapshot.
  final List<String> snapshotMissing;

  /// Same on the iOS screenshot (null elsewhere).
  final List<String>? screenMissing;

  /// Pixels of the pin or cluster color found outside every published marker: markers left behind.
  final int ghostPixels;
  final int ghostLimit;

  /// Points on screen with no published marker while clustering is off.
  final List<String> unpublished;

  bool get ok =>
      snapshotMissing.isEmpty && (screenMissing?.isEmpty ?? true) && ghostPixels <= ghostLimit && unpublished.isEmpty;

  @override
  String toString() =>
      'published $published, expected on screen $expected, missing in snapshot ${snapshotMissing.length} '
      '${snapshotMissing.take(6).toList()}, missing on screen ${screenMissing?.length}, ghost pixels $ghostPixels '
      '(limit $ghostLimit), unpublished ${unpublished.length} ${unpublished.take(5).toList()}';
}

/// Checks that every marker the core published and that lies fully on screen is drawn by the native map (color
/// found in its snapshot, and on iOS in a screenshot too), that nothing of the test colors is drawn elsewhere, and,
/// when [allPoints] is given and clustering is off at the camera's zoom (above [clusteringOffAbove]), that every
/// point on screen has a published marker.
Future<VisibilityReport> checkVisibility(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  RecordingPlatform recorder,
  MapController controller, {
  required String label,
  List<(String, LatLng)>? allPoints,
  int? clusteringOffAbove,
  Set<String> ignore = const {},
}) async {
  final camera = controller.camera;
  final size = camera.nonRotatedSize;
  final origin = tester.getTopLeft(find.byType(UnifiedMap));
  final expected = <String, ui.Rect>{};
  final known = <ui.Rect>[];
  for (final marker in recorder.markers.values) {
    final box = ui.Rect.fromCenter(
      center: camera.latLngToScreenOffset(marker.position),
      width: marker.icon.logicalSize.width,
      height: marker.icon.logicalSize.height,
    );
    known.add(box.inflate(3));
    if (box.left < 0 || box.top < 0 || box.right > size.width || box.bottom > size.height) continue;
    if (!ignore.contains(marker.id)) expected[marker.id] = box;
  }

  Future<(List<String>, int, int)> inspect(RgbaImage image, ui.Offset offset) async {
    final scale = image.width / (tester.view.physicalSize.width / tester.view.devicePixelRatio);
    ui.Rect toImage(ui.Rect box) => ui.Rect.fromLTRB(
      (box.left + offset.dx) * scale,
      (box.top + offset.dy) * scale,
      (box.right + offset.dx) * scale,
      (box.bottom + offset.dy) * scale,
    );
    final missing = <String>[];
    for (final MapEntry(key: id, value: box) in expected.entries) {
      final marker = recorder.markers[id]!;
      final color = id.contains('/c') ? clusterColor : pinColor;
      final hits = countPixelsNear(image, color, tolerance: 40, region: toImage(box));
      final area = marker.icon.logicalSize.width * marker.icon.logicalSize.height * scale * scale;
      if (hits < area * 0.1) missing.add(id);
    }
    final mapArea = toImage(ui.Rect.fromLTWH(0, 0, size.width, size.height));
    final knownInImage = [for (final box in known) toImage(box)];
    var ghosts = 0;
    for (final color in [pinColor, clusterColor]) {
      ghosts += countPixelsNear(image, color, tolerance: 40, region: mapArea, exclude: knownInImage);
    }
    return (missing, ghosts, (44 * 44 * scale * scale * 0.3).round());
  }

  final unpublished = <String>[];
  if (allPoints != null && clusteringOffAbove != null && camera.zoom > clusteringOffAbove + 1e-6) {
    final published = {
      for (final id in recorder.markers.keys)
        if (id.contains('/k:')) id.substring(id.indexOf('/k:') + 3),
    };
    for (final (id, point) in allPoints) {
      final p = camera.latLngToScreenOffset(point);
      if (p.dx < 25 || p.dy < 25 || p.dx > size.width - 25 || p.dy > size.height - 25) continue;
      if (!published.contains(id)) unpublished.add(id);
    }
  }

  final snapshotBytes = await tester.runAsync(controller.takeSnapshot);
  final snapshot = snapshotBytes == null ? null : await tester.runAsync(() => decodePng(snapshotBytes));
  // Without a snapshot nothing can be checked: that fails the check rather than passing it.
  final fromSnapshot = snapshot == null ? (['<no snapshot>'], 0, 0) : await inspect(snapshot, ui.Offset.zero);

  List<String>? screenMissing;
  if (Platform.isIOS) {
    final bytes = Uint8List.fromList(await binding.takeScreenshot('visibility-$label'));
    final screen = await tester.runAsync(() => decodePng(bytes));
    screenMissing = (await inspect(screen!, origin)).$1;
  }
  return VisibilityReport(
    published: recorder.markers.length,
    expected: expected.length,
    snapshotMissing: fromSnapshot.$1,
    screenMissing: screenMissing,
    ghostPixels: fromSnapshot.$2,
    ghostLimit: fromSnapshot.$3,
    unpublished: unpublished,
  );
}
