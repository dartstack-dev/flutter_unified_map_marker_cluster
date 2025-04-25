import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster_example/src/demo_data.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show PlatformCameraIdleEvent, PlatformMarkerTransition, UnifiedMapsPlatform;
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';
import 'support/macos_test_window.dart';
import 'support/recording_platform.dart';
import 'support/visibility.dart';

void _log(String message) => log('transition', message);

const _munich = LatLng(48.14, 11.58);

/// The animated transitions the layer sent since the [from]-th marker update, merged.
({Map<String, LatLng> appearFrom, Map<String, LatLng> disappearTo, Set<Duration> durations}) _sent(
  RecordingPlatform recorder,
  int from,
) {
  final appearFrom = <String, LatLng>{};
  final disappearTo = <String, LatLng>{};
  final durations = <Duration>{};
  for (final transition in recorder.markerTransitions.skip(from).whereType<PlatformMarkerTransition>()) {
    appearFrom.addAll(transition.appearFrom);
    disappearTo.addAll(transition.disappearTo);
    durations.add(transition.duration);
  }
  return (appearFrom: appearFrom, disappearTo: disappearTo, durations: durations);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  holdMacOSTestWindowInFront();

  late UnifiedMapsPlatform real;
  late RecordingPlatform recorder;

  setUp(() {
    real = UnifiedMapsPlatform.instance;
    recorder = RecordingPlatform(real);
    UnifiedMapsPlatform.instance = recorder;
  });

  tearDown(() => UnifiedMapsPlatform.instance = real);

  testWidgets('clusters split and merge with native transitions and end in the right state', (tester) async {
    if (recorder.supportsFlutterMapLayers) {
      markTestSkipped('flutter_map backend: transitions are flutter_map_marker_cluster\'s own');
      return;
    }
    final points = [for (final s in generatePins()) (s.id, s.point)];
    final scene = ClusterScene(recorder, points);
    await scene.start(tester, center: _munich, zoom: 7, disableClusteringAtZoom: 10);
    final controller = scene.controller;

    final level7 = {for (final m in recorder.markers.values) m.id: m.position};
    _log('level 7: ${level7.length} markers');

    var from = recorder.markerTransitions.length;
    controller.move(_munich, 8);
    await settleMarkers(tester, recorder);
    final split = _sent(recorder, from);
    final level8 = {for (final m in recorder.markers.values) m.id: m.position};
    _log('zoom in to 8: ${level8.length} markers, appearFrom ${split.appearFrom.length}, durations ${split.durations}');
    expect(split.durations, {const Duration(milliseconds: 500)});
    expect(split.appearFrom, isNotEmpty);
    for (final MapEntry(key: id, value: origin) in split.appearFrom.entries) {
      expect(level8.containsKey(id), isTrue, reason: '$id appeared and is on the map');
      expect(level7.containsKey(id), isFalse, reason: '$id is new at level 8');
      expect(level7.values, contains(origin), reason: '$id slides out of an element that was on the map');
    }
    expect(split.disappearTo, isEmpty, reason: 'split clusters fade out in place');
    expect(level8.keys.toSet().intersection(level7.keys.toSet()), isNotEmpty, reason: 'unchanged elements keep ids');
    var visibility = await checkVisibility(tester, binding, recorder, controller, label: 'split');
    _log('after the split: $visibility');
    expect(visibility.ok, isTrue, reason: '$visibility');

    from = recorder.markerTransitions.length;
    controller.move(_munich, 7);
    await settleMarkers(tester, recorder);
    final merge = _sent(recorder, from);
    final back = {for (final m in recorder.markers.values) m.id: m.position};
    _log('zoom out to 7: ${back.length} markers, disappearTo ${merge.disappearTo.length}');
    expect(merge.disappearTo, isNotEmpty);
    for (final MapEntry(key: id, value: target) in merge.disappearTo.entries) {
      expect(level8.containsKey(id), isTrue);
      expect(back.containsKey(id), isFalse);
      expect(back.values, contains(target), reason: '$id slides into an element now on the map');
    }
    expect(back.keys.toSet(), level7.keys.toSet(), reason: 'the same level and view give the same elements');

    _log('zoom during an animation: reclustered before idle');
    final idleAt = <int>[];
    final subscription = recorder.onEvent.listen((event) {
      if (event is PlatformCameraIdleEvent) idleAt.add(recorder.markerTransitions.length);
    });
    from = recorder.markerTransitions.length;
    var done = false;
    unawaited(
      controller
          .animateTo(dest: _munich, zoom: 9.5, duration: const Duration(milliseconds: 1500))
          .whenComplete(() => done = true),
    );
    await pumpUntil(tester, () => done && idleAt.isNotEmpty, timeout: const Duration(seconds: 10));
    await subscription.cancel();
    final beforeIdle = recorder.markerTransitions.sublist(from, idleAt.first).whereType<PlatformMarkerTransition>();
    _log('animated transitions sent before the idle event: ${beforeIdle.length}');
    expect(beforeIdle, isNotEmpty, reason: 'levels 8, 9 and 10 are reached while the camera moves');
    await settleMarkers(tester, recorder);

    _log('quick zoom steps');
    for (var i = 0; i < 12; i++) {
      final zoom = i.isEven ? 6.5 : 9.5;
      if (i % 3 == 0) {
        unawaited(controller.animateTo(dest: _munich, zoom: zoom, duration: const Duration(milliseconds: 300)));
      } else {
        controller.move(_munich, zoom);
      }
      await pumpFor(tester, Duration(milliseconds: 80 + 40 * (i % 4)));
    }
    controller.move(_munich, 8.4);
    await settleMarkers(tester, recorder);
    visibility = await checkVisibility(tester, binding, recorder, controller, label: 'quick');
    _log('after quick steps: $visibility');
    expect(visibility.ok, isTrue, reason: 'no marker missing, none left behind: $visibility');
    await scene.stop(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
