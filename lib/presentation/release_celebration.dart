import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../domain/app_version.dart';
import 'controller.dart';
import 'haptics.dart';
import 'l10n_widgets.dart';
import 'widgets/finora_orb.dart';
import 'widgets/motion.dart';

/// Finora Release 1.0.0: the first launch of the release is a celebration —
/// confetti, Finora glad to see you, and a few words about what the app is
/// now. Shown once (after onboarding), then never again.
abstract final class ReleaseCelebration {
  static bool _open = false;

  /// Off in widget tests that do not test it (they open the app with data
  /// of their own and would see the celebration first).
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// Shows the celebration once; true when it was shown.
  static Future<bool> check(BuildContext context) async {
    final c = FinanceScope.of(context);
    final p = c.data.preferences;
    if (!enabled ||
        _open ||
        !p.onboarded ||
        p.releaseCelebrated ||
        c.data.demo) {
      return false;
    }
    _open = true;
    try {
      unawaited(Haptics.success());
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, _, _) => const ReleaseScreen(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
      // The release is told here: no separate «Что нового» right after.
      await c.mutate(
        (d) => d.copyWith(
          preferences: d.preferences.copyWith(
            releaseCelebrated: true,
            seenVersion: appVersion,
          ),
        ),
      );
      return true;
    } finally {
      _open = false;
    }
  }
}

/// The celebration itself.
class ReleaseScreen extends StatefulWidget {
  const ReleaseScreen({super.key});

  @override
  State<ReleaseScreen> createState() => _ReleaseScreenState();
}

class _ReleaseScreenState extends State<ReleaseScreen>
    with SingleTickerProviderStateMixin {
  late final _confetti = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  final _pieces = List.generate(90, (i) => _Piece(math.Random(i * 7919 + 1)));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambient(context)) {
      if (!_confetti.isAnimating) unawaited(_confetti.repeat());
    } else {
      _confetti.value = .35;
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const points = [
      (
        Icons.account_balance_wallet_rounded,
        'Счета, бюджеты и мечты — всё под рукой',
      ),
      (Icons.mic_rounded, 'Голосом и по скриншоту — запись за секунды'),
      (Icons.emoji_events_rounded, 'Достижения за порядок в деньгах'),
      (
        Icons.face_retouching_natural_rounded,
        'Финора — с эмоциями или сферой света, как вам нравится',
      ),
    ];
    return Scaffold(
      key: const ValueKey('release-celebration'),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1630), Color(0xFF14284A), Color(0xFF0B1630)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) => CustomPaint(
                    painter: _ConfettiPainter(_pieces, _confetti.value),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FinoraCharacter(
                          size: 150,
                          moods: [
                            FinoraMood.delight,
                            FinoraMood.happy,
                            FinoraMood.wink,
                          ],
                          loop: true,
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'РЕЛИЗ',
                          style: TextStyle(
                            color: Color(0xFF8FF3DE),
                            fontSize: 13,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          appName,
                          key: ValueKey('release-title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Версия $appVersion',
                          style: TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Это первый большой релиз Финоры. Спасибо, что были рядом всё это время — дальше будет только лучше!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 22),
                        for (final (icon, text) in points)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Icon(
                                    icon,
                                    color: const Color(0xFF8FF3DE),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    text,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            key: const ValueKey('release-start'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3FE0C2),
                              foregroundColor: const Color(0xFF06231E),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              Haptics.light();
                              Navigator.of(context).pop();
                            },
                            child: const Text(
                              'Поехали!',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One piece of confetti: where it starts, how it falls and turns.
class _Piece {
  _Piece(math.Random r)
    : x = r.nextDouble(),
      delay = r.nextDouble(),
      speed = .6 + r.nextDouble() * .7,
      drift = (r.nextDouble() - .5) * .12,
      spin = (r.nextDouble() - .5) * 14,
      size = 5 + r.nextDouble() * 7,
      color = const [
        Color(0xFF3FE0C2),
        Color(0xFFFFC94D),
        Color(0xFFFF6FA8),
        Color(0xFF7FA8FF),
        Color(0xFFB98BFF),
        Color(0xFFFFFFFF),
      ][r.nextInt(6)],
      round = r.nextBool();
  final double x, delay, speed, drift, spin, size;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final f = (t * p.speed + p.delay) % 1;
      final y = -20 + f * (size.height + 40);
      final x =
          p.x * size.width +
          math.sin(f * math.pi * 4 + p.delay * 9) * 18 +
          p.drift * size.width * f;
      final paint = Paint()..color = p.color.withValues(alpha: .9);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(p.spin * f);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * .4, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * .45,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
