import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/plugin_api.dart';
import 'package:flutter_unified_map_marker_cluster/src/core/cluster_index.dart';
import 'package:flutter_unified_map_marker_cluster/src/native/transition_planner.dart';

void main() {
  final markers = [
    for (final (name, point) in [
      ('p1', const LatLng(48.0, 2.0)),
      ('p2', const LatLng(48.0, 2.2)),
      ('p3', const LatLng(48.05, 3.0)),
    ])
      Marker(key: ValueKey(name), point: point, child: const SizedBox()),
  ];
  final index = ClusterIndex.build(
    markers: markers,
    config: const ClusterConfig(
      minZoom: 1,
      maxZoom: 20,
      maxClusterRadius: 80,
      disableClusteringAtZoom: 20,
      alignment: null,
      size: Size(30, 30),
    ),
    markerId: (marker, i) => 'L/${(marker.key! as ValueKey<String>).value}',
    clusterIdPrefix: 'L/c',
  );
  final world = LatLngBounds.unsafe(north: 90, south: -90, east: 180, west: -180);

  List<MarkerSpec> level(int zoom) => [
    for (final node in index.visible(zoom, world))
      MarkerSpec(
        id: index.idOf(node),
        position: node.position,
        iconKey: index.idOf(node),
        child: const SizedBox(),
        size: const Size(30, 30),
      ),
  ];

  LatLng at(List<MarkerSpec> specs, String id) => specs.firstWhere((s) => s.id == id).position;

  const half = Duration(milliseconds: 500);

  test('a split slides the new elements out of the cluster on the map; a merge slides them back in', () {
    final level6 = level(6);
    final level8 = level(8);
    final top = level6.single;
    final split = TransitionPlanner().plan(index, level6, level8, Duration.zero);
    expect(split.appearFrom, {for (final spec in level8) spec.id: top.position});
    expect(split.disappearTo, isEmpty);

    final merge = TransitionPlanner().plan(index, level8, level6, Duration.zero);
    expect(merge.appearFrom, isEmpty);
    expect(merge.disappearTo, {for (final spec in level8) spec.id: top.position});
    expect(merge.clustered, {
      top.id: ['L/p3'],
    }, reason: 'only markers shown alone are reported as clustered');
  });

  test('an element appears from where its container is in the middle of its own glide', () {
    final planner = TransitionPlanner();
    final level6 = level(6);
    final level8 = level(8);
    final level10 = level(10);
    final top = level6.single.position;
    final first = planner.plan(index, level6, level8, Duration.zero);
    planner.track(
      level6,
      level8,
      MarkerTransition(duration: half, appearFrom: first.appearFrom, disappearTo: first.disappearTo),
      Duration.zero,
    );
    final pairId = level8.firstWhere((s) => s.id.contains('/c')).id;
    final pair = at(level8, pairId);

    final second = planner.plan(index, level8, level10, const Duration(milliseconds: 100));
    final t = Curves.easeInOut.transform(0.2);
    final glided = LatLng(
      top.latitude + (pair.latitude - top.latitude) * t,
      top.longitude + (pair.longitude - top.longitude) * t,
    );
    expect(second.appearFrom.keys, unorderedEquals(['L/p1', 'L/p2']));
    for (final from in second.appearFrom.values) {
      expect(from.latitude, closeTo(glided.latitude, 1e-9));
      expect(from.longitude, closeTo(glided.longitude, 1e-9));
    }

    final settled = planner.plan(index, level8, level10, half);
    expect(settled.appearFrom.values, everyElement(pair), reason: 'the glide is over');
  });

  test('elements still leaving are sent on into the element that now contains them', () {
    final planner = TransitionPlanner();
    final level6 = level(6);
    final level8 = level(8);
    final level10 = level(10);
    final merge = planner.plan(index, level10, level8, Duration.zero);
    planner.track(
      level10,
      level8,
      MarkerTransition(duration: half, appearFrom: merge.appearFrom, disappearTo: merge.disappearTo),
      Duration.zero,
    );
    final again = planner.plan(index, level8, level6, const Duration(milliseconds: 100));
    expect(again.disappearTo.keys, containsAll(['L/p1', 'L/p2']));
    expect(again.disappearTo['L/p1'], level6.single.position);

    planner.reset();
    expect(
      planner.plan(index, level8, level6, const Duration(milliseconds: 100)).disappearTo.keys,
      isNot(contains('L/p1')),
    );
  });
}
