import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_unified_map/flutter_unified_map.dart';
import 'package:flutter_unified_map_platform_interface/flutter_unified_map_platform_interface.dart'
    show UnifiedMapsPlatform;

import 'fake_platform.dart';

FakeUnifiedMapsPlatform installFakePlatform() {
  final fake = FakeUnifiedMapsPlatform();
  UnifiedMapsPlatform.instance = fake;
  return fake;
}

Widget mapApp({MapController? controller, MapOptions options = const MapOptions(), List<Widget> children = const []}) =>
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600), devicePixelRatio: 2),
        child: UnifiedMap(mapController: controller, options: options, children: children),
      ),
    );

/// Lets off-screen rasterisation (real async engine work) and the per-frame flush run.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// A plain colored dot; markers sharing a color share their bitmap.
class Dot extends StatelessWidget {
  const Dot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
