## 0.1.0 (unreleased)

- First version, moved out of `flutter_unified_map` (where the layer was `MarkerClusterLayer`, clustered with
  supercluster on camera idle and without animation).
- API of flutter_map_marker_cluster 8.2: `MarkerClusterLayerWidget`, `MarkerClusterLayerOptions` with every option
  (except `popupOptions`), `AnimationsOptions`, `PolygonOptions`, `MarkerClusterNode`, `MarkerNode`; extra
  `clusterIconKey` for native bitmaps and `spiderLegs` for the native spider legs.
- Web, Windows, Linux: the real flutter_map_marker_cluster, drawn inside the flutter_map backend.
- Android, iOS, macOS: flutter_map_marker_cluster's clustering ported to Dart (same clusters at the same zoom),
  native markers published atomically, animated split and merge on every zoom level change (also during gestures,
  with a small hysteresis around integer zooms), reclustering while panning, native spiderfy with legs, hull polygon
  while zooming to a cluster.
- Native object ids depend on the marker keys (clusters: `<layerId>/c<zoom>:<first marker id>`): an equivalent
  marker list sends nothing to the map and keeps an open spider; transitions published before the previous one
  reached the map or finished slide out of where the container is on screen; the area wraps across the antimeridian;
  markers on screen are published first when the area holds more than 1500 elements.
- A cluster tap that moves the camera spiderfies once the camera reached the cluster (not after an interrupted move).
- Markers with a NaN or infinite coordinate are left out and reported on every platform.
