import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The launch screen draws «Finora» in the side panel's serif, the way a new
/// phone greets you: a thin line of light traces every letter in turn, a
/// soft glow follows the pen, then the strokes fill in and the word settles
/// in calm white.
///
/// The letter outlines are Noto Serif Medium (SIL Open Font License), the
/// face Android uses for the panel's «Finora», so both words match.
class FinoraWordmark extends StatefulWidget {
  const FinoraWordmark({super.key, this.size = 64});

  /// Font size of the word.
  final double size;

  static const word = 'Finora';

  /// The whole performance; the app's loading pause is about as long.
  static const duration = Duration(milliseconds: 2400);

  @override
  State<FinoraWordmark> createState() => _FinoraWordmarkState();
}

class _FinoraWordmarkState extends State<FinoraWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: FinoraWordmark.duration,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _play.value = 1;
    } else {
      _play.forward();
    }
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _Glyphs.bounds;
    final scale = widget.size / 1000;
    return Semantics(
      label: FinoraWordmark.word,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('finora-wordmark'),
          size: Size(
            bounds.width * scale + widget.size * .3,
            bounds.height * scale + widget.size * .3,
          ),
          painter: _WordPainter(_play),
        ),
      ),
    );
  }
}

class _WordPainter extends CustomPainter {
  _WordPainter(this.play) : super(repaint: play);
  final Animation<double> play;

  static const _ink = [
    Color(0xFF7FF2DA),
    Color(0xFFFFFFFF),
    Color(0xFFFFB3D1),
    Color(0xFFFFC27A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = play.value;
    final b = _Glyphs.bounds;
    final settle = Curves.easeOutCubic.transform(t);
    final k = math.min(size.width / b.width, size.height / b.height) * .86;
    final s = k * (.965 + .035 * settle);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(s)
      ..translate(-b.center.dx, -b.center.dy);

    final shader = ui.Gradient.linear(
      Offset(b.left, b.top),
      Offset(b.right, b.bottom),
      _ink,
      const [0, .35, .7, 1],
    );
    // The strokes fill in over the last part of the performance.
    final fill = Curves.easeInOutCubic.transform(
      ((t - .58) / .34).clamp(0.0, 1.0),
    );
    final line = 1.7 / s;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = line * 5
      ..shader = shader
      ..color = Colors.white.withValues(alpha: .35 * (1 - fill))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, line * 3);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = line
      ..shader = shader
      ..color = Colors.white.withValues(alpha: 1 - fill * .85);

    for (var i = 0; i < _Glyphs.letters.length; i++) {
      // Each letter is traced in turn, overlapping the next a little.
      final p = Curves.easeInOutSine.transform(
        ((t - i * .07) / .42).clamp(0.0, 1.0),
      );
      if (p <= 0) continue;
      final letter = _Glyphs.letters[i];
      if (fill > 0) {
        canvas.drawPath(
          letter,
          Paint()
            ..color = Color.lerp(const Color(0x00FFFFFF), Colors.white, fill)!,
        );
      }
      final traced = p >= 1 ? letter : _trace(letter, p);
      if (fill < 1) canvas.drawPath(traced, glow);
      canvas.drawPath(traced, pen);
    }
    canvas.restore();
  }

  /// The first [p] of every outline of the letter.
  static Path _trace(Path letter, double p) {
    final out = Path();
    for (final m in letter.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * p), Offset.zero);
    }
    return out;
  }

  @override
  bool shouldRepaint(_WordPainter old) => old.play != play;
}

/// «Finora» as outlines, one path per letter, in font units (1000 per em).
abstract final class _Glyphs {
  static final letters = [for (final d in _data) _parse(d)];

  static final bounds = letters
      .map((p) => p.getBounds())
      .reduce((a, b) => a.expandToInclude(b));

