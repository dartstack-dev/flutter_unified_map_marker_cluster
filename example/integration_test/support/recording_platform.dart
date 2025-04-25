import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/widgets.dart' show Widget;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart';

@immutable
class RecordedMove {
  final int viewId;
  final PlatformCameraUpdate update;
  final Duration? animation;

  const RecordedMove(this.viewId, this.update, this.animation);

  @override
  String toString() => 'RecordedMove($viewId, $update, $animation)';
}

/// Passes every call through to [delegate] (the platform registered by the plugin, or any implementation) and
/// records what the core sent and what the platform reported, so tests can assert what reached the native side.
class RecordingPlatform extends UnifiedMapsPlatform with MockPlatformInterfaceMixin {
  RecordingPlatform(this.delegate);

  final UnifiedMapsPlatform delegate;

  final builtViews = <int, PlatformMapOptions>{};
  final markerUpdates = <MapObjectUpdates<PlatformMarker>>[];
  final polylineUpdates = <MapObjectUpdates<PlatformPolyline>>[];
  final markerTransitions = <PlatformMarkerTransition?>[];

  /// When each entry of [markerUpdates] was sent, and when the platform reported it applied (null while in flight).
  final markerUpdateSent = <Duration>[];
  final markerUpdateApplied = <Duration?>[];
  final clock = Stopwatch()..start();
  final cameraMoves = <RecordedMove>[];
  final receivedEvents = <PlatformMapEvent>[];

  final markers = <String, PlatformMarker>{};
  final polylines = <String, PlatformPolyline>{};
  final polygons = <String, PlatformPolygon>{};

  final _eventsController = StreamController<PlatformMapEvent>.broadcast(sync: true);
  final _injected = StreamController<PlatformMapEvent>.broadcast(sync: true);

  /// Every platform event, as the core receives it.
  Stream<PlatformMapEvent> get onEvent => _eventsController.stream;

  /// Sends [event] to the core as if the native map had emitted it (synthetic taps do not reach UIKit and AppKit
  /// platform views, so tests tap markers this way there).
  void inject(PlatformMapEvent event) => _injected.add(event);

  @override
  Widget buildView({
    required int viewId,
    required PlatformMapOptions options,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    builtViews[viewId] = options;
    return delegate.buildView(viewId: viewId, options: options, gestureRecognizers: gestureRecognizers);
  }

  @override
  Future<void> dispose(int viewId) => delegate.dispose(viewId);

  @override
  Future<void> updateOptions(int viewId, PlatformMapOptions options) => delegate.updateOptions(viewId, options);

  @override
  Future<void> updateMarkers(
    int viewId,
    MapObjectUpdates<PlatformMarker> updates, {
    PlatformMarkerTransition? transition,
  }) {
    final index = markerUpdates.length;
    markerUpdates.add(updates);
    markerTransitions.add(transition);
    markerUpdateSent.add(clock.elapsed);
    markerUpdateApplied.add(null);
    _apply(markers, updates);
    return delegate.updateMarkers(viewId, updates, transition: transition).then((_) {
      markerUpdateApplied[index] = clock.elapsed;
    });
  }

  /// Every marker update that added, changed or removed [id], with its timing and transition hints.
  String historyOf(String id) {
    final lines = <String>[];
    for (final (i, updates) in markerUpdates.indexed) {
      final String? kind = updates.added.any((m) => m.id == id)
          ? 'added'
          : updates.changed.any((m) => m.id == id)
          ? 'changed'
          : updates.removedIds.contains(id)
          ? 'removed'
          : null;
      if (kind == null) continue;
      final transition = markerTransitions[i];
      final hint = transition == null
          ? 'no transition'
          : '${transition.duration.inMilliseconds} ms, appearFrom ${transition.appearFrom[id]}, '
                'disappearTo ${transition.disappearTo[id]}';
      lines.add(
        '#$i $kind at ${markerUpdateSent[i].inMilliseconds} ms (applied ${markerUpdateApplied[i]?.inMilliseconds}), '
        '$hint',
      );
    }
    return '$id: ${lines.join('; ')}';
  }

  @override
  Future<void> updatePolylines(int viewId, MapObjectUpdates<PlatformPolyline> updates) {
    polylineUpdates.add(updates);
    _apply(polylines, updates);
    return delegate.updatePolylines(viewId, updates);
  }

  @override
  Future<void> updatePolygons(int viewId, MapObjectUpdates<PlatformPolygon> updates) {
    _apply(polygons, updates);
    return delegate.updatePolygons(viewId, updates);
  }

  @override
  Future<void> updateCircles(int viewId, MapObjectUpdates<PlatformCircle> updates) =>
      delegate.updateCircles(viewId, updates);

  @override
  Future<void> updateTileLayers(int viewId, MapObjectUpdates<PlatformTileLayer> updates) =>
      delegate.updateTileLayers(viewId, updates);

  @override
  Future<void> moveCamera(int viewId, PlatformCameraUpdate update, {Duration? animation}) {
    cameraMoves.add(RecordedMove(viewId, update, animation));
    return delegate.moveCamera(viewId, update, animation: animation);
  }

  @override
  Future<PlatformCamera> getCamera(int viewId) => delegate.getCamera(viewId);

  @override
  Future<PlatformLatLngBounds> getVisibleRegion(int viewId) => delegate.getVisibleRegion(viewId);

  @override
  Future<Offset> toScreen(int viewId, LatLng position) => delegate.toScreen(viewId, position);

  @override
  Future<LatLng> toLatLng(int viewId, Offset screenPoint) => delegate.toLatLng(viewId, screenPoint);

  @override
  Future<Uint8List?> takeSnapshot(int viewId) => delegate.takeSnapshot(viewId);

  @override
  bool get supportsFlutterMapLayers => delegate.supportsFlutterMapLayers;

  @override
  void setFlutterMapLayers(int viewId, List<Widget> layers) => delegate.setFlutterMapLayers(viewId, layers);

  @override
  Stream<PlatformMapEvent> events(int viewId) {
    final merged = StreamController<PlatformMapEvent>.broadcast(sync: true);
    void forward(PlatformMapEvent event) {
      receivedEvents.add(event);
      _eventsController.add(event);
      merged.add(event);
    }

    final subscriptions = [
      delegate.events(viewId).listen(forward, onError: merged.addError),
      _injected.stream.where((event) => event.viewId == viewId).listen(forward),
    ];
    merged.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return merged.stream;
  }

  static void _apply<T extends PlatformMapObject>(Map<String, T> store, MapObjectUpdates<T> updates) {
    for (final id in updates.removedIds) {
      store.remove(id);
    }
    for (final object in [...updates.added, ...updates.changed]) {
      store[object.id] = object;
    }
  }
}
