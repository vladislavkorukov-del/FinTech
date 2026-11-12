import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 1.55: the launch screen writes «Finora». Each letter rises out of a soft
/// blur in turn, then one band of Finora's aqua-and-pink light passes over the
/// word and it settles in calm white. An original treatment drawn in code with
/// the bundled Inter face; no outside artwork or lettering is used.
class FinoraWordmark extends StatefulWidget {
  const FinoraWordmark({super.key, this.size = 64});

  /// Font size of the word.
  final double size;

  static const word = 'Finora';

  /// The whole performance; the app's loading pause is about as long.
  static const duration = Duration(milliseconds: 1500);

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

  /// The iOS sheet curve: a quick start and a long, soft landing.
  static const _settle = Cubic(.32, .72, 0, 1);

  @override
  Widget build(BuildContext context) {
    const letters = FinoraWordmark.word;
    final style = TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: widget.size,
      fontWeight: FontWeight.w600,
      letterSpacing: -widget.size * .03,
      height: 1,
      color: Colors.white,
      decoration: TextDecoration.none,
    );
    return Semantics(
      label: letters,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _play,
        builder: (context, _) {
          final t = _play.value;
          // Letters arrive over the first 70%, 9% of the time apart.
          final row = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < letters.length; i++)
                _letter(letters[i], style, t, i),
            ],
          );
          // The light band crosses from 45% to 95% of the performance.
          final sweep = ((t - .45) / .5).clamp(0.0, 1.0);
          if (sweep <= 0 || sweep >= 1) return row;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              final x = -.6 + 2.2 * Curves.easeInOutCubic.transform(sweep);
              return LinearGradient(
                begin: Alignment(x - .9, -.4),
                end: Alignment(x + .9, .4),
                colors: const [
                  Colors.white,
                  Color(0xFF7FF2DA),
                  Color(0xFFFFB3D1),
                  Colors.white,
                ],
                stops: const [0, .4, .6, 1],
              ).createShader(bounds);
            },
            child: row,
          );
        },
      ),
    );
  }

  Widget _letter(String letter, TextStyle style, double t, int index) {
    final start = index * .09;
    final p = _settle.transform(((t - start) / .45).clamp(0.0, 1.0));
    final blur = (1 - p) * widget.size * .14;
    Widget glyph = Text(letter, style: style);
    if (blur > .2) {
      glyph = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: glyph,
      );
    }
    return Opacity(
      opacity: math.min(1, p * 1.4),
      child: Transform.translate(
        offset: Offset(0, (1 - p) * widget.size * .22),
        child: Transform.scale(scale: .94 + .06 * p, child: glyph),
      ),
    );
  }
}
