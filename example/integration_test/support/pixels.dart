import 'dart:typed_data';
import 'dart:ui' as ui;

/// Straight-alpha RGBA pixels of a decoded image.
class RgbaImage {
  const RgbaImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  ui.Rect get bounds => ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  /// Counts pixels inside [region] (physical pixels, clipped to the image) and outside every rect of [exclude] for
  /// which [test] holds.
  int count(bool Function(int r, int g, int b, int a) test, {ui.Rect? region, List<ui.Rect> exclude = const []}) {
    final area = (region ?? bounds).intersect(bounds);
    if (area.isEmpty) return 0;
    var n = 0;
    for (var y = area.top.floor(); y < area.bottom.ceil(); y++) {
      for (var x = area.left.floor(); x < area.right.ceil(); x++) {
        final i = (y * width + x) * 4;
        if (!test(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])) continue;
        if (exclude.any((r) => r.contains(ui.Offset(x + 0.5, y + 0.5)))) continue;
        n++;
      }
    }
    return n;
  }
}

Future<RgbaImage> decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return RgbaImage(image.width, image.height, data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } finally {
    image.dispose();
    codec.dispose();
  }
}

/// Opaque-enough pixels whose every channel is within [tolerance] of [color]'s.
int countPixelsNear(
  RgbaImage image,
  ui.Color color, {
  int tolerance = 40,
  ui.Rect? region,
  List<ui.Rect> exclude = const [],
}) {
  final argb = color.toARGB32();
  final r0 = (argb >> 16) & 0xFF;
  final g0 = (argb >> 8) & 0xFF;
  final b0 = argb & 0xFF;
  return image.count(
    (r, g, b, a) =>
        a >= 200 && (r - r0).abs() <= tolerance && (g - g0).abs() <= tolerance && (b - b0).abs() <= tolerance,
    region: region,
    exclude: exclude,
  );
}
