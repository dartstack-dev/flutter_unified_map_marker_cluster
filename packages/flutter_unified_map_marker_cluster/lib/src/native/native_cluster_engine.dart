import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/plugin_api.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show PlatformPolygon;

import '../core/cluster_index.dart';
import '../core/quick_hull.dart';
import '../marker_cluster_layer_options.dart';
import '../node/marker_cluster_node.dart';
import '../node/marker_node.dart';
import '../node/marker_or_cluster_node.dart';
import 'camera_fit.dart';
import 'spider.dart';
import 'transition_planner.dart';

/// The cluster level flutter_map_marker_cluster shows at [zoom]: the zoom rounded up, tolerating platforms that
/// report zoom 5 as 4.9999999 or 5.0000001.
int clusterLevel(double zoom) => (zoom - integerZoomEpsilon).ceil();

/// Clusters on the native maps (Android, iOS, macOS): the markers are clustered in Dart with
/// flutter_map_marker_cluster's algorithm and published as native markers. Splits, merges and spiderfies are native
/// marker transitions.
class NativeClusterEngine {
  /// Most markers published at once. Those on screen come first, then the nearest to the screen.
  static const maxPublished = 1500;

  /// How far (fraction of the viewport) the camera may move during a gesture before the area is clustered again.
  static const _moveThreshold = 0.25;
  static const _moveThrottle = Duration(milliseconds: 150);
  static const _zoomTolerance = 1e-3;

  /// How far past a level's boundary a gesture or an animation must zoom before the level changes, so that a pinch
  /// hovering on an integer zoom does not split and merge the clusters back and forth. A settled camera always shows
  /// the exact level.
  static const levelHysteresis = 0.05;

  /// Most cluster icons rasterised ahead per settled camera, and how many at once.
  static const _prefetchLimit = 48;
  static const _prefetchConcurrency = 4;

  final String layerId;
  final String Function(Key? key, int index) markerId;
  final _clock = clock.stopwatch()..start();
  final _planner = TransitionPlanner();
  late MarkerPublisher _publisher = MarkerPublisher(layerId);

  MapLayerHost? _host;
  MapController? _listenedController;
  StreamSubscription<MapEvent>? _mapEvents;
  MarkerClusterLayerOptions? _options;
  ClusterIndex? _index;

  int? _requestedLevel;
  String? _requestedSpider;
  Duration? _pendingDuration;
  MapCamera? _reclusterCamera;
  bool _capped = false;
  bool _warnedCap = false;
  final _sinceRecluster = clock.stopwatch();
  Timer? _throttle;
  Timer? _legsTimer;
  Timer? _polygonTimer;
  Spider? _spider;
  SpiderTarget? _spiderTarget;
  bool _animatingCamera = false;
  bool _legsPublished = false;
  List<MarkerSpec>? _reportedAgainst;
  final _reported = <String>{};
  bool _polygonShown = false;
  ({ClusterIndex index, int level, MapCamera camera, int iconEpoch})? _prefetched;
  int _prefetchRun = 0;
  bool _disposed = false;

  NativeClusterEngine({required this.layerId, required this.markerId});

  MarkerClusterLayerOptions get _o => _options!;

  void attach(MapLayerHost host) {
    _host = host;
    host.liveCamera.addListener(_onLive);
    host.idleCamera.addListener(_onIdle);
    _listenToMapEvents(host);
  }

  /// Leaves [host], forgetting everything about what is on its map: the layer may move to another map.
  void detach(MapLayerHost host) {
    host.liveCamera.removeListener(_onLive);
    host.idleCamera.removeListener(_onIdle);
    _mapEvents?.cancel();
    _mapEvents = null;
    _listenedController = null;
    _throttle?.cancel();
    _legsTimer?.cancel();
    _polygonTimer?.cancel();
    _publisher.dispose();
    _publisher = MarkerPublisher(layerId);
    _planner.reset();
    _requestedLevel = null;
    _requestedSpider = null;
    _pendingDuration = null;
    _reclusterCamera = null;
    _spider = null;
    _spiderTarget = null;
    _animatingCamera = false;
    _legsPublished = false;
    _reportedAgainst = null;
    _reported.clear();
    _polygonShown = false;
    _prefetched = null;
    _prefetchRun++;
    _host = null;
  }

  void update(MarkerClusterLayerOptions options) {
    _options = options;
    final host = _host;
    if (host == null) return;
    _listenToMapEvents(host);
    if (host.isReady) _recluster(host.camera);
  }