  static Path _parse(String d) {
    final path = Path();
    final parts = d.split(' ');
    var i = 0;
    double n() => double.parse(parts[i++]);
    while (i < parts.length) {
      switch (parts[i++]) {
        case 'M':
          path.moveTo(n(), n());
        case 'L':
          path.lineTo(n(), n());
        case 'Q':
          path.quadraticBezierTo(n(), n(), n(), n());
        case 'C':
          path.cubicTo(n(), n(), n(), n(), n(), n());
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  static const _data = [
    'M 35 0 L 35 -45 L 56 -45 Q 76 -45 92 -50 Q 109 -54 120 -68 Q 130 -82 130 -110 L 130 -603 Q 130 -632 120 -646 Q 109 -660 92 -664 Q 76 -669 56 -669 L 35 -669 L 35 -714 L 553 -714 L 558 -537 L 501 -537 L 496 -581 Q 492 -617 472 -639 Q 452 -661 409 -661 L 246 -661 L 246 -376 L 486 -376 L 486 -325 L 246 -325 L 246 -115 Q 246 -85 256 -70 Q 266 -55 283 -50 Q 300 -45 320 -45 L 361 -45 L 361 0 Z',
    'M 620 0 L 620 -45 L 633 -45 Q 653 -45 671 -50 Q 689 -54 700 -68 Q 712 -83 712 -111 L 712 -425 Q 712 -454 700 -468 Q 689 -482 671 -486 Q 653 -491 633 -491 L 628 -491 L 628 -536 L 822 -536 L 822 -115 Q 822 -85 833 -70 Q 844 -55 862 -50 Q 881 -45 901 -45 L 914 -45 L 914 0 Z M 763 -633 Q 735 -633 716 -648 Q 698 -663 698 -698 Q 698 -734 717 -748 Q 736 -763 763 -763 Q 789 -763 808 -748 Q 828 -734 828 -698 Q 828 -663 808 -648 Q 789 -633 763 -633 Z',
    'M 954 0 L 954 -45 L 960 -45 Q 983 -45 1002 -50 Q 1020 -55 1030 -70 Q 1041 -86 1041 -116 L 1041 -424 Q 1041 -453 1030 -468 Q 1020 -482 1002 -486 Q 985 -491 963 -491 L 959 -491 L 959 -536 L 1134 -536 L 1147 -458 L 1152 -458 Q 1173 -496 1196 -515 Q 1220 -534 1248 -540 Q 1275 -547 1307 -547 Q 1386 -547 1430 -500 Q 1474 -454 1474 -352 L 1474 -117 Q 1474 -86 1483 -70 Q 1492 -55 1508 -50 Q 1525 -45 1547 -45 L 1552 -45 L 1552 0 L 1364 0 L 1364 -341 Q 1364 -406 1342 -442 Q 1319 -477 1263 -477 Q 1221 -477 1196 -455 Q 1172 -433 1162 -396 Q 1151 -359 1151 -317 L 1151 -111 Q 1151 -83 1162 -68 Q 1172 -54 1190 -50 Q 1207 -45 1229 -45 L 1233 -45 L 1233 0 Z',
    'M 1871 10 Q 1760 10 1696 -59 Q 1632 -128 1632 -269 Q 1632 -410 1693 -478 Q 1754 -547 1874 -547 Q 1985 -547 2049 -478 Q 2113 -410 2113 -269 Q 2113 -128 2052 -59 Q 1990 10 1871 10 Z M 1873 -45 Q 1920 -45 1948 -70 Q 1976 -95 1988 -146 Q 2000 -196 2000 -269 Q 2000 -380 1971 -436 Q 1942 -491 1872 -491 Q 1802 -491 1774 -436 Q 1745 -380 1745 -269 Q 1745 -159 1774 -102 Q 1803 -45 1873 -45 Z',
    'M 2195 0 L 2195 -45 L 2198 -45 Q 2221 -45 2240 -50 Q 2258 -55 2268 -70 Q 2279 -86 2279 -117 L 2279 -423 Q 2279 -453 2268 -468 Q 2257 -482 2240 -486 Q 2222 -491 2200 -491 L 2197 -491 L 2197 -536 L 2364 -536 L 2383 -443 L 2388 -443 Q 2401 -473 2416 -496 Q 2432 -520 2458 -534 Q 2483 -547 2526 -547 Q 2582 -547 2609 -527 Q 2636 -507 2636 -471 Q 2636 -436 2612 -414 Q 2587 -393 2534 -393 Q 2534 -421 2529 -438 Q 2524 -456 2513 -464 Q 2502 -473 2482 -473 Q 2455 -473 2436 -452 Q 2418 -431 2408 -399 Q 2398 -367 2394 -333 Q 2389 -299 2389 -273 L 2389 -112 Q 2389 -83 2400 -68 Q 2411 -54 2428 -50 Q 2446 -45 2468 -45 L 2497 -45 L 2497 0 Z',
    'M 2855 10 Q 2811 10 2776 -8 Q 2740 -25 2720 -60 Q 2700 -96 2700 -151 Q 2700 -231 2756 -270 Q 2812 -308 2927 -312 L 3009 -315 L 3009 -373 Q 3009 -409 3004 -436 Q 2998 -463 2980 -478 Q 2962 -494 2925 -494 Q 2890 -494 2872 -480 Q 2853 -466 2846 -442 Q 2840 -417 2840 -385 Q 2792 -385 2767 -400 Q 2742 -414 2742 -449 Q 2742 -485 2768 -506 Q 2793 -527 2836 -537 Q 2878 -547 2929 -547 Q 3024 -547 3072 -508 Q 3119 -469 3119 -375 L 3119 -117 Q 3119 -89 3125 -74 Q 3131 -58 3145 -52 Q 3159 -45 3181 -45 L 3184 -45 L 3184 0 L 3035 0 L 3018 -81 L 3009 -81 Q 2988 -54 2968 -34 Q 2948 -13 2922 -2 Q 2896 10 2855 10 Z M 2887 -55 Q 2925 -55 2952 -72 Q 2979 -88 2994 -119 Q 3009 -150 3009 -191 L 3009 -270 L 2950 -267 Q 2898 -265 2868 -250 Q 2838 -236 2826 -210 Q 2813 -184 2813 -146 Q 2813 -116 2821 -96 Q 2829 -75 2846 -65 Q 2862 -55 2887 -55 Z',
  ];
}
