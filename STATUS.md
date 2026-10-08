# Status

Oct 8 2026 (review fixes), Flutter 3.47.4, Dart 3.13, against the sibling `../flutter_unified_map` (path overrides).
Nothing is committed.

## What works, per platform

| Platform | How the clusters are made | State |
|---|---|---|
| Android | Native engine (`src/native/native_cluster_engine.dart`): Dart clustering with flutter_map_marker_cluster's algorithm, Google Maps markers animated natively | Verified on `emulator-5554` with a Maps key. Animated split and merge on level changes (also during gestures), spiderfy with legs, a real native tap on the cluster |
| iOS | Native engine, MapKit annotations animated natively | Verified on the iPhone 17 Pro Max simulator. Taps are injected as native events, because synthetic Flutter taps do not reach UIKit platform views |
| macOS | Native engine, MapKit | Verified, one file per `flutter test`. Taps are injected as on iOS |
| Web | The real flutter_map_marker_cluster 8.2.2 through `setFlutterMapLayers` (`src/flutter_map/flutter_map_cluster_bridge.dart`) | Example built; a headless Chrome screenshot shows the clusters. Gestures and animations were not exercised in a browser |
| Windows, Linux | Same as web | Not built (needs those hosts) |
| Headless tests | Same as web, on the `flutter_unified_map_flutter_map` backend | 7 package tests on the flutter_map backend; one of them compares the native clustering with the real package at zooms 5, 6.4, 7, 8.7 and 10.2, the others check rendering, callbacks, keying, option changes and invalid coordinates. GasMobility's headless ShellMap test finds the `StationClusterBadge` widgets drawn by flutter_map_marker_cluster |

Native behaviour, as decided with Clovis:
- **Cluster level:** `(zoom - 1e-6).ceil()` on a settled camera; during a gesture or an animation the level changes
  only 0.05 past its boundary (hysteresis against flipping on a pinch hovering on an integer zoom).
- **When the map reclusters:**
  - on an idle camera, unless the last generation already covers it (same tree, level, spider and rotation, nothing
    capped, moved less than 25 % of the viewport);
  - on a live camera when the level or the spider changes;
  - during a gesture that moved more than 25 % of the viewport, at most every 150 ms.
- **Area:** the viewport plus one viewport on each side, wrapping across the antimeridian, capped at 1500 elements
  (spider leaves included): those on screen first, then the nearest to the screen. A map without a size publishes
  nothing.
- **Tree:** kept when a new marker list has the same keys and points (only the markers it hands out change); markers
  with a NaN or infinite coordinate are left out and reported.
- **Transitions:**
  - A new element slides out of the element on the map that contained it.
  - A leaving element slides into the new element that contains it.
  - Duration: `animationsOptions.zoom` for a level change, `animationsOptions.spiderfy` for a spider.
- **Ids depend on the marker keys:** an equivalent marker list sends nothing to the map. Taps resolve against the
  tree of the generation the map shows.
- **Spiderfy:** opens when zooming cannot split the cluster, or when its markers share one point. A map tap or a zoom
  closes it. Legs follow the `spiderLegs` option (native only; null draws none).
- **Icon prefetch:** on a settled camera, at most 48 on-screen clusters of the neighbouring levels, nearest the center
  first, four at a time; skipped when nothing moved.

See AGENTS.md and the package README for the details.

## How it was verified

The review fixes of Oct 8 2026 were checked with these commands, on the final code:

| Command | Result |
|---|---|
| `flutter analyze` (root) | No issues found |
| `dart format --line-length 120 --output=none --set-exit-if-changed packages/flutter_unified_map_marker_cluster example/lib example/test example/integration_test` | 0 changed |
| `flutter test` in `packages/flutter_unified_map_marker_cluster` | 52 passed: 22 + 20 native-engine tests on a fake platform (`native_cluster_test.dart`, `native_options_test.dart`), 3 transition-planner unit tests, 7 on the real flutter_map backend |
| `flutter test` in `example` | 2 passed (demo scenes on the flutter_map backend) |
| `flutter test integration_test/<file>.dart -d <iPhone 17 Pro Max>`, one command per file | `cluster_transition_test` passed (zoom 7→8: 177 markers, 171 `appearFrom`; 8→7: 171 `disappearTo`; after the quick steps 0 missing, 0 ghost pixels); `marker_visibility_test` passed (16 steps, 0 failing, 57 s); `spiderfy_test` 3 passed |