  void dispose() {
    _disposed = true;
    _mapEvents?.cancel();
    _throttle?.cancel();
    _legsTimer?.cancel();
    _polygonTimer?.cancel();
    _publisher.dispose();
  }

  void _onLive() {
    final host = _host;
    if (host == null || _options == null) return;
    final camera = host.liveCamera.value;
    final spider = _spider;
    if (spider != null && (camera.zoom - spider.zoom).abs() > _zoomTolerance) _closeSpider();
    final level = _liveLevel(camera);
    if (level != _requestedLevel || _spider?.clusterId != _requestedSpider) {
      _recluster(camera, level: level);
    } else if (_movedFar(camera)) {
      _throttledRecluster();
    }
  }

  void _onIdle() {
    final host = _host;
    final camera = host?.idleCamera.value;
    if (host == null || camera == null || _options == null) return;
    if (!_coversAlready(camera)) _recluster(camera);
    _prefetchNeighbours(camera);
    final target = _spiderTarget;
    _spiderTarget = null;
    if (target != null && target.reachedBy(camera)) _spiderfy(target.clusterId, camera);
  }

  /// Whether the generation last made already shows what [camera] needs: the same tree, level and spider, nothing
  /// left out by the cap, and an area that still has a margin around [camera]'s view.
  bool _coversAlready(MapCamera camera) {
    final last = _reclusterCamera;
    return last != null &&
        !_capped &&
        identical(_index, _o.markers.isEmpty ? null : _ensureIndex(camera)) &&
        _levelOf(camera) == _requestedLevel &&
        _spider?.clusterId == _requestedSpider &&
        last.rotation == camera.rotation &&
        !_movedFar(camera);
  }

  /// Map taps close the spider; long presses do not (the layer hit tester would see both).
  void _listenToMapEvents(MapLayerHost host) {
    final controller = host.controller;
    if (identical(controller, _listenedController)) return;
    _mapEvents?.cancel();
    _listenedController = controller;
    _mapEvents = controller.mapEventStream.listen((event) {
      if (event is! MapEventTap) return;
      _spiderTarget = null;
      final host = _host;
      if (_spider == null || host == null || _disposed) return;
      _closeSpider();
      _recluster(host.camera);
    });
  }

  int _levelOf(MapCamera camera) => math.max(clusterLevel(camera.zoom), _index?.config.minZoom ?? 1);

  /// The level to show during a gesture or an animation: [_levelOf], unless the zoom is still within
  /// [levelHysteresis] of the boundary of the level on the map.
  int _liveLevel(MapCamera camera) {
    final level = _levelOf(camera);
    final current = _requestedLevel;
    if (current == null || level == current) return level;
    final zoom = camera.zoom;
    final held = level > current ? zoom <= current + levelHysteresis : zoom >= current - 1 - levelHysteresis;
    return held ? current : level;
  }

  bool _movedFar(MapCamera camera) {
    final last = _reclusterCamera;
    return last == null || last.nonRotatedSize != camera.nonRotatedSize || _movedFarFrom(last, camera);
  }

  static bool _movedFarFrom(MapCamera last, MapCamera camera) {
    final delta = camera.projectAtZoom(camera.center) - camera.projectAtZoom(last.center);
    final size = camera.nonRotatedSize;
    return delta.dx.abs() > size.width * _moveThreshold || delta.dy.abs() > size.height * _moveThreshold;
  }

  void _throttledRecluster() {
    if (_throttle?.isActive ?? false) return;
    void recluster() {
      final camera = _host!.liveCamera.value;
      _recluster(camera, level: _liveLevel(camera));
    }

    final wait = _moveThrottle - _sinceRecluster.elapsed;
    if (wait <= Duration.zero) {
      recluster();
      return;
    }
    _throttle = Timer(wait, () {
      if (!_disposed && _host != null) recluster();
    });
  }

