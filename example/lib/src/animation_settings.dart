import 'package:flutter/material.dart';
import 'package:flutter_unified_map_marker_cluster/flutter_unified_map_marker_cluster.dart';

/// The demo's animation durations: every animation slowed to 2000 ms so the split, merge, fit, center and spiderfy
/// moves are easy to follow in a screen or video recording.
const demoAnimations = AnimationsOptions(
  zoom: Duration(milliseconds: 2000),
  fitBound: Duration(milliseconds: 2000),
  centerMarker: Duration(milliseconds: 2000),
  spiderfy: Duration(milliseconds: 2000),
);

/// The demo's editable animation durations, shared by every page.
class AnimationSettings extends ValueNotifier<AnimationsOptions> {
  AnimationSettings() : super(demoAnimations);

  void set({Duration? zoom, Duration? spiderfy, Duration? fitBound, Duration? centerMarker}) {
    final o = value;
    value = AnimationsOptions(
      zoom: zoom ?? o.zoom,
      spiderfy: spiderfy ?? o.spiderfy,
      fitBound: fitBound ?? o.fitBound,
      centerMarker: centerMarker ?? o.centerMarker,
    );
  }
}

/// Bottom sheet with one slider per animation duration.
class AnimationSettingsSheet extends StatelessWidget {
  const AnimationSettingsSheet({super.key, required this.settings});

  final AnimationSettings settings;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: settings,
    builder: (context, o, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Animation durations', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '0 ms turns an animation off. Slow values make the split, merge and spiderfy easy to follow.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _DurationSlider(
              label: 'Split / merge (zoom)',
              value: o.zoom,
              onChanged: (d) => settings.set(zoom: d),
            ),
            _DurationSlider(
              label: 'Spiderfy',
              value: o.spiderfy,
              onChanged: (d) => settings.set(spiderfy: d),
            ),
            _DurationSlider(
              label: 'Fit cluster',
              value: o.fitBound,
              onChanged: (d) => settings.set(fitBound: d),
            ),
            _DurationSlider(
              label: 'Center marker',
              value: o.centerMarker,
              onChanged: (d) => settings.set(centerMarker: d),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => settings.value = demoAnimations, child: const Text('Reset')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DurationSlider extends StatelessWidget {
  const _DurationSlider({required this.label, required this.value, required this.onChanged});

  final String label;
  final Duration value;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 150, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.inMilliseconds.toDouble(),
          max: 3000,
          divisions: 30,
          label: '${value.inMilliseconds} ms',
          onChanged: (v) => onChanged(Duration(milliseconds: v.round())),
        ),
      ),
      SizedBox(width: 64, child: Text('${value.inMilliseconds} ms', textAlign: TextAlign.end)),
    ],
  );
}
