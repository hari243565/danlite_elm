// Regenerates assets/launcher/logo_adaptive_foreground.png from the brand art.
//
//   dart run tool/make_adaptive_foreground.dart \
//       assets/images/logo.png assets/launcher/logo_adaptive_foreground.png
//
// Run this whenever assets/images/logo.png changes, then re-run
// `dart run flutter_launcher_icons` to rebuild the Android icon set.
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Derives an Android adaptive-icon FOREGROUND from the flattened brand logo.
///
/// The source art has its navy plate and rounded corners baked in. Fed to the
/// launcher as-is it would be masked twice and lose ~41% of the artwork. This
/// lifts the artwork off its plate (soft luminance key + un-premultiply against
/// the plate's own vertical gradient) and re-centres it, scaled so that EVERY
/// ink pixel sits inside the 66/108dp circle Android guarantees is visible.
///
/// Crop + scale + pad only. No artwork is invented or redrawn.
void main(List<String> args) {
  final src = img.decodePng(File(args[0]).readAsBytesSync())!;
  final out = File(args[1]);
  final w = src.width, h = src.height;

  // ── Per-row plate colour. Ink starts at x=143, so x=70 is always plate.
  final bgRow = List<List<int>>.generate(h, (y) {
    final p = src.getPixel(70, y);
    return [p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt()];
  });
  int? firstOpaque, lastOpaque;
  for (var y = 0; y < h; y++) {
    if (bgRow[y][3] > 250) { firstOpaque ??= y; lastOpaque = y; }
  }
  for (var y = 0; y < h; y++) {
    if (bgRow[y][3] <= 250) {
      bgRow[y] = List<int>.from(bgRow[y < firstOpaque! ? firstOpaque : lastOpaque!]);
    }
  }

  double lum(num r, num g, num b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

  // ── Soft alpha key: coverage ramps from the plate's own luminance upward.
  final keyed = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    final b = bgRow[y];
    final bl = lum(b[0], b[1], b[2]);
    final lo = bl + 10.0, hi = bl + 70.0;
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      if (p.a < 8) { keyed.setPixelRgba(x, y, 0, 0, 0, 0); continue; }
      var a = ((lum(p.r, p.g, p.b) - lo) / (hi - lo)).clamp(0.0, 1.0);
      if (a <= 0.001) { keyed.setPixelRgba(x, y, 0, 0, 0, 0); continue; }
      num r = p.r, g = p.g, bb = p.b;
      if (a > 0.15) {
        // Un-premultiply against the plate so edges are not navy-tinted.
        r = ((p.r - (1 - a) * b[0]) / a).clamp(0, 255);
        g = ((p.g - (1 - a) * b[1]) / a).clamp(0, 255);
        bb = ((p.b - (1 - a) * b[2]) / a).clamp(0, 255);
      }
      keyed.setPixelRgba(x, y, r.round(), g.round(), bb.round(), (a * 255).round());
    }
  }

  // ── Ink bbox + the true max radius of ink from that bbox's centre.
  int x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (keyed.getPixel(x, y).a > 12) {
        if (x < x0) x0 = x; if (x > x1) x1 = x;
        if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
  }
  final cx = (x0 + x1) / 2.0, cy = (y0 + y1) / 2.0;
  var maxR = 0.0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      if (keyed.getPixel(x, y).a <= 12) continue;
      final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
      if (d > maxR) maxR = d;
    }
  }

  const canvas = 1024;
  final safeR = canvas * (66.0 / 108.0) / 2.0; // guaranteed-visible circle
  final s = safeR / maxR;

  final crop = img.copyCrop(keyed, x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1);
  final nw = (crop.width * s).round(), nh = (crop.height * s).round();
  final scaled = img.copyResize(crop, width: nw, height: nh,
      interpolation: img.Interpolation.cubic);

  final fg = img.Image(width: canvas, height: canvas, numChannels: 4);
  img.compositeImage(fg, scaled,
      dstX: ((canvas - nw) / 2).round(), dstY: ((canvas - nh) / 2).round());

  out.writeAsBytesSync(img.encodePng(fg));

  stdout.writeln('ink bbox      ($x0,$y0)-($x1,$y1)  centre (${cx.toStringAsFixed(1)},${cy.toStringAsFixed(1)})');
  stdout.writeln('max ink radius ${maxR.toStringAsFixed(1)}px  ->  safe radius ${safeR.toStringAsFixed(1)}px');
  stdout.writeln('scale         ${s.toStringAsFixed(4)}   artwork ${nw}x$nh on ${canvas}x$canvas transparent');
  stdout.writeln('wrote         ${out.path}');

  // ── Verify: 100% of ink must now survive the 66/108 mask.
  var total = 0, inside = 0;
  for (var y = 0; y < canvas; y++) {
    for (var x = 0; x < canvas; x++) {
      if (fg.getPixel(x, y).a <= 12) continue;
      total++;
      final d = math.sqrt(math.pow(x - canvas / 2, 2) + math.pow(y - canvas / 2, 2));
      if (d <= safeR + 0.75) inside++;
    }
  }
  stdout.writeln('VERIFY        ${(100 * inside / total).toStringAsFixed(2)}% of ink inside the 66/108dp safe circle');
}
