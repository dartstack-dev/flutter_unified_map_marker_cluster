# flutter_unified_map_marker_cluster

Marker clustering for [flutter_unified_map](https://github.com/dartstack-dev/flutter_unified_map) with the API of
[flutter_map_marker_cluster](https://pub.dev/packages/flutter_map_marker_cluster) 8.2: clusters split and merge with
an animation when the zoom level changes, also during a pinch, and a cluster that zooming cannot split spreads its
markers around it (spiderfy).

| Platform | Clustering | Drawing and animations |
|---|---|---|
| Android | Dart, flutter_map_marker_cluster's algorithm | Google Maps markers, animated natively |
| iOS, macOS | Dart, flutter_map_marker_cluster's algorithm | MapKit annotations, animated natively |
| Web, Windows, Linux, tests | flutter_map_marker_cluster itself | flutter_map_marker_cluster, inside the flutter_map backend |

| Gathered under one cluster | Spiderfied | Closed again |
|---|---|---|
| <img src="https://raw.githubusercontent.com/dartstack-dev/flutter_unified_map_marker_cluster/main/screenshots/spiderfy-cluster.png" alt="The demo pins gathered under one cluster" width="230" height="500"> | <img src="https://raw.githubusercontent.com/dartstack-dev/flutter_unified_map_marker_cluster/main/screenshots/spiderfy-open.png" alt="The cluster spiderfied: pins spread on a spiral with legs" width="230" height="500"> | <img src="https://raw.githubusercontent.com/dartstack-dev/flutter_unified_map_marker_cluster/main/screenshots/spiderfy-closed.png" alt="The spider closed again" width="230" height="500"> |

```dart
UnifiedMap(
  options: const MapOptions(initialCenter: LatLng(48.5, 9.0), initialZoom: 5),
  children: [
    MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        markers: [
          for (final station in stations)
            Marker(key: ValueKey(station.id), point: station.point, iconKey: station.brand, child: Pin(station.brand)),
        ],
        size: const Size(44, 44),
        disableClusteringAtZoom: 12,
        builder: (context, markers) => ClusterBadge(count: markers.length),
        onMarkerTap: (marker) => select(marker.key),
      ),
    ),
  ],
)
```

## Spiderfy

A cluster that zooming cannot split — markers stacked on the same point, or a cluster still whole at `maxZoom` —
spreads its markers around it on tap. Three layouts:

- **circle** — up to `circleSpiralSwitchover` markers (9 by default) on a circle `spiderfyCircleRadius` pixels
  around the cluster;
- **spiral** — from that count on, an Archimedean spiral ("snail"), its spacing widened by
  `spiderfySpiralDistanceMultiplier` (keep it above 1 so the markers do not overlap);
- **your own** — `spiderfyShapePositions` receives the marker count and the cluster's position in pixels and returns
  a position per marker.

```dart
MarkerClusterLayerOptions(
  circleSpiralSwitchover: 9,            // circle up to 9 markers, spiral from there on
  spiderfyCircleRadius: 40,
  spiderfySpiralDistanceMultiplier: 2,  // a wider snail for dense stacks
  spiderLegs: const SpiderLegOptions(), // native maps only: a leg joins every marker back to the cluster
)
```

The markers glide out with `animationsOptions.spiderfy`; a map tap or a zoom change folds them back in. On
Android, iOS and macOS the legs are polylines (`spiderLegs`, null draws none); flutter_map_marker_cluster draws no
legs, so web, Windows and Linux never show them.

## Migrating from flutter_map_marker_cluster

Import `package:flutter_unified_map/flutter_unified_map.dart` and
`package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart` instead of flutter_map and
flutter_map_marker_cluster. `MarkerClusterLayerWidget`, `MarkerClusterLayerOptions` (every option, with the same
names, types and defaults), `AnimationsOptions`, `PolygonOptions`, `MarkerClusterNode` and `MarkerNode` keep their
names; `Marker` and `LatLngBounds` are flutter_unified_map's.

Differences:

- **Bitmaps.** On Android, iOS and macOS the markers are native: every marker child and cluster widget is rasterised
  once per key. Give markers an `iconKey` that captures their look (see `Marker`), and clusters a
  `clusterIconKey` when the `builder` shows more than the count (the default key is the number of markers).
- **No `popupOptions`** (flutter_map_marker_popup): open your popup from `onMarkerTap`, for example with a
  `MarkerLayer` holding a selected pin, or a Flutter overlay.
- **Native gestures.** Native markers report single taps only: `onMarkerDoubleTap`, `onMarkerHoverEnter` and
  `onMarkerHoverExit` are not called there. With `markerChildBehavior: true`, `onMarkerTap` and
  `centerMarkerOnClick` are skipped as on flutter_map, and `Marker.onTap` still fires.
- **Curves.** Native markers move with the platform's ease-in-out; the `AnimationsOptions` curves of the split, merge,
  fade and spiderfy animations apply on flutter_map only. `fitBoundCurves` and `centerMarkerCurves` are passed to the
  camera animations everywhere (the native camera ignores curves, see flutter_unified_map's STATUS).
- **Spiderfy.** As in flutter_map_marker_cluster, a tapped cluster spiderfies when zooming cannot split it. Natively:
  - this also covers markers sharing the exact same point (flutter_map_marker_cluster first zooms to `maxZoom`, then
    spiderfies on a second tap);
  - the camera centers such a cluster at its current zoom, where flutter_map_marker_cluster rounds the zoom up;
  - the spiderfied cluster stays under its markers at 30 % opacity;
  - legs join the markers to the cluster once they arrived, styled by the extra `spiderLegs` option (null draws
    none; flutter_map_marker_cluster draws no legs, so web, Windows and Linux never show them);
  - a map tap (not a long press) or a zoom closes the spider;
  - when the tap first moves the camera to center the cluster, the spider opens once the platform reports the camera
    there, and not at all if the user takes the camera elsewhere meanwhile;
  - the hull polygon is drawn solid.
- **Callbacks.** `onClusterTap` receives a `MarkerClusterNode` of this package. On flutter_map it is converted from
  flutter_map_marker_cluster's node with its subtree (its `parent` is null). `onMarkersClustered` receives, natively,
  the markers shown alone that join a cluster (zooming out, a spider closing).
- **Rebuilds.** As in flutter_map_marker_cluster, a new `markers` list rebuilds the clusters and a new `computeSize`
  alone does not; on every platform a new `maxClusterRadius`, `disableClusteringAtZoom`, `size` or `alignment`
  rebuilds them too. Natively the tree is kept when the new markers have the same keys and points as the previous
  ones (only the markers it hands out change), and an equivalent list sends nothing to the map (see below). A real
  change rebuilds the tree on the UI thread, in O(markers × zoom levels): a few tens of milliseconds for 4000 markers.
- **Marker keys.** Give every marker a unique `Key`: native ids, and so the transitions across list changes, follow
  the keys; a marker without a key is identified by its index. Duplicate keys fail an assertion in debug builds.
- **Invalid coordinates.** A marker with a NaN or infinite coordinate is left out and reported through
  `FlutterError.reportError` (flutter_map_marker_cluster throws).

### From flutter_unified_map's former `MarkerClusterLayer`

`MarkerClusterLayer(options:)` becomes `MarkerClusterLayerWidget(options:)`, with flutter_map_marker_cluster's
defaults: `disableClusteringAtZoom` 20 (clusters up to and including that level), `padding` is the padding of the
camera fit on a cluster tap (default zero) and `alignment` is nullable. With `zoomToBoundsOnClick: false` every
cluster tap spiderfies unless `spiderfyCluster: false`: an app that moves the camera itself in `onClusterTap` must set
it, or its camera move closes the spider right after it opened.

## How it works on native maps

The tree is built once per marker list, with flutter_map_marker_cluster's distance grid and radius semantics, so the
clusters are the same as on flutter_map at the same zoom (the cluster level is the zoom rounded up). The layer
publishes the elements of that level in the viewport grown by one viewport on each side (at most 1500: those on
screen first, then the nearest to the screen), as one atomic generation through `flutter_unified_map`'s
`MarkerPublisher`:

- the area is clustered again when the camera settles (unless the last generation still covers it), as soon as the
  zoom level changes during a gesture or an animation (0.05 past the level's boundary, so that a pinch hovering on an
  integer zoom does not flip the clusters; a settled camera always shows the exact level), and when a gesture moved
  the camera by more than a quarter of the viewport (at most every 150 ms);
- a level change sends a `MarkerTransition` of `animationsOptions.zoom`: an element that was not on the map slides
  out of the element on the map that contains it, an element leaving slides into the new element that contains it,
  the others fade; elements present before and after keep their id and do not move. `Duration.zero` turns it off;
- a spider opening or closing is the same transition with `animationsOptions.spiderfy`;
- a cluster tap fits the camera to the cluster with `animationsOptions.fitBound`, a marker tap centers it with
  `animationsOptions.centerMarker`, and the cluster's convex hull is shown while the map zooms in (`showPolygon`).

Object ids depend on the marker keys: a marker is `MapLayerState.objectId(marker.key, index)`, a cluster
`'<layerId>/c<zoom>:<id of its first marker without the layer id>'`. A new list of equivalent markers therefore
gives the same ids: nothing is sent to the map, an open spider stays open, and transitions continue across it. A tap
is resolved against the tree of the generation the map shows, which may be older than the newest one while that one
waits for its icons.

A generation can reach the map before the previous one finished animating, or together with it (the map merges the
generations set before one push). So a new element slides out of where its container is on screen, estimated from
the container's own glide (ease-in-out over the transition's duration), and the elements still sliding away are sent
on into the new element that contains them: during a fast pinch across several levels everything comes out of, and
goes back into, what the user sees.

The area wraps across the antimeridian like the native maps, and distances to the screen are measured the short way
round. When the camera settles, the icons of the on-screen clusters of the neighbouring levels are rasterised ahead
(at most 48, nearest the center first, four at a time), so a zoom step rarely waits for them.

## Example

`example/example.dart` is a minimal map. The `example/` app of
[the repository](https://github.com/dartstack-dev/flutter_unified_map_marker_cluster) opens on the Brussels city network
— 120 pins under one cluster: tap it and the camera zooms in while the cluster splits down to every pin —
plus a spiderfy page (one stack of pins on the same point — a single cluster that a tap spreads on a spiral); its
tune button changes the animation durations, and its end-to-end tests run on the native maps.