  /// The cluster tree of the current markers. Kept when the markers have the same keys and points as the ones it was
  /// built from (a parent rebuilding them, for example), built again otherwise.
  ClusterIndex? _ensureIndex(MapCamera camera) {
    final o = _o;
    final config = ClusterConfig(
      minZoom: camera.minZoom?.ceil() ?? 1,
      maxZoom: camera.maxZoom?.floor() ?? 20,
      maxClusterRadius: o.maxClusterRadius,
      disableClusteringAtZoom: o.disableClusteringAtZoom,
      alignment: o.alignment,
      size: o.size,
    );
    final markers = o.markers;
    final index = _index;
    if (index != null && config == index.config && index.adopt(markers)) return index;
    // Ids only depend on the markers' keys and the configuration, so what is on the map, the spider and the
    // transitions in progress carry over to the new index.
    final rebuilt = markers.isEmpty
        ? null
        : ClusterIndex.build(
            markers: markers,
            config: config,
            computeSize: o.computeSize,
            markerId: (marker, index) => markerId(marker.key, index),
            clusterIdPrefix: '$layerId/c',
          );
    _spider = _spider?.within(rebuilt);
    return _index = rebuilt;
  }

  void _recluster(MapCamera camera, {int? level}) {
    final host = _host;
    // A map without a size shows nothing: keep what is published until it has one.
    if (host == null || _disposed || camera.nonRotatedSize.isEmpty) return;
    _throttle?.cancel();
    final index = _ensureIndex(camera);
    final o = _o;
    final shown = level ?? _levelOf(camera);
    var elements = index == null
        ? const <MarkerOrClusterNode>[]
        : [for (final area in _areas(camera)) ...index.visible(shown, area)];
    final budget = math.max(0, maxPublished - (_spider?.positions.length ?? 0));
    _capped = elements.length > budget;
    if (_capped) elements = _onScreenFirst(camera, elements, budget);

    var spider = _spider;
    if (spider != null && (spider.level != shown || !elements.any((e) => identical(e, spider!.cluster)))) {
      _closeSpider();
      spider = null;
    }

    final specs = <MarkerSpec>[];
    for (final element in elements) {
      final id = index!.idOf(element);
      if (element is MarkerNode) {
        specs.add(_markerSpec(element, id, element.point));
      } else if (element is MarkerClusterNode) {
        if (identical(element, spider?.cluster)) {
          specs.add(_clusterSpec(element, id: id, faded: true));
          for (final leaf in element.markers) {
            final leafId = index.idOf(leaf);
            specs.add(_markerSpec(leaf, leafId, spider!.positions[leafId]!, zIndex: 0.6));
          }
        } else {
          specs.add(_clusterSpec(element, id: id));
        }
      }
    }

    final levelChanged = _requestedLevel != null && shown != _requestedLevel;
    final spiderChanged = spider?.clusterId != _requestedSpider;
    var duration = levelChanged
        ? o.animationsOptions.zoom
        : spiderChanged
        ? o.animationsOptions.spiderfy
        : null;
    if (duration == null && _publisher.hasPending) duration = _pendingDuration;
    if (duration == Duration.zero) duration = null;
    final now = _clock.elapsed;
    final published = _publisher.published;
    final plan = index == null ? null : _planner.plan(index, published, specs, now);
    final transition = duration == null || plan == null
        ? null
        : MarkerTransition(duration: duration, appearFrom: plan.appearFrom, disappearTo: plan.disappearTo);
    if (plan != null) _planner.track(published, specs, transition, now);

    _requestedLevel = shown;
    _requestedSpider = spider?.clusterId;
    _reclusterCamera = camera;
    _sinceRecluster
      ..reset()
      ..start();
    _pendingDuration = duration;
    final legStyle = o.spiderLegs;
    final legs = spider != null && spider.legs && legStyle != null ? spider.legsWith(legStyle) : null;
    _publisher.publish(
      host,
      specs,
      onTap: index == null ? null : (id) => _onTap(index, id),
      transition: transition,
      // Legs are cleared until a generation without them was applied: one superseded while waiting for its icons
      // would leave them on the map.
      polylines: legs ?? (_legsPublished ? const [] : null),
    );
    _legsPublished = legs != null || (_legsPublished && _publisher.hasPending);
    if (!_publisher.hasPending) _pendingDuration = null;
    if (plan != null) _reportClustered(index!, published, plan.clustered);
  }

  /// Calls `onMarkersClustered` once per marker joining a cluster, although a generation still waiting for its icons
  /// is computed again from the same markers on the map.
  void _reportClustered(ClusterIndex index, List<MarkerSpec> published, Map<String, List<String>> clustered) {
    if (!identical(published, _reportedAgainst)) {
      _reportedAgainst = published;
      _reported.clear();
    }
    final onMarkersClustered = _o.onMarkersClustered;
    if (onMarkersClustered == null) return;
    for (final ids in clustered.values) {
      final markers = [
        for (final id in ids)
          if (_reported.add(id)) (index.nodes[id]! as MarkerNode).marker,
      ];
      if (markers.isNotEmpty) onMarkersClustered(markers);
    }
  }

