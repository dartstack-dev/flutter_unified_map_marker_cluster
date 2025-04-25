import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_marker_cluster_example/main.dart';
import 'package:flutter_unified_map_marker_cluster_example/src/demo_data.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show PlatformMarkerTapEvent, PlatformMapTapEvent, UnifiedMapsPlatform;
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';
import 'support/macos_test_window.dart';
import 'support/recording_platform.dart';

import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' as pi show Offset;

/// Runs the real demo app, opens its Spiderfy page and spiderfies its single cluster. Each state is asserted and
/// logged, so the host can capture screenshots of the app at CLUSTER-READY (the cluster before the tap),
/// SPIDER-READY (the spider once its legs are drawn) and SPIDER-CLOSED (back to the cluster).
///
/// On iOS and macOS synthetic Flutter taps do not reach UIKit / AppKit platform views, so the marker tap is
/// injected as the native tap event — the same event a real tap produces.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  holdMacOSTestWindowInFront();

  late UnifiedMapsPlatform real;
  late RecordingPlatform recorder;

  setUp(() {
    real = UnifiedMapsPlatform.instance;
    recorder = RecordingPlatform(real);
    UnifiedMapsPlatform.instance = recorder;
  });

  tearDown(() => UnifiedMapsPlatform.instance = real);

  bool at(LatLng a, LatLng b) => (a.latitude - b.latitude).abs() < 1e-9 && (a.longitude - b.longitude).abs() < 1e-9;

  testWidgets('the demo app shows the spiderfy effect', (tester) async {
    await tester.pumpWidget(const ClusterExampleApp());
    await pumpUntil(tester, () => recorder.builtViews.isNotEmpty, timeout: const Duration(seconds: 30));

    await tester.tap(find.text('Spiderfy'));
    await pumpUntil(tester, () => recorder.builtViews.length >= 2, timeout: const Duration(seconds: 30));
    final viewId = recorder.builtViews.keys.last;
    await pumpUntil(
      tester,
      () => recorder.markers.values.any((m) => m.id.contains('/c') && at(m.position, spiderfySpot.point)),
      timeout: const Duration(seconds: 30),
    );

    final cluster = recorder.markers.values.firstWhere(
      (m) => m.id.contains('/c') && at(m.position, spiderfySpot.point),
    );
    log('screenshot', 'CLUSTER-READY (cluster ${cluster.id})');
    await pumpFor(tester, const Duration(seconds: 10));

    recorder.inject(PlatformMarkerTapEvent(viewId, cluster.id));
    final opened = await pumpUntil(
      tester,
      () => recorder.polylines.length == spiderfySpot.count,
      timeout: const Duration(seconds: 20),
    );
    expect(opened, isTrue, reason: 'the single cluster spiderfies: every leg is drawn');
    log('screenshot', 'SPIDER-READY');
    await pumpFor(tester, const Duration(seconds: 20));

    recorder.inject(PlatformMapTapEvent(viewId, spiderfySpot.point, const pi.Offset(5, 5)));
    final closed = await pumpUntil(tester, () => recorder.polylines.isEmpty, timeout: const Duration(seconds: 15));
    expect(closed, isTrue, reason: 'a map tap closes the spider');
    log('screenshot', 'SPIDER-CLOSED');
    await pumpFor(tester, const Duration(seconds: 10));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
