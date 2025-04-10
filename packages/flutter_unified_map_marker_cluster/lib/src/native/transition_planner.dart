import 'package:flutter/animation.dart';
import 'package:flutter_unified_map/plugin_api.dart';

import '../core/cluster_index.dart';
import '../node/marker_node.dart';

/// Where the elements of a new generation come from and where the leaving ones go, by object id. [clustered] lists,
/// per cluster, the ids of the markers shown alone that join it.
typedef TransitionPlan = ({
  Map<String, LatLng> appearFrom,
  Map<String, LatLng> disappearTo,
  Map<String, List<String>> clustered,
});

/// Plans how the markers on the map become a new generation: a new element slides out of the element on the map
/// that contains it (a cluster splitting, a spider opening), an element leaving slides into the new element that
/// contains it (clusters merging, a spider closing); the others fade.
///
/// What is on the map ([MarkerPublisher.published]) may not have reached the platform yet (the map merges the
/// generations set before one push) or still be gliding there: the planner remembers the glides it planned, so that
/// an element slides out of where its container is now on screen, and sends the elements still leaving on into the
/// new element that contains them. Times are durations on one monotonic clock.
class TransitionPlanner {
  final _arriving = <String, _Glide>{};
  final _leaving = <String, Duration>{};

  TransitionPlan plan(ClusterIndex index, List<MarkerSpec> published, List<MarkerSpec> next, Duration now) {
    final onMap = {for (final spec in published) spec.id: spec.position};
    final nextIds = {for (final spec in next) spec.id: spec.position};
    final appearFrom = <String, LatLng>{};
    final disappearTo = <String, LatLng>{};
    final clustered = <String, List<String>>{};
    for (final id in nextIds.keys) {
      if (onMap.containsKey(id)) continue;
      final container = _container(index, id, onMap);
      if (container != null) appearFrom[id] = _arriving[container]?.at(now, onMap[container]!) ?? onMap[container]!;
    }
    for (final id in onMap.keys) {
      if (nextIds.containsKey(id)) continue;
      final container = _container(index, id, nextIds);
      if (container == null) continue;
      disappearTo[id] = nextIds[container]!;
      if (index.nodes[id] is MarkerNode) (clustered[container] ??= []).add(id);
    }
    for (final MapEntry(key: id, value: end) in _leaving.entries) {
      if (end <= now || onMap.containsKey(id) || nextIds.containsKey(id)) continue;
      final container = _container(index, id, nextIds);
      if (container != null) disappearTo[id] = nextIds[container]!;
    }
    return (appearFrom: appearFrom, disappearTo: disappearTo, clustered: clustered);
  }

  /// Records that [next] replaces [published] on the map at [now], animated by [transition] or at once.
  void track(List<MarkerSpec> published, List<MarkerSpec> next, MarkerTransition? transition, Duration now) {
    _arriving.removeWhere((_, glide) => glide.end <= now);
    _leaving.removeWhere((_, end) => end <= now);
    final before = {for (final spec in published) spec.id};
    final after = <String>{};
    for (final spec in next) {
      after.add(spec.id);
      if (before.contains(spec.id)) continue;
      final from = transition?.appearFrom[spec.id];
      if (from == null) {
        _arriving.remove(spec.id);
      } else {
        _arriving[spec.id] = _Glide(from, spec.position, now, transition!.duration);
      }
      _leaving.remove(spec.id);
    }
    if (transition == null) return;
    for (final id in before) {
      if (!after.contains(id)) _leaving[id] = now + transition.duration;
    }
  }

  /// Forgets every glide, for a map that shows none of them.
  void reset() {
    _arriving.clear();
    _leaving.clear();
  }

  /// The id in [ids] of the closest cluster above the node [id].
  static String? _container(ClusterIndex index, String id, Map<String, LatLng> ids) {
    for (var parent = index.nodes[id]?.parent; parent != null; parent = parent.parent) {
      if (parent == index.top) return null;
      final parentId = index.idOf(parent);
      if (ids.containsKey(parentId)) return parentId;
    }
    return null;
  }
}

/// An element sliding from [from] to [to] with the platform's ease-in-out, from [start].
class _Glide {
  final LatLng from;
  final LatLng to;
  final Duration start;
  final Duration duration;

  const _Glide(this.from, this.to, this.start, this.duration);

  Duration get end => start + duration;

  /// Where the element is at [now], if it still glides towards [target].
  LatLng at(Duration now, LatLng target) {
    if (to != target || now >= end) return target;
    final t = Curves.easeInOut.transform(((now - start).inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0));
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }
}