  /// The viewport grown by [margin] viewports on each side (one by default, so that panning never reveals an area
  /// without markers). Native maps repeat the world: beyond the antimeridian the area continues on the other side.
  static List<LatLngBounds> _areas(MapCamera camera, {double margin = 1}) {
    final size = camera.nonRotatedSize;
    if (size.isEmpty) return const [];
    final w = size.width;
    final h = size.height;
    final low = Offset(-margin * w, -margin * h);
    final high = Offset((1 + margin) * w, (1 + margin) * h);
    final corners = [
      for (final corner in [low, Offset(high.dx, low.dy), Offset(low.dx, high.dy), high])
        camera.screenOffsetToLatLng(corner),
    ];
    // The corners' longitudes continue across the antimeridian (the camera unrolls the world), so the span is
    // taken directly instead of through `LatLngBounds.fromPoints`, which rejects longitudes beyond ±180.
    final north = math.min(corners.map((c) => c.latitude).reduce(math.max), 90.0);
    final south = math.max(corners.map((c) => c.latitude).reduce(math.min), -90.0);
    final west = corners.map((c) => c.longitude).reduce(math.min);
    final east = corners.map((c) => c.longitude).reduce(math.max);
    LatLngBounds part(double west, double east) =>
        LatLngBounds.unsafe(north: north, south: south, east: east, west: west);
    if (east - west >= 360) return [part(-180, 180)];
    return [
      if (math.min(east, 180) > math.max(west, -180)) part(math.max(west, -180), math.min(east, 180)),
      if (west < -180) part(west + 360, 180),
      if (east > 180) part(-180, east - 360),
    ];
  }

  /// How far a node is outside [camera]'s (rotated) viewport, then how far from its center, both squared in screen
  /// pixels; longitudes are measured the short way round.
  static (double, double) Function(MarkerOrClusterNode node) _screenDistance(MapCamera camera) {
    final center = camera.projectAtZoom(camera.center);
    final world = camera.projectAtZoom(const LatLng(0, 180)).dx - camera.projectAtZoom(const LatLng(0, -180)).dx;
    final halfWidth = camera.nonRotatedSize.width / 2;
    final halfHeight = camera.nonRotatedSize.height / 2;
    final rad = camera.rotationRad;
    return (node) {
      final offset = camera.projectAtZoom(node.position) - center;
      var dx = offset.dx % world;
      if (dx > world / 2) dx -= world;
      final screen = rotatePoint(Offset(dx, offset.dy), rad);
      final outX = math.max(screen.dx.abs() - halfWidth, 0.0);
      final outY = math.max(screen.dy.abs() - halfHeight, 0.0);
      return (outX * outX + outY * outY, screen.distanceSquared);
    };
  }

  /// The [budget] elements to publish out of too many: those on screen first, then the nearest to the screen.
  List<MarkerOrClusterNode> _onScreenFirst(MapCamera camera, List<MarkerOrClusterNode> elements, int budget) {
    final distance = _screenDistance(camera);
    final ranked = [for (final e in elements) (e, distance(e))]
      ..sort((a, b) {
        final outside = a.$2.$1.compareTo(b.$2.$1);
        return outside != 0 ? outside : a.$2.$2.compareTo(b.$2.$2);
      });
    assert(() {
      if (!_warnedCap && budget < ranked.length && ranked[budget].$2.$1 == 0) {
        _warnedCap = true;
        debugPrint(
          'MarkerClusterLayerWidget: more than $budget markers and clusters on screen; those farthest from the '
          'center are not shown. Cluster more (maxClusterRadius, disableClusteringAtZoom).',
        );
      }
      return true;
    }());
    return [for (final (e, _) in ranked.take(budget)) e];
  }

  MarkerSpec _markerSpec(MarkerNode node, String id, LatLng position, {double zIndex = 0}) => MarkerSpec(
    id: id,
    position: position,
    iconKey: node.marker.effectiveIconKey,
    child: node.marker.child,
    size: Size(node.width, node.height),
    alignment: node.alignment ?? Alignment.center,
    rotate: node.rotate == true || _o.rotate == true,
    zIndex: zIndex,
  );

