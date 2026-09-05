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
/// The source art has its own ground baked in. Fed to the launcher as-is it
/// would be masked twice and lose a large part of the artwork. This lifts the
/// artwork off its ground (soft key + un-premultiply) and re-centres it,
/// scaled so that EVERY ink pixel sits inside the 66/108dp circle Android
/// guarantees is visible.
///
/// Crop + scale + pad only. No artwork is invented or redrawn.
///
/// ── Two ground shapes, detected rather than assumed ───────────────────────
/// The first brand art was a NAVY PLATE with a vertical gradient and rounded
/// transparent corners. This tool keyed it by sampling one column known to be
/// plate at every row (x=70; ink started at x=143) and ramping coverage upward
/// from that row's own luminance.
///
/// Both of those are properties of that one image, not of brand art in
/// general, and the current art breaks both: it is a FLAT WHITE ground, and
/// its ink spans effectively the full width (bbox x=2..1597 of 1600), so no
/// column is plate at every row. The luminance-upward ramp is also the wrong
/// direction for a light ground — against white it keys out the entire image
/// and leaves nothing to scale.
///
/// So the ground is measured now instead of assumed. The 1px border ring
/// decides: an opaque ring that agrees with itself is a FLAT ground, keyed on
/// colour distance (which works for a light and a dark ground alike); anything
/// else falls back to the original per-row gradient path, unchanged.
void main(List<String> args) {
  // decodeImage, not decodePng: brand art arrives in whatever format the
  // designer exported. The current assets/images/logo.png is in fact a
  // progressive JPEG carrying a .png name, and decodePng returns null for it.
  final src = img.decodeImage(File(args[0]).readAsBytesSync())!;
  final out = File(args[1]);
  final w = src.width, h = src.height;

  // ── Measure the ground off the 1px border ring ───────────────────────────
  final ring = <List<int>>[];
  void sample(int x, int y) {
    final p = src.getPixel(x, y);
    ring.add(<int>[p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt()]);
  }
  for (var x = 0; x < w; x++) {
    sample(x, 0);
    sample(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    sample(0, y);
    sample(w - 1, y);
  }

  final ringMid = <int>[
    for (var c = 0; c < 4; c++)
      (ring.map((p) => p[c]).toList()..sort())[ring.length ~/ 2],
  ];

  int chan(List<num> a, List<num> b) => <int>[
        (a[0] - b[0]).abs().toInt(),
        (a[1] - b[1]).abs().toInt(),
        (a[2] - b[2]).abs().toInt(),
      ].reduce(math.max);

  var ringSpread = 0;
  var ringOpaque = 0;
  for (final p in ring) {
    if (p[3] > 250) ringOpaque++;
    final d = chan(p, ringMid);
    if (d > ringSpread) ringSpread = d;
  }

  // A ground is FLAT when the whole border ring is opaque and agrees with its
  // own median. 24 is a deliberately loose bar: it accepts the ringing a lossy
  // export leaves on a solid ground (measured at 12 on the current art) while
  // still rejecting a gradient plate, whose ring spans far more than that.
  final flatGround = ringOpaque == ring.length && ringSpread <= 24;

  stdout.writeln(
      'source        ${args[0]}  ${w}x$h  channels=${src.numChannels}');
  stdout.writeln('border ring   median rgba(${ringMid.join(",")})  '
      'spread $ringSpread  opaque $ringOpaque/${ring.length}');
  stdout.writeln('ground model  ${flatGround ? "FLAT (colour-distance key)" : "GRADIENT PLATE (per-row luminance key)"}');

  double lum(num r, num g, num b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

  final keyed = img.Image(width: w, height: h, numChannels: 4);

  if (flatGround) {
    // ── Flat ground: coverage ramps with distance from the ground colour ───
    // Direction-free, so it keys a white ground and a black one identically.
    // lo sits just above the ring's own measured noise floor, so a lossy
    // export's ringing cannot register as ink and inflate the bounding box.
    final lo = (ringSpread + 2).toDouble(), hi = ringSpread + 60.0;
    stdout.writeln('key ramp      distance ${lo.toStringAsFixed(0)}..'
        '${hi.toStringAsFixed(0)} from rgb(${ringMid[0]},${ringMid[1]},${ringMid[2]})');
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        if (p.a < 8) {
          keyed.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        final d = chan(<num>[p.r, p.g, p.b], ringMid).toDouble();
        final a = ((d - lo) / (hi - lo)).clamp(0.0, 1.0);
        if (a <= 0.001) {
          keyed.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        num r = p.r, g = p.g, bb = p.b;
        if (a > 0.15) {
          // Un-premultiply against the ground so edges are not tinted by it.
          r = ((p.r - (1 - a) * ringMid[0]) / a).clamp(0, 255);
          g = ((p.g - (1 - a) * ringMid[1]) / a).clamp(0, 255);
          bb = ((p.b - (1 - a) * ringMid[2]) / a).clamp(0, 255);
        }
        keyed.setPixelRgba(
            x, y, r.round(), g.round(), bb.round(), (a * 255).round());
      }
    }
  } else {
    // ── Gradient plate: the original path, unchanged ───────────────────────
    // Per-row plate colour. Ink started at x=143 on that art, so x=70 is plate.
    final bgRow = List<List<int>>.generate(h, (y) {
      final p = src.getPixel(70, y);
      return <int>[p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt()];
    });
    int? firstOpaque, lastOpaque;
    for (var y = 0; y < h; y++) {
      if (bgRow[y][3] > 250) {
        firstOpaque ??= y;
        lastOpaque = y;
      }
    }
    for (var y = 0; y < h; y++) {
      if (bgRow[y][3] <= 250) {
        bgRow[y] =
            List<int>.from(bgRow[y < firstOpaque! ? firstOpaque : lastOpaque!]);
      }
    }
    for (var y = 0; y < h; y++) {
      final b = bgRow[y];
      final bl = lum(b[0], b[1], b[2]);
      final lo = bl + 10.0, hi = bl + 70.0;
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        if (p.a < 8) {
          keyed.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        var a = ((lum(p.r, p.g, p.b) - lo) / (hi - lo)).clamp(0.0, 1.0);
        if (a <= 0.001) {
          keyed.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        num r = p.r, g = p.g, bb = p.b;
        if (a > 0.15) {
          r = ((p.r - (1 - a) * b[0]) / a).clamp(0, 255);
          g = ((p.g - (1 - a) * b[1]) / a).clamp(0, 255);
          bb = ((p.b - (1 - a) * b[2]) / a).clamp(0, 255);
        }
        keyed.setPixelRgba(
            x, y, r.round(), g.round(), bb.round(), (a * 255).round());
      }
    }
  }

  // ── Ink bbox + the true max radius of ink from that bbox's centre.
  int x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (keyed.getPixel(x, y).a > 12) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) {
    stderr.writeln('FATAL: the key found no ink at all — the ground model is '
        'wrong for this image. Nothing written.');
    exitCode = 1;
    return;
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

  final crop = img.copyCrop(keyed,
      x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1);
  final nw = (crop.width * s).round(), nh = (crop.height * s).round();
  final scaled = img.copyResize(crop,
      width: nw, height: nh, interpolation: img.Interpolation.cubic);

  final fg = img.Image(width: canvas, height: canvas, numChannels: 4);
  img.compositeImage(fg, scaled,
      dstX: ((canvas - nw) / 2).round(), dstY: ((canvas - nh) / 2).round());

  out.writeAsBytesSync(img.encodePng(fg));

  stdout.writeln('ink bbox      ($x0,$y0)-($x1,$y1)  '
      'centre (${cx.toStringAsFixed(1)},${cy.toStringAsFixed(1)})');
  stdout.writeln('              ${x1 - x0 + 1}x${y1 - y0 + 1}  = '
      '${(100 * (x1 - x0 + 1) / w).toStringAsFixed(1)}% of width, '
      '${(100 * (y1 - y0 + 1) / h).toStringAsFixed(1)}% of height');
  stdout.writeln('max ink radius ${maxR.toStringAsFixed(1)}px  ->  '
      'safe radius ${safeR.toStringAsFixed(1)}px');
  stdout.writeln('scale         ${s.toStringAsFixed(4)}   '
      'artwork ${nw}x$nh on ${canvas}x$canvas transparent');
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
  stdout.writeln('VERIFY        '
      '${(100 * inside / total).toStringAsFixed(2)}% of ink inside the '
      '66/108dp safe circle   ($inside/$total px)');
}
