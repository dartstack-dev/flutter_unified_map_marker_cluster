import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart' as fmmc;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_flutter_map/flutter_unified_map_flutter_map.dart';
import 'package:flutter_unified_map_marker_cluster_example/src/demo_data.dart';
import 'package:flutter_unified_map_marker_cluster_example/src/map_widgets.dart';
import 'package:flutter_unified_map_marker_cluster_example/src/spiderfy_page.dart';
import 'package:flutter_unified_map_marker_cluster_example/src/pins_page.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show UnifiedMapsPlatform;

/// The demo scenes on the pure Dart flutter_map backend (web, Windows, Linux), with no base map and no network:
/// clustering there is the real flutter_map_marker_cluster.
void main() {
  setUp(() => UnifiedMapsPlatform.instance = UnifiedMapsFlutterMap());

  Widget app(Widget map) => MaterialApp(home: Scaffold(body: map));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('the opening view shows the Brussels network as one cluster', (tester) async {
    await tester.pumpWidget(app(const PinsMap(mapStyle: MapStyle.none)));
    await settle(tester);
    expect(find.byType(fmmc.MarkerClusterLayerWidget), findsOneWidget);
    expect(find.descendant(of: find.byType(fm.FlutterMap), matching: find.byType(ClusterBadge)), findsWidgets);
    final badges = tester.widgetList<ClusterBadge>(find.byType(ClusterBadge)).toList();
    final biggest = badges.reduce((a, b) => a.count > b.count ? a : b);
    expect(biggest.count, greaterThan(brusselsNetwork), reason: 'the whole Brussels city network sits in one cluster');
    expect(
      badges.where((b) => b != biggest).every((b) => b.count < 50),
      isTrue,
      reason: 'everything else around Brussels stays in small clusters',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the Brussels cluster zooms in and reveals its pins', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(PinsMap(controller: controller, mapStyle: MapStyle.none)));
    await settle(tester);
    final badges = tester.widgetList<ClusterBadge>(find.byType(ClusterBadge)).toList();
    final biggest = badges.reduce((a, b) => a.count > b.count ? a : b);
    await tester.tap(find.byWidget(biggest).first);
    await settle(tester);
    expect(controller.camera.zoom, greaterThan(10), reason: 'the fit lands past disableClusteringAtZoom');
    expect(
      tester.widgetList<DemoPin>(find.byType(DemoPin)).length,
      greaterThanOrEqualTo(brusselsNetwork),
      reason: 'every pin below the cluster is on the map',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a stacked cluster spiderfies it on flutter_map', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(SpiderfyMap(controller: controller, mapStyle: MapStyle.none)));
    await settle(tester);
    controller.move(spiderfySpot.point, 16);
    await settle(tester);
    final badge = find.byWidgetPredicate((w) => w is ClusterBadge && w.count == spiderfySpot.count);
    expect(badge, findsOneWidget);
    expect(find.byType(DemoPin), findsNothing);
    await tester.tap(badge);
    await settle(tester);
    expect(controller.camera.zoom, 17, reason: 'flutter_map_marker_cluster first zooms to its maxZoom (17)');
    await tester.tap(badge);
    await settle(tester);
    expect(find.byType(DemoPin), findsNWidgets(spiderfySpot.count));
    await tester.pumpWidget(const SizedBox());
  });
}