  /// The marker of [cluster] (with an empty [id] when only its icon is needed).
  MarkerSpec _clusterSpec(MarkerClusterNode cluster, {String id = '', bool faded = false}) {
    final o = _o;
    final markers = cluster.mapMarkers;
    final builder = o.builder;
    final key = o.clusterIconKey?.call(markers) ?? markers.length;
    final Widget child = Builder(builder: (context) => builder(context, markers));
    return MarkerSpec(
      id: id,
      position: cluster.position,
      iconKey: (faded ? #spiderfied : #cluster, layerId, key),
      // A spiderfied cluster stays under its markers, almost faded out like flutter_map_marker_cluster's.
      child: faded ? Opacity(opacity: 0.3, child: child) : child,
      size: cluster.size(),
      alignment: o.alignment ?? Alignment.center,
      rotate: o.rotate == true,
      zIndex: faded ? 0.5 : 0,
    );
  }

  /// Rasterises ahead the on-screen clusters of the levels around [camera]'s, nearest the center first and a few at
  /// a time, so a zoom step does not wait for them. A newer settled camera supersedes the run.
  void _prefetchNeighbours(MapCamera camera) {
    final host = _host;
    final index = _index;
    if (host == null || index == null || camera.nonRotatedSize.isEmpty) return;
    final level = _levelOf(camera);
    final previous = _prefetched;
    if (previous != null &&
        identical(previous.index, index) &&
        previous.level == level &&
        previous.iconEpoch == host.icons.epoch &&
        previous.camera.nonRotatedSize == camera.nonRotatedSize &&
        previous.camera.rotation == camera.rotation &&
        !_movedFarFrom(previous.camera, camera)) {
      return;
    }
    _prefetched = (index: index, level: level, camera: camera, iconEpoch: host.icons.epoch);
    final distance = _screenDistance(camera);
    final clusters = <(MarkerClusterNode, double)>[];
    for (final neighbour in [level - 1, level + 1]) {
      if (neighbour < index.config.minZoom) continue;
      for (final area in _areas(camera, margin: 0)) {
        for (final element in index.visible(neighbour, area)) {
          if (element is MarkerClusterNode) clusters.add((element, distance(element).$2));
        }
      }
    }
    clusters.sort((a, b) => a.$2.compareTo(b.$2));
    final specs = [for (final (cluster, _) in clusters.take(_prefetchLimit)) _clusterSpec(cluster)];
    final run = ++_prefetchRun;
    final publisher = _publisher;
    unawaited(() async {
      for (var i = 0; i < specs.length; i += _prefetchConcurrency) {
        if (_disposed || run != _prefetchRun || !identical(publisher, _publisher)) return;
        await publisher.prepare(host, specs.sublist(i, math.min(i + _prefetchConcurrency, specs.length)));
      }
    }());
  }

  /// A tap on a marker of the generation built from [index]: ids are resolved against the tree that generation came
  /// from, which may not be the newest one yet.
  void _onTap(ClusterIndex index, String id) {
    final node = index.nodes[id];
    if (node is MarkerNode) {
      _onMarkerTap(node.marker);
    } else if (node is MarkerClusterNode) {
      _onClusterTap(index, node);
    }
  }

  void _onMarkerTap(Marker marker) {
    final host = _host;
    if (_animatingCamera || host == null) return;
    final o = _o;
    if (!o.markerChildBehavior) o.onMarkerTap?.call(marker);
    marker.onTap?.call();
    if (o.markerChildBehavior || !o.centerMarkerOnClick) return;
    _animate(
      host,
      host.controller.animateTo(
        dest: marker.point,
        duration: o.animationsOptions.centerMarker,
        curve: o.animationsOptions.centerMarkerCurves,
      ),
    );
  }

  void _onClusterTap(ClusterIndex index, MarkerClusterNode cluster) {
    final host = _host;
    if (_animatingCamera || host == null) return;
    final o = _o;
    final clusterId = index.idOf(cluster);
    _spiderTarget = null;
    o.onClusterTap?.call(cluster);
    final camera = host.camera;
    final isSpiderfied = _spider?.clusterId == clusterId;

    if (!o.zoomToBoundsOnClick) {
      if (!o.spiderfyCluster) return;
      _closeSpider();
      if (isSpiderfied) {
        _recluster(camera);
      } else {
        _spiderfy(clusterId, camera);
      }
      return;
    }

    final level = _levelOf(camera);
    final fit = fitBounds(
      camera,
      cluster.bounds,
      padding: o.padding,
      maxZoom: o.maxZoom,
      forceIntegerZoomLevel: o.forceIntegerZoomLevel,
    );
    final first = cluster.markers.first;
    // flutter_map_marker_cluster's rule, plus markers that share one point: zooming can never separate those.
    final cannotDivide =
        cluster.markers.every((m) => m.parent!.zoom == index.config.maxZoom && identical(m.parent, first.parent)) ||
        cluster.markers.every((m) => m.point == first.point) ||
        (fit.zoom == level && level == o.maxZoom);

    if (cannotDivide && _spider != null) {
      _closeSpider();
      if (isSpiderfied) {
        _recluster(camera);
        return;
      }
    }
    if (!cannotDivide && fit.zoom > level) _showPolygon(cluster);

    final dest = cannotDivide
        ? fitBounds(camera, cluster.bounds, padding: o.padding, zoom: camera.zoom)
        : (center: fit.center, zoom: fit.zoom);
    final alreadyFit = _same(dest.center, camera.center) && (dest.zoom - camera.zoom).abs() < 1e-9;
    if (alreadyFit) {
      if (cannotDivide && o.spiderfyCluster) {
        _spiderfy(clusterId, camera);
      } else {
        _recluster(camera);
      }
      return;
    }
    if (cannotDivide) _recluster(camera);
    _animate(
      host,
      host.controller.animateTo(
        dest: dest.center,
        zoom: dest.zoom,
        duration: o.animationsOptions.fitBound,
        curve: o.animationsOptions.fitBoundCurves,
      ),
      then: () {
        _hidePolygonLater();
        if (!cannotDivide || !_o.spiderfyCluster) return;
        // The platform may report the final camera after the move completes: the spider opens on the idle camera
        // that reached the target, and not at all when the user took the camera elsewhere.
        final target = SpiderTarget(clusterId, dest.center, dest.zoom);
        final idle = host.idleCamera.value;
        if (idle != null && target.reachedBy(idle)) {
          _spiderfy(clusterId, idle);
        } else {
          _spiderTarget = target;
        }
      },
    );
  }

  /// Ignores taps while the camera moves for one; [then] runs once it stopped, if the layer is still on [host].
  void _animate(MapLayerHost host, Future<void> animation, {VoidCallback? then}) {
    _animatingCamera = true;
    unawaited(
      animation.catchError((Object _) {}).whenComplete(() {
        if (_disposed || !identical(_host, host)) return;
        _animatingCamera = false;
        then?.call();
      }),
    );
  }

  /// Opens the spider of the cluster [clusterId] of the newest tree, if it still has one.
  void _spiderfy(String clusterId, MapCamera camera) {
    final index = _index;
    final cluster = index?.nodes[clusterId];
    if (index == null || cluster is! MarkerClusterNode) return;
    _spider = Spider.open(index: index, cluster: cluster, level: _levelOf(camera), camera: camera, options: _o);
    _recluster(camera);
    _legsTimer?.cancel();
    _legsTimer = Timer(_o.animationsOptions.spiderfy, () {
      final spider = _spider;
      final host = _host;
      if (_disposed || host == null || spider == null || spider.clusterId != clusterId) return;
      spider.legs = true;
      _recluster(host.camera);
    });
  }

  void _closeSpider() {
    if (_spider == null) return;
    _spider = null;
    _legsTimer?.cancel();
  }

  void _showPolygon(MarkerClusterNode cluster) {
    final host = _host;
    final o = _o;
    if (host == null || !o.showPolygon) return;
    final hull = QuickHull.getConvexHull([for (final marker in cluster.markers) marker.point]);
    if (hull.length < 3) return;
    final style = o.polygonOptions;
    _polygonTimer?.cancel();
    _polygonShown = true;
    host.registry.setPolygons(layerId, [
      PlatformPolygon(
        id: '$layerId/hull',
        points: hull,
        fillColor: style.color,
        strokeColor: style.borderColor,
        strokeWidth: style.borderStrokeWidth,
        zIndex: host.registry.shapeZIndexOf(layerId, 0, 1),
      ),
    ]);
  }

  void _hidePolygonLater() {
    if (!_polygonShown) return;
    _polygonTimer?.cancel();
    _polygonTimer = Timer(_o.animationsOptions.zoom, () {
      _polygonShown = false;
      _host?.registry.setPolygons(layerId, const []);
    });
  }

  static bool _same(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-9 && (a.longitude - b.longitude).abs() < 1e-9;
}
