# flutter_unified_map_marker_cluster — agent context

Marker clustering for `flutter_unified_map` (sibling repo `~/Documents/Code/AlphaByte/flutter_unified_map`) with the
public API of flutter_map_marker_cluster 8.2.2 (`~/.pub-cache/hosted/pub.dev/flutter_map_marker_cluster-8.2.2`).
Built only on `package:flutter_unified_map/plugin_api.dart`; never change the core from here.

## Layout

| Path | Role |
|---|---|
| `packages/flutter_unified_map_marker_cluster/lib/src/marker_cluster_layer_widget.dart` | The layer (`MapLayerState`): picks the flutter_map bridge or the native engine from `host.supportsFlutterMapLayers` |
| `.../src/marker_cluster_layer_options.dart` | Options, `AnimationsOptions`, `PolygonOptions` (flutter_map_marker_cluster's fields and defaults + `clusterIconKey`) |
| `.../src/flutter_map/flutter_map_cluster_bridge.dart` | Web/Windows/Linux: builds the real `fmmc.MarkerClusterLayerWidget` (converted markers cached per source list, callbacks mapped back with Expandos) and hands it to `setFlutterMapLayers` |
| `.../src/native/native_cluster_engine.dart` | Android/iOS/macOS: recluster triggers, query area and cap, taps, hull, icon prefetch; wires the two below |
| `.../src/native/transition_planner.dart` | `TransitionPlanner`: `appearFrom` / `disappearTo` / clustered ids of a new generation, and the glides it planned (unit-tested on plain data) |
| `.../src/native/spider.dart` | `Spider` (layout, carried over to a rebuilt tree, legs) and `SpiderTarget` (arrival check) |
| `.../src/core/` | Ports of flutter_map_marker_cluster (BSD-3, notice in LICENSE): `ClusterIndex` (ClusterManager), `DistanceGrid`, `Spiderfy`, `QuickHull`. Keep them identical to upstream: `test/flutter_map_backend_test.dart` compares the clusters with the real package |
| `.../src/node/` | Public `MarkerClusterNode`, `MarkerNode` (implements `Marker`), `MarkerOrClusterNode`; cluster data (markers, bounds, size) is computed lazily and invalidated up the tree |
| `example/` | Demo (pins, spiderfy, durations sheet) and `integration_test/` (see README) |

## Native behaviour (decided with Clovis, Oct 7 2026)

- Cluster level = `max((zoom - 1e-6).ceil(), tree minZoom)` (`_levelOf`; flutter_map_marker_cluster uses
  `zoom.ceil()`; the epsilon absorbs MapKit's 4.9999999). During gestures and animations (`liveCamera`) the level
  changes only 0.05 past its boundary (`_liveLevel`); a settled camera shows the exact level. Tree levels:
  `camera.minZoom?.ceil() ?? 1` to `camera.maxZoom?.floor() ?? 20`; clusters only up to `disableClusteringAtZoom`.
- Recluster: on `idleCamera` unless the last generation covers it (`_coversAlready`); on `liveCamera` immediately
  when the level or the spider changes, throttled (150 ms) when a gesture moved more than 25 % of the viewport.
  Area = viewport ± one viewport, split in two across the antimeridian, cap 1500 including spider leaves: on-screen
  elements first (rotated viewport), then by distance to the screen (longitude the short way round). An empty map
  size publishes nothing.
- Tree: `ClusterIndex.adopt` keeps it when a new list has the same keys and points (swaps the markers, invalidates
  the lazy cluster data); otherwise rebuilt. Non-finite coordinates are skipped and reported (bridge too); duplicate
  keys assert.
- Transition rule (`TransitionPlanner.plan`), relative to `MarkerPublisher.published` (what is on the map, not the last request): a new
  id whose closest ancestor is on the map appears from it; a leaving id whose closest ancestor is in the new
  generation disappears into it; ids in both keep their position. Animated only when the level changed
  (`animationsOptions.zoom`) or the spider changed (`animationsOptions.spiderfy`), or to keep the duration of a
  generation still waiting for its icons. `published` may not have reached the platform yet (the registry merges the
  generations set before a push) or still be gliding: `_arriving` estimates where a container is on screen (ease-in-
  out over the transition, on the engine's `clock` stopwatch, which `testWidgets` fakes), and ids in `_leaving` are
  re-targeted to the new element that contains them.
- Ids are content-derived: cluster `<layerId>/c<zoom>:<first marker id without the layer id>` (a marker is in one
  cluster per level). An index rebuilt from equivalent markers keeps every id, so nothing is re-sent, the spider is
  carried over (`_Spider.within`) and transitions continue. `ClusterConfig` leaves `computeSize` out, like upstream.
- Taps are resolved against the `ClusterIndex` of the generation that registered the handler (the one on the map),
  not the newest tree.
- Cluster tap: flutter_map_marker_cluster's `cannotDivide` rule plus "all markers on one point"; cannot divide →
  center at the current zoom then spiderfy once an idle camera is within 8 px / 0.01 zoom of the target (the move
  future can complete before the platform's last camera events, and an interrupted move completes normally), looked
  up again by cluster id; otherwise `animateTo` the `fitBounds` result (port of flutter_map's
  `FitBounds.fit`, in `native/camera_fit.dart`) with `fitBound`, hull shown until `animationsOptions.zoom` after.
- Spider: positions computed in unrotated screen pixels like upstream; faded cluster (opacity 0.3, its own bitmap
  key), leaves at z 0.6, legs (`spiderLegs`, null = none) published with the generation after
  `animationsOptions.spiderfy`; polylines are only sent while legs are or were drawn. Closed by a map tap
  (`MapEventTap` on `controller.mapEventStream`: the layer hit tester also runs on long presses), a zoom change
  > 1e-3, a level change or the cluster leaving the area.
- flutter_map path: the fmmc widget is keyed by `(layerId, zoom, fitBound, centerMarker, spiderfy)` because
  flutter_map_marker_cluster creates its AnimationControllers in `initState` only; the converted marker list gets a
  new identity when `maxClusterRadius`, `disableClusteringAtZoom`, `size` or `alignment` change, since upstream
  rebuilds its tree only on a new list.
- Marker `rotate`: upright when `Marker.rotate == true || options.rotate == true` (upstream's rule).
- Icons follow the map's appearance: the core clears its icon cache and resyncs layers when the theme, text style,
  direction, brightness or text scale change, so cluster keys need not include them.
- `detach` resets everything tied to the map (new `MarkerPublisher`, planner, spider, timers).
- `MapLayerHost` sets `liveCamera` / `idleCamera` on ready before `isReady` is true: the engine's listeners must not
  check `isReady`.

## Commands

```sh
flutter pub get && flutter analyze
dart format --line-length 120 packages example
cd packages/flutter_unified_map_marker_cluster && flutter test
cd example && flutter test && flutter test integration_test -d <device>
example/tool/integration_tests.sh <device>   # one `flutter test` per file; required on macOS
```

Devices on this Mac: simulators "iPhone 17 Pro Max" / "iPhone 17", `-d macos`, `emulator-5554` (Google Maps key in
`example/android/local.properties`, `maps.apiKey`). Check `ps aux | grep flutter_tools.snapshot` first: other agents
may be using a device.

## Style

Dart 3.13, flutter_lints, line length 120, no comments that say what the code does, no feature flags or compat shims,
tests next to the code. Nothing is committed by agents: Clovis commits.
