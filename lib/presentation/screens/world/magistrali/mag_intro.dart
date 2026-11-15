import 'package:flutter/material.dart' hide Text;

import '../../../l10n_widgets.dart';

/// The way into the game (S20+): the title over a dark veil that lifts
/// and lets the map in. It never takes a touch.
class MagIntro extends StatefulWidget {
  const MagIntro({super.key, required this.subtitle});
  final String subtitle;

  @override
  State<MagIntro> createState() => _MagIntroState();
}

class _MagIntroState extends State<MagIntro>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        if (t >= 1) return const SizedBox.shrink();
        final veil =
            1 - Curves.easeInCubic.transform(((t - .35) / .65).clamp(0.0, 1.0));
        final rise = Curves.easeOutCubic.transform((t / .4).clamp(0.0, 1.0));
        return Container(
          key: const ValueKey('mag-intro'),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.1,
              colors: [
                Color.fromRGBO(16, 44, 40, .78 * veil),
                Color.fromRGBO(8, 20, 18, .94 * veil),
              ],
            ),
          ),
          child: Opacity(
            opacity: (veil * 1.4).clamp(0.0, 1.0) * rise,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - rise)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'FINORA',
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8FE3CF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'МАГИСТРАЛИ',
                    style: TextStyle(
                      fontSize: 34,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: Color(0x662BB59A), blurRadius: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 64 * rise,
                    height: 2,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x002BB59A),
                          Color(0xFF2BB59A),
                          Color(0x002BB59A),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xCCFFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