Final verification of Oct 8 2026, on the final code of both repos (`flutter analyze` clean, 52 + 2 tests passed,
example built for `ios --simulator --debug`, `macos --debug` and `apk --debug`), one `flutter test` per file, the
devices in parallel with the core repo's sweep:

| File | iPhone 17 Pro Max simulator | macOS | emulator-5554 |
|---|---|---|---|
| `cluster_transition_test.dart` | 1 passed | failed, then 1 passed on a lone re-run | 1 passed |
| `marker_visibility_test.dart` | 1 passed (57 s) | failed, then 1 passed on a lone re-run | 1 passed |
| `spiderfy_test.dart` | 3 passed | 3 passed | 3 passed |
| GasMobility `integration_test/shell_map_test.dart` | 1 passed | 1 passed | 1 passed |

Both macOS failures started with the test window off screen (`[window] visible before activation: false`, "Failed to
foreground app") while the iOS runs were activating Simulator.app: native transitions do not advance while the window
is off screen, so the snapshots missed every marker (`marker_visibility_test`, all 10 failing steps) or a split check
failed (`cluster_transition_test`). Re-run alone with the window visible, both passed with no change.

In the Oct 7 sweep
every file passed on all three devices (macOS: 221 markers, 213 / 213; emulator: 99 markers, 95 / 95; visibility
0 failing steps on each), with these earlier, non-recurring exceptions:
- **macOS `marker_visibility_test`, one run:** timed out at 6 min because the test window went off screen while iOS
  runs activated Simulator.app (Flutter draws no frame then). `support/macos_test_window.dart` now keeps the window in
  front; the next run under the same load took 68 s.
- **macOS `spiderfy_test`, one run:** the maxZoom ring test found no cluster at zoom 17. It did not recur in 3 later
  runs; the test logs the settled zoom and the markers.

## Limitations

- **Native animations**
  - The native curves are ease-in-out. The `AnimationsOptions` curves apply on flutter_map only.
  - Chained transitions estimate where a container is on screen from the engine's own clock: the core does not report which generation reached the platform.
  - Not checked by eye mid-animation; only through the recorded transitions and the snapshots taken after they settle.
- **Taps**
  - Native maps report only single taps: there is no `onMarkerDoubleTap` and no hover.
  - `popupOptions` is not supported.
  - A spider closes on `MapEventTap` from the controller's stream, one microtask later than a hit tester would.
- **Android**
  - The emulator's Google Maps SDK is slow with many animated markers. In the core repo's load test, 600 markers took 80 ms per split call and 89 ms per merge call. A real phone was not measured.
  - Step 0 once missed 3 clusters in the snapshot, in a review run before this round; it never happened in this round's runs. On failure, the test logs each missing marker's update history.
- **macOS**
  - `flutter test integration_test -d macos` with several files runs only the first file; use `example/tool/integration_tests.sh macos`.
  - Windows off screen stall the frames, hence the window helper.
- **Not covered by the device tests:** Windows and Linux; web gestures; a physical device.
- **macOS window helper:** `holdMacOSTestWindowInFront()` activates the window but does not wait until it is visible;
  a window that starts off screen under parallel iOS runs can still fail a run (see above).
- **Rebuild cost:** a marker list whose keys or points changed rebuilds the tree synchronously on the UI thread
  (about 44-72 ms for 4000 markers in a debug benchmark, 270 ms for 20 000). Building it in an isolate is not done.
- **Spider legs** exist only natively: flutter_map_marker_cluster draws none.

## Next steps

- Run on physical devices: a mid-range Android phone and a 120 Hz iPhone, with GasMobility's real station set.
- Check web in a browser: zoom animations, spiderfy, cluster taps.
- When the core exposes it, use an "applied generation" signal from `MarkerPublisher` instead of the estimated container positions, and a tap or long-press event kind in the layer hit tester.
- Watch the two intermittent failures above (Android step 0, macOS maxZoom ring); their tests now log enough to tell the cause.
