import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';

/// Gray of every demo icon: the map stays monochrome so the clustering, not the colors, carries the demo.
const pinGray = Color(0xFF52616F);

/// Demo pin drawn into a 30×30 marker bitmap. Colors are explicit: the core rasterises it off-screen.
class DemoPin extends StatelessWidget {
  const DemoPin({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: pinGray,
      shape: BoxShape.circle,
      border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2)),
      boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))],
    ),
    child: const Center(child: Icon(Icons.place, size: 15, color: Colors.white)),
  );
}

/// Teardrop pin for the selected pin, 30×40 with its tip on the bottom edge.
class SelectedPin extends StatelessWidget {
  const SelectedPin({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(
    painter: _TeardropPainter(),
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: 5),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(Icons.place, size: 13, color: pinGray),
        ),
      ),
    ),
  );
}

class _TeardropPainter extends CustomPainter {
  const _TeardropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final tip = Offset(r, size.height);
    final shoulder = math.acos(r / (size.height - r));
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..arcTo(
        Rect.fromCircle(center: Offset(r, r), radius: r),
        math.pi / 2 + shoulder,
        2 * math.pi - 2 * shoulder,
        false,
      )
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = pinGray);
  }

  @override
  bool shouldRepaint(_TeardropPainter oldDelegate) => false;
}

/// Cluster bubble; its look depends only on the count, so `clusterIconKey: (m) => m.length` is a valid key.
class ClusterBadge extends StatelessWidget {
  const ClusterBadge({super.key, required this.count});

  final int count;

  static String label(int count) => count < 1000 ? '$count' : '${(count / 1000).toStringAsFixed(1)}k';

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x3D52616F)),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: pinGray,
            border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
          ),
          child: Center(
            child: Text(
              label(count),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating square button used by the map overlays.
class MapButton extends StatelessWidget {
  const MapButton({super.key, required this.tooltip, required this.onPressed, required this.child});

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 2,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: IconTheme.merge(
              data: IconThemeData(color: scheme.onSurface, size: 22),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class ZoomButtons extends StatelessWidget {
  const ZoomButtons({super.key});

  @override
  Widget build(BuildContext context) {
    void zoomBy(double amount) {
      final controller = MapController.of(context);
      unawaited(controller.animateTo(zoom: controller.camera.zoom + amount));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MapButton(tooltip: 'Zoom in', onPressed: () => zoomBy(1), child: const Icon(Icons.add)),
        const SizedBox(height: 8),
        MapButton(tooltip: 'Zoom out', onPressed: () => zoomBy(-1), child: const Icon(Icons.remove)),
      ],
    );
  }
}

class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) =>
      const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]);
}

/// Small rounded card floating over the map.
class MapCard extends StatelessWidget {
  const MapCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 10)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.96),
    elevation: 2,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(16),
    child: Padding(padding: padding, child: child),
  );
}
