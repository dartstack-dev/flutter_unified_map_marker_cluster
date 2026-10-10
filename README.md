# flutter_unified_map_marker_cluster

Animated marker clustering for [flutter_unified_map](https://github.com/dartstack-dev/flutter_unified_map) with the API of
[flutter_map_marker_cluster](https://pub.dev/packages/flutter_map_marker_cluster). Usage, differences with
flutter_map_marker_cluster and how it works: [the package README](packages/flutter_unified_map_marker_cluster/README.md).

<img src="https://raw.githubusercontent.com/dartstack-dev/flutter_unified_map_marker_cluster/main/screenshots/spiderfy-cluster.png" alt="The demo pins gathered under one cluster" width="230" height="500">
<img src="https://raw.githubusercontent.com/dartstack-dev/flutter_unified_map_marker_cluster/main/screenshots/spiderfy-open.png" alt="The cluster spiderfied: pins spread on a spiral with legs" width="230" height="500">
<img src="https://raw.githubusercontent.com/dartstack-dev/flutter_unified_map_marker_cluster/main/screenshots/spiderfy-closed.png" alt="The spider closed again" width="230" height="500">

## Layout

| Path | Role |
|---|---|
| `packages/flutter_unified_map_marker_cluster` | The package: `MarkerClusterLayerWidget`, `MarkerClusterLayerOptions`, nodes |
| `example/` | Demo app: opens on the Brussels city network under one cluster — one tap zooms into its 120 pins — plus a spiderfy page (one stack of 30 pins, a single cluster spread on a spiral), and the end-to-end tests |

The repository is a pub workspace. `flutter_unified_map` and its federated packages are not published yet: the root
`pubspec.yaml` overrides them with the sibling clone `../flutter_unified_map`.

## Commands

```sh
flutter pub get                                   # once, at the root
flutter analyze                                   # whole workspace
cd packages/flutter_unified_map_marker_cluster && flutter test
cd example && flutter test                        # demo scenes on the flutter_map backend, no device
cd example && flutter run                         # demo app
cd example && flutter test integration_test -d <device>
example/tool/integration_tests.sh <device>          # one `flutter test` per file (macOS needs it)
```

## End-to-end tests

`example/integration_test` runs on the native maps through a `RecordingPlatform` that wraps the real backend and
records what reaches it (and lets a test inject native events, since synthetic Flutter taps do not reach UIKit and
AppKit platform views). On the flutter_map backend they are skipped (flutter_map_marker_cluster draws the clusters).

| Test | Checks |
|---|---|
| `marker_visibility_test.dart` | 16 steps of zooms, pans, bursts of moves and rotations over the demo pins: every published marker fully on screen is found in the native snapshot (and on iOS in a screenshot), no test color is drawn outside the published markers, and above `disableClusteringAtZoom` every pin on screen is published |
| `cluster_transition_test.dart` | Zoom 7 → 8: new elements carry `appearFrom` = position of an element that was on the map, split clusters fade, unchanged elements keep their ids; 8 → 7: leaving elements carry `disappearTo` = position of an element now on the map, and the final elements equal the first ones; a 1.5 s animated zoom sends animated reclusters before its idle event; after 12 quick zoom steps nothing is missing or left behind |
| `spiderfy_test.dart` | A tap on a centered cluster of 12 pins sharing one point (a real native tap on Android, an injected native tap event on iOS and macOS) spiderfies it: 12 markers appear from the cluster position on a spiral, 12 legs from the cluster, all visible in the snapshot; a map tap closes it (`disappearTo` = cluster position, legs removed). The same cluster off center: the camera centers it, then the spider opens and is still open once the camera settled. A ring of 12 pins that separates only beyond `maxZoom` 17: the first tap zooms to 17 without spiderfying, the second spiderfies |

On macOS run the files one at a time with `example/tool/integration_tests.sh macos` (one `flutter test` per file,
then a summary): with several files in one `flutter test` the Flutter tool fails to relaunch the desktop app for the
second one ("Unable to start the app on the device", "The log reader stopped unexpectedly"), whatever the tests do:
the first file's app stays alive until the whole command ends, and the second instance of the same bundle starts and
dies within seconds without connecting. With one command per file the app is gone as soon as `flutter test` returns.
Each file also keeps the macOS test window in front (`support/macos_test_window.dart`: all Spaces, floating level):
Flutter draws no frame while the window is off screen, for instance when an iOS simulator run activates
Simulator.app at the same time, and every `pump` then blocks for minutes.

Android needs `maps.apiKey` in `example/android/local.properties` (not committed) or the `MAPS_API_KEY` environment
variable at build time.
