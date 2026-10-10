import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:path_provider/path_provider.dart';

import 'animation_settings.dart';
import 'pins_page.dart';

/// Shown instead of the demo when `--dart-define=CLUSTER_CAPTURE=true`: the pins map runs a
/// slow zoom in and out over Brussels while the platform's own snapshots are written to the app's
/// documents folder, so the cluster split and merge animations can be assembled into a GIF.
///
/// Every snapshot is logged with its index and elapsed milliseconds, so the encoder can give each
/// GIF frame the delay the capture really took (the snapshot latency varies) instead of a fixed
/// cadence that would make the animation stutter.
class CaptureMap extends StatefulWidget {
  const CaptureMap({super.key});

  @override
  State<CaptureMap> createState() => _CaptureMapState();
}

class _CaptureMapState extends State<CaptureMap> {
  static const _zoomIn = 10.4;
  static const _zoomOut = 5.2;
  static const _phaseDuration = Duration(seconds: 6);
  static const _frameInterval = Duration(milliseconds: 40);

  final _controller = MapController();
  final _ready = Completer<void>();
  var _phase = 'waiting for the map';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    await _ready.future;
    setState(() => _phase = 'loading the base map');
    await Future<void>.delayed(const Duration(seconds: 5));
    final directory = await getApplicationDocumentsDirectory();
    final stopwatch = Stopwatch()..start();
    var index = 0;

    Future<void> snap() async {
      final started = stopwatch.elapsedMilliseconds;
      final image = await _controller.takeSnapshot();
      if (image != null) {
        await File('${directory.path}/cluster-zoom-$index.png').writeAsBytes(image);
        debugPrint('cluster snapshot $index at $started ms');
        index++;
      }
    }

    Future<void> phase(double zoom, String label) async {
      setState(() => _phase = label);
      final phaseStopwatch = Stopwatch()..start();
      unawaited(_controller.animateTo(zoom: zoom, duration: _phaseDuration, curve: Curves.easeInOut));
      while (phaseStopwatch.elapsed < _phaseDuration + const Duration(milliseconds: 300)) {
        await snap();
        await Future<void>.delayed(_frameInterval);
      }
    }

    await phase(_zoomIn, 'zooming in: clusters split');
    await phase(_zoomOut, 'zooming out: clusters merge');
    setState(() => _phase = 'done');
    debugPrint('cluster snapshots done in ${directory.path}');
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: PinsMap(
            controller: _controller,
            animations: demoAnimations,
            initialCenter: const LatLng(50.35, 4.5),
            initialZoom: 5.2,
            onMapReady: () {
              if (!_ready.isCompleted) _ready.complete();
            },
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _phase,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
