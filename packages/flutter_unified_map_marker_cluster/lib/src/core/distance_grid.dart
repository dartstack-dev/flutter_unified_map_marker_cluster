// Port of flutter_map_marker_cluster 8.2.2's DistanceGrid (BSD-3-Clause, Copyright (c) 2018 Lorenzo Pongetti; see
// LICENSE), kept identical so that native clusters match the ones flutter_map_marker_cluster draws.
import 'dart:collection';
import 'dart:ui';

class _CellEntry<T> {
  final T obj;
  final double x;
  final double y;

  const _CellEntry(this.x, this.y, this.obj);
}

typedef _GridKey = (int row, int col);

class DistanceGrid<T> {
  final int cellSize;
  final double _sqCellSize;

  final _grid = HashMap<_GridKey, List<_CellEntry<T>>>();
  final _objectPoint = HashMap<T, _GridKey>();

  DistanceGrid(int cellSize) : cellSize = cellSize > 0 ? cellSize : 1, _sqCellSize = (cellSize * cellSize).toDouble();

  void addObject(T obj, Offset point) {
    final key = (_coord(point.dy), _coord(point.dx));
    _objectPoint[obj] = key;
    (_grid[key] ??= []).add(_CellEntry<T>(point.dx, point.dy, obj));
  }

  /// Whether the object was in the grid.
  bool removeObject(T obj) {
    final key = _objectPoint.remove(obj);
    if (key == null) return false;
    final cell = _grid[key]!..removeWhere((e) => e.obj == obj);
    if (cell.isEmpty) _grid.remove(key);
    return true;
  }

  T? getNearObject(Offset point) {
    final px = point.dx;
    final py = point.dy;
    final x = _coord(px);
    final y = _coord(py);
    var closestDistSq = _sqCellSize;
    T? closest;
    var foundCenter = false;
    for (final (:dist, :row, :col) in _neighbors) {
      if (foundCenter && dist > 1) break;
      final cell = _grid[(y + row, x + col)];
      if (cell == null) continue;
      for (final entry in cell) {
        final dx = px - entry.x;
        final dy = py - entry.y;
        final distSq = dx * dx + dy * dy;
        if (distSq <= closestDistSq) {
          closestDistSq = distSq;
          closest = entry.obj;
          if (dist == 0) foundCenter = true;
        }
      }
    }
    return closest;
  }

  int _coord(double x) => x ~/ cellSize;
}

const _neighbors = <({int dist, int row, int col})>[
  (dist: 0, row: 0, col: 0),
  (dist: 1, row: -1, col: 0),
  (dist: 1, row: 1, col: 0),
  (dist: 1, row: 0, col: -1),
  (dist: 1, row: 0, col: 1),
  (dist: 2, row: -1, col: -1),
  (dist: 2, row: 1, col: -1),
  (dist: 2, row: -1, col: 1),
  (dist: 2, row: 1, col: 1),
];
