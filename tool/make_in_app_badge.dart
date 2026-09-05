// Regenerates assets/images/logo_badge.png from the brand art.
//
//   dart run tool/make_in_app_badge.dart \
//       assets/images/logo.png assets/images/logo_badge.png
//
// Run this whenever assets/images/logo.png changes.
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Derives the IN-APP circular badge from the flattened brand logo.
///
/// ── Why this is not the launcher's adaptive foreground ────────────────────
/// `tool/make_adaptive_foreground.dart` already derives a circular-safe asset,
/// and the obvious move is to reuse it here. It was tried, built and
/// screenshotted in one of these four frames, and it is wrong for this job on
/// two independent counts:
///
///  1. SCALE. That asset pads its ink to 66/108 of its canvas so it survives
///     whatever mask shape a launcher applies. These frames apply no mask —
///     they are fixed avatar circles that already carry their own padding — so
///     the launcher padding lands on top of the widget's padding and the mark
///     ends up spanning about a third of the circle, floating in empty space.
///
///  2. CONTRAST. That asset's ground is keyed to TRANSPARENT, because the
///     launcher supplies the white back layer separately. Dropped straight
///     onto a dark card the DANLITE wordmark — measured rgb(0,66,143) — sits
///     at roughly 1.7:1 against the surface and is unreadable. The white
///     ground is not decoration; it is what makes the wordmark legible.
///
/// So this produces a self-contained badge: an opaque WHITE DISC filling the
/// square canvas, with the artwork composed on it. Same white ground as the
/// launcher background layer and the API 31+ splash icon disc, so the mark
/// reads identically in all three places rather than gaining a third look.
///
/// ── The one number that sets the composition ──────────────────────────────
/// The launcher icon's ink is guaranteed inside the 66dp safe circle, and the
/// shape it is masked to is 72dp. Its ink therefore fills 66/72 of the circle
/// a rider actually sees. Reusing exactly that ratio here means this badge is
/// composed identically to the launcher icon that was already measured and
/// screenshotted — not to a new number picked by eye.
///
/// Crop + scale + pad only. No artwork is invented or redrawn.
void main(List<String> args) {
  // decodeImage, not decodePng: the brand art is a progressive JPEG carrying a
  // .png name. Same reason make_adaptive_foreground.dart moved off decodePng.
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

  var ringSpread = 0, ringOpaque = 0;
  for (final p in ring) {
    if (p[3] > 250) ringOpaque++;
    final d = chan(p, ringMid);
    if (d > ringSpread) ringSpread = d;
  }
  if (ringOpaque != ring.length || ringSpread > 24) {
    stderr.writeln('FATAL: the border ring is not a flat opaque ground '
        '(opaque $ringOpaque/${ring.length}, spread $ringSpread). This badge '
        'tool only handles flat-ground art. Nothing written.');
    exitCode = 1;
    return;
  }

  stdout.writeln('source        ${args[0]}  ${w}x$h  channels=${src.numChannels}');
  stdout.writeln('border ring   median rgba(${ringMid.join(",")})  '
      'spread $ringSpread  opaque $ringOpaque/${ring.length}');

  // ── Key the ground out so the ink can be measured and re-composed ────────
  // lo sits just above the ring's own measured noise floor, so a lossy
  // export's ringing cannot register as ink and inflate the bounding box.
  final lo = (ringSpread + 2).toDouble(), hi = ringSpread + 60.0;
  stdout.writeln('key ramp      distance ${lo.toStringAsFixed(0)}..'
      '${hi.toStringAsFixed(0)} from rgb(${ringMid[0]},${ringMid[1]},${ringMid[2]})');

  final keyed = img.Image(width: w, height: h, numChannels: 4);
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
        r = ((p.r - (1 - a) * ringMid[0]) / a).clamp(0, 255);
        g = ((p.g - (1 - a) * ringMid[1]) / a).clamp(0, 255);
        bb = ((p.b - (1 - a) * ringMid[2]) / a).clamp(0, 255);
      }
      keyed.setPixelRgba(
          x, y, r.round(), g.round(), bb.round(), (a * 255).round());
    }
  }

  // ── Ink bbox + the true max radius of ink from that bbox's centre ────────
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
    stderr.writeln('FATAL: the key found no ink at all. Nothing written.');
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

  // ── Compose the badge ────────────────────────────────────────────────────
  // 512 is 7.3x the largest frame that renders this (the 70px splash box), so
  // it is downscaled at every use and never upscaled.
  const canvas = 512;
  const discR = canvas / 2.0;
  // 66/72 — the launcher icon's ink fills exactly this fraction of the circle
  // it is masked to. See the doc comment: matching it makes this badge the
  // same composition as the icon that was already verified on device.
  const inkFraction = 66.0 / 72.0;
  final targetInkR = discR * inkFraction;
  final s = targetInkR / maxR;

  final badge = img.Image(width: canvas, height: canvas, numChannels: 4);
  // Opaque white disc, anti-aliased with 4x4 supersampled edge coverage so the
  // rim is smooth against whatever frame colour the widget puts behind it.
  for (var y = 0; y < canvas; y++) {
    for (var x = 0; x < canvas; x++) {
      var hits = 0;
      for (var sy = 0; sy < 4; sy++) {
        for (var sx = 0; sx < 4; sx++) {
          final px = x + (sx + 0.5) / 4.0 - discR;
          final py = y + (sy + 0.5) / 4.0 - discR;
          if (px * px + py * py <= discR * discR) hits++;
        }
      }
      if (hits == 0) continue;
      badge.setPixelRgba(x, y, ringMid[0], ringMid[1], ringMid[2],
          (255 * hits / 16).round());
    }
  }

  final crop = img.copyCrop(keyed,
      x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1);
  final nw = (crop.width * s).round(), nh = (crop.height * s).round();
  final scaled = img.copyResize(crop,
      width: nw, height: nh, interpolation: img.Interpolation.cubic);
  img.compositeImage(badge, scaled,
      dstX: ((canvas - nw) / 2).round(), dstY: ((canvas - nh) / 2).round());

  out.writeAsBytesSync(img.encodePng(badge));

  stdout.writeln('ink bbox      ($x0,$y0)-($x1,$y1)  ${x1 - x0 + 1}x${y1 - y0 + 1}'
      '  max ink radius ${maxR.toStringAsFixed(1)}px');
  stdout.writeln('badge         ${canvas}x$canvas  disc radius '
      '${discR.toStringAsFixed(1)}px  target ink radius '
      '${targetInkR.toStringAsFixed(1)}px (66/72 of the disc)');
  stdout.writeln('scale         ${s.toStringAsFixed(4)}   artwork ${nw}x$nh');
  stdout.writeln('wrote         ${out.path}');

  // ── Verify against the composed badge, not against intent ────────────────
  var inkTotal = 0, inkInside = 0;
  var achievedR = 0.0;
  int ix0 = canvas, iy0 = canvas, ix1 = -1, iy1 = -1;
  var opaque = 0;
  for (var y = 0; y < canvas; y++) {
    for (var x = 0; x < canvas; x++) {
      final p = badge.getPixel(x, y);
      if (p.a >= 250) opaque++;
      // "Ink" in the composed badge = anything that is not the white ground.
      if (p.a <= 12) continue;
      final isInk = chan(<num>[p.r, p.g, p.b], ringMid) > 12;
      if (!isInk) continue;
      inkTotal++;
      if (x < ix0) ix0 = x;
      if (x > ix1) ix1 = x;
      if (y < iy0) iy0 = y;
      if (y > iy1) iy1 = y;
      final d = math.sqrt(
          math.pow(x - discR + 0.5, 2) + math.pow(y - discR + 0.5, 2));
      if (d > achievedR) achievedR = d;
      if (d <= discR) inkInside++;
    }
  }
  stdout.writeln('VERIFY ink    bbox ($ix0,$iy0)-($ix1,$iy1)  '
      '${ix1 - ix0 + 1}x${iy1 - iy0 + 1}  '
      '= ${(100 * (ix1 - ix0 + 1) / canvas).toStringAsFixed(1)}% of the disc '
      'diameter wide, ${(100 * (iy1 - iy0 + 1) / canvas).toStringAsFixed(1)}% tall');
  stdout.writeln('VERIFY fit    ${(100 * inkInside / inkTotal).toStringAsFixed(2)}% '
      'of ink inside the white disc   ($inkInside/$inkTotal px)');
  stdout.writeln('VERIFY radius achieved max ink radius '
      '${achievedR.toStringAsFixed(1)}px = '
      '${(100 * achievedR / discR).toStringAsFixed(1)}% of the disc radius '
      '(target ${(100 * inkFraction).toStringAsFixed(1)}%)');
  stdout.writeln('VERIFY disc   ${(100 * opaque / (canvas * canvas)).toStringAsFixed(2)}% '
      'of the canvas is opaque (a full-bleed disc is pi/4 = 78.54%)');
}
