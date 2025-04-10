import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart' hide Offset;
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    as platform
    show Offset;

class MoveCameraCall {
  final int viewId;
  final PlatformCameraUpdate update;
  final Duration? animation;

  const MoveCameraCall(this.viewId, this.update, this.animation);
}

/// Records every call and lets tests emit platform events.
class FakeUnifiedMapsPlatform extends UnifiedMapsPlatform with MockPlatformInterfaceMixin {
  final builtViews = <int, PlatformMapOptions>{};
  final markerUpdates = <MapObjectUpdates<PlatformMarker>>[];

  /// The transition passed with each entry of [markerUpdates].
  final markerTransitions = <PlatformMarkerTransition?>[];
  final polylineUpdates = <MapObjectUpdates<PlatformPolyline>>[];
  final polygonUpdates = <MapObjectUpdates<PlatformPolygon>>[];
  final cameraMoves = <MoveCameraCall>[];

  /// Answer of [supportsFlutterMapLayers], like the flutter_map backend when true.
  bool flutterMapLayersSupported = false;

  /// When set, each marker update waits for it before it is applied, like a native side registering icons first.
  Future<void> Function()? markerUpdateGate;

  /// When set, each camera move completes only once it completes, like a native camera animation.
  Future<void> Function()? moveCameraGate;

  /// Marker updates started and not yet applied, and the most that were ever in flight together.
  int markerUpdatesInFlight = 0;
  int maxMarkerUpdatesInFlight = 0;

  final markers = <String, PlatformMarker>{};
  final polylines = <String, PlatformPolyline>{};
  final polygons = <String, PlatformPolygon>{};

  final _controllers = <int, StreamController<PlatformMapEvent>>{};

  int get lastViewId => builtViews.keys.last;

  @override
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    builtViews[viewId] = options;
    return const SizedBox.expand(key: ValueKey('fake-map'));
  }

  @override
  Stream<PlatformMapEvent> events(int viewId) => _controller(viewId).stream;

  StreamController<PlatformMapEvent> _controller(int viewId) =>
      _controllers.putIfAbsent(viewId, () => StreamController<PlatformMapEvent>.broadcast(sync: true));

  void emit(PlatformMapEvent event) => _controller(event.viewId).add(event);

  void ready({PlatformCamera camera = const PlatformCamera(center: LatLng(0, 0), zoom: 2), int? viewId}) =>
      emit(PlatformMapReadyEvent(viewId ?? lastViewId, camera));

  void moveTo(PlatformCamera camera, {bool byGesture = true}) {
    emit(PlatformCameraMoveStartedEvent(lastViewId, byGesture: byGesture));
    emit(PlatformCameraMoveEvent(lastViewId, camera));
    emit(PlatformCameraIdleEvent(lastViewId, camera));
  }

  void tap(LatLng position, Offset point) =>
      emit(PlatformMapTapEvent(lastViewId, position, platform.Offset(point.dx, point.dy)));

  void longPress(LatLng position, Offset point) =>
      emit(PlatformMapLongPressEvent(lastViewId, position, platform.Offset(point.dx, point.dy)));

  void tapMarker(String id) => emit(PlatformMarkerTapEvent(lastViewId, id));

  @override
  Future<void> dispose(int viewId) async {
    await _controllers.remove(viewId)?.close();
  }

  @override
  Future<void> updateOptions(int viewId, PlatformMapOptions options) async {}

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) async {
    markerUpdatesInFlight++;
    if (markerUpdatesInFlight > maxMarkerUpdatesInFlight) maxMarkerUpdatesInFlight = markerUpdatesInFlight;
    try {
      await markerUpdateGate?.call();
      markerUpdates.add(updates);
      markerTransitions.add(transition);
      _apply(markers, updates);
    } finally {
      markerUpdatesInFlight--;
    }
  }

  @override
  bool get supportsFlutterMapLayers => flutterMapLayersSupported;

  @override
  void setFlutterMapLayers(int viewId, List<Widget> layers) {
    if (!flutterMapLayersSupported) throw StateError('setFlutterMapLayers called on a native platform');
  }

  @override
  Future<void> updatePolylines(int viewId, MapObjectUpdates<PlatformPolyline> updates) async {
    polylineUpdates.add(updates);
    _apply(polylines, updates);
  }

  @override
  Future<void> updatePolygons(int viewId, MapObjectUpdates<PlatformPolygon> updates) async {
    polygonUpdates.add(updates);
    _apply(polygons, updates);
  }

  @override
  Future<void> updateCircles(int viewId, MapObjectUpdates<PlatformCircle> updates) async {}

  @override
  Future<void> updateTileLayers(int viewId, MapObjectUpdates<PlatformTileLayer> updates) async {}

  @override
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) async {
    cameraMoves.add(MoveCameraCall(viewId, update, animation));
    await moveCameraGate?.call();
  }

  void _apply<T extends PlatformMapObject>(Map<String, T> target, MapObjectUpdates<T> updates) {
    for (final id in updates.removedIds) {
      target.remove(id);
    }
    for (final object in [...updates.added, ...updates.changed]) {
      target[object.id] = object;
    }
  }
}
