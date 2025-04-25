import 'package:flutter/material.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show UnifiedMapsPlatform;

import 'src/animation_settings.dart';
import 'src/capture_page.dart';
import 'src/demo_data.dart';
import 'src/map_widgets.dart';
import 'src/spiderfy_page.dart';
import 'src/pins_page.dart';

void main() => runApp(const ClusterExampleApp());

class ClusterExampleApp extends StatefulWidget {
  const ClusterExampleApp({super.key});

  @override
  State<ClusterExampleApp> createState() => _ClusterExampleAppState();
}

class _ClusterExampleAppState extends State<ClusterExampleApp> {
  final _settings = AnimationSettings();
  var _page = 0;

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const bool.fromEnvironment('CLUSTER_CAPTURE')
      ? MaterialApp(title: 'Unified Map Marker Cluster', debugShowCheckedModeBanner: false, home: const CaptureMap())
      : MaterialApp(
          title: 'Unified Map Marker Cluster',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFF0F766E), useMaterial3: true),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF0F766E),
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ValueListenableBuilder(
                valueListenable: _settings,
                builder: (context, animations, _) {
                  final top = MediaQuery.paddingOf(context).top + 12;
                  final header = Positioned(
                    top: top,
                    left: 12,
                    right: 72,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _page == 0
                          ? const PinsHeader(count: demoPinCount)
                          : const MapCard(child: Text('Tap a cluster that cannot be split by zooming')),
                    ),
                  );
                  final buttons = Positioned(
                    top: top,
                    right: 12,
                    child: Column(
                      children: [
                        MapButton(
                          tooltip: 'Animation durations',
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            builder: (_) => AnimationSettingsSheet(settings: _settings),
                          ),
                          child: const Icon(Icons.tune),
                        ),
                        const SizedBox(height: 8),
                        const ZoomButtons(),
                        const SizedBox(height: 8),
                        _BackendChip(),
                      ],
                    ),
                  );
                  return _page == 0
                      ? PinsMap(animations: animations, overlays: [header, buttons])
                      : SpiderfyMap(animations: animations, overlays: [header, buttons]);
                },
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _page,
                onDestinationSelected: (page) => setState(() => _page = page),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.place_outlined), label: 'Pins'),
                  NavigationDestination(icon: Icon(Icons.scatter_plot_outlined), label: 'Spiderfy'),
                ],
              ),
            ),
          ),
        );
}

/// Says which clustering runs: native markers or the real flutter_map_marker_cluster.
class _BackendChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final flutterMap = UnifiedMapsPlatform.instance.supportsFlutterMapLayers;
    return MapCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(flutterMap ? 'flutter_map' : 'native', style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
