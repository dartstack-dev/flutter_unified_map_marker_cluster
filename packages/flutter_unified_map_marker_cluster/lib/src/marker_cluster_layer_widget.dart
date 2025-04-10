import 'package:flutter/widgets.dart';
import 'package:flutter_unified_map/plugin_api.dart';

import 'flutter_map/flutter_map_cluster_bridge.dart';
import 'marker_cluster_layer_options.dart';
import 'native/native_cluster_engine.dart';

/// Clusters [MarkerClusterLayerOptions.markers] on a `UnifiedMap`, like flutter_map_marker_cluster's
/// `MarkerClusterLayerWidget` (same options).
///
/// On the platforms drawn with flutter_map (web, Windows, Linux) it is the real flutter_map_marker_cluster layer.
/// On Android, iOS and macOS the markers are clustered in Dart with the same algorithm and drawn as native markers:
/// clusters split and merge with native animations when the zoom level changes (also during gestures), and a cluster
/// that zooming cannot split spreads its markers around it (spiderfy).
class MarkerClusterLayerWidget extends StatefulWidget {
  /// The markers, the cluster widgets and how the layer behaves.
  final MarkerClusterLayerOptions options;

  const MarkerClusterLayerWidget({super.key, required this.options});

  @override
  State<MarkerClusterLayerWidget> createState() => _MarkerClusterLayerWidgetState();
}

class _MarkerClusterLayerWidgetState extends MapLayerState<MarkerClusterLayerWidget> {
  FlutterMapClusterBridge? _bridge;
  NativeClusterEngine? _engine;

  @override
  void attachHost(MapLayerHost host) {
    if (host.supportsFlutterMapLayers) {
      _bridge ??= FlutterMapClusterBridge(layerId);
    } else {
      (_engine ??= NativeClusterEngine(layerId: layerId, markerId: objectId)).attach(host);
    }
  }

  @override
  void detachHost(MapLayerHost host) => _engine?.detach(host);

  @override
  void sync() {
    final bridge = _bridge;
    if (host.supportsFlutterMapLayers && bridge != null) {
      setFlutterMapLayers([bridge.build(widget.options)]);
    } else {
      _engine?.update(widget.options);
    }
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }
}
