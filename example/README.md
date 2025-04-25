# flutter_unified_map_marker_cluster example

- **Pins**: 500 deterministic pins in one `MarkerClusterLayerWidget`. The map opens on the dense Brussels
  city network under a single cluster: tap it and the camera zooms in while the cluster splits down to every
  pin; tap a pin to select it.
- **Spiderfy**: one stack of 30 pins on the same point of Brussels — a single cluster, and a tap spreads it on a
  spiral (fewer than 9 pins would spread on a circle).
- The tune button changes the split / merge, spiderfy, fit and center durations (0 ms turns one off; the demo
  defaults to 2000 ms); the chip says whether the clusters are native or drawn by flutter_map_marker_cluster.

```sh
flutter run                                     # pick a device
flutter test                                    # demo scenes on the flutter_map backend
flutter test integration_test -d <device>       # native end-to-end tests (see the repository README)
```

## Screenshots

`../screenshots/` holds the Spiderfy page of this demo on the iOS simulator: the 30-pin Heysel cluster before the
tap (`spiderfy-cluster.png`), its spider spread on a spiral with its legs (`spiderfy-open.png`), and back to the
cluster after a map tap (`spiderfy-closed.png`). To regenerate them on a simulator:

```sh
example/tool/capture_spiderfy_screenshots.sh <ios-udid>   # or "macos" (captures the screen; the test window stays in front)
```

`spiderfy_screenshot_test.dart` drives the real demo app and asserts the spider opens and closes while the
screenshots are taken.

Android needs `maps.apiKey=<key>` in `android/local.properties` or `MAPS_API_KEY` in the environment.
