import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Text;

import '../../../domain/flow/flow.dart';
import '../../l10n_widgets.dart';
import 'flow_art.dart';
import 'flow_hud.dart';

/// All modal content stays over the real map/board and blocks pointer input.
class FlowOverlay extends StatelessWidget {
  const FlowOverlay({
    super.key,
    required this.child,
    this.blur = false,
    this.art = 'out_of_moves_panel_base',
  });
  final Widget child;
  final bool blur;
  final String art;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: blur ? 3 : 0,
              sigmaY: blur ? 3 : 0,
            ),
            child: const ModalBarrier(
              dismissible: false,
              color: Color(0x7A4B2346),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                // 1.60: a compact card, never wider than 360.
                child: SizedBox(
                  width: math.min(
                    360,
                    box.maxWidth * (box.maxWidth < 360 ? .92 : .82),
                  ),
                  // 1.61: the card rises and settles into place.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 340),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, panel) => Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 28 * (1 - t)),
                        child: Transform.scale(
                          scale: .94 + .06 * t,
                          child: panel,
                        ),
                      ),
                    ),
                    child: FlowArtPanel(
                      art: art,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class FlowPauseContent extends StatelessWidget {
  const FlowPauseContent({
    super.key,
    required this.flow,
    required this.onContinue,
    required this.onRestart,
    required this.onExit,
    required this.onMusic,
    required this.onSound,
    required this.onHaptics,
    this.busy = false,
  });
  final FlowProgress flow;
  final VoidCallback onContinue, onRestart, onExit, onMusic, onSound, onHaptics;
  final bool busy;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        header: true,
        label: 'Пауза',
        child: const FlowSprite('pause_title', height: 30),
      ),
      const SizedBox(height: 12),
      FlowArtButton(
        key: const ValueKey('flow-pause-continue'),
        art: 'pause_button_continue',
        label: 'Продолжить',
        onPressed: busy ? null : onContinue,
        width: double.infinity,
        height: 50,
      ),
      const SizedBox(height: 10),
      FlowArtButton(
        key: const ValueKey('flow-pause-restart'),
        art: 'pause_button_restart',
        label: 'Заново',
        onPressed: busy ? null : onRestart,
        width: double.infinity,
        height: 50,
      ),
      const SizedBox(height: 10),
      FlowArtButton(
        key: const ValueKey('flow-pause-exit'),
        art: 'pause_button_exit',
        label: 'Выйти',
        onPressed: busy ? null : onExit,
        width: double.infinity,
        height: 50,
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final item in <(String, String, bool, VoidCallback)>[
            ('music', 'Музыка', flow.music, onMusic),
            ('sound', 'Звуки', flow.sound, onSound),
            ('haptics', 'Вибрация', flow.haptics, onHaptics),
          ])
            Semantics(
              toggled: item.$3,
              child: FlowArtButton(
                key: ValueKey('flow-setting-${item.$1}'),
                art: 'pause_${item.$1}_${item.$3 ? 'on' : 'off'}',
                label: '${item.$2}, ${item.$3 ? 'включены' : 'выключены'}',
                onPressed: busy ? null : item.$4,
                width: 48,
                height: 48,
              ),
            ),
        ],
      ),
    ],
  );
}

class FlowVictoryContent extends StatelessWidget {
  const FlowVictoryContent({
    super.key,
    required this.level,
    required this.session,
    required this.reward,
    required this.onLevels,
    required this.onReplay,
    this.onNext,
    this.onExitWorld,
    this.busy = false,
  });
  final FlowLevel level;
  final FlowSession session;
  final int reward;
  final VoidCallback onLevels, onReplay;
  final VoidCallback? onNext, onExitWorld;
  final bool busy;
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      const Positioned(
        left: -40,
        right: -40,
        top: -60,
        height: 320,
        child: IgnorePointer(child: FlowConfetti()),
      ),
      Column(
        key: const ValueKey('flow-result'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            label: 'Уровень пройден!',
            child: const FlowSprite('victory_title', height: 46),
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Звёзд: ${session.stars(level)} из 3',
            child: FlowVictoryStars(stars: session.stars(level)),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Очки',
            child: const FlowLabel('victory_label_score', capitalHeight: 13),
          ),
          SizedBox(height: 32, child: FlowNumber(session.score, size: 24)),
          const SizedBox(height: 8),
          Semantics(
            label: 'Награда',
            child: const FlowLabel('victory_label_reward', capitalHeight: 13),
          ),
          Semantics(
            label: 'Награда: $reward игровых искр',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const FlowSprite('victory_reward_coin', width: 30, height: 30),
                const SizedBox(width: 8),
                Flexible(
                  child: SizedBox(
                    height: 32,
                    child: FlowNumber(reward, size: 24),
                  ),
                ),
              ],
            ),
          ),
          if (reward == 0)
            const Text(
              'Награда уже получена',
              style: TextStyle(fontSize: 12, color: flowInk),
            ),
          const SizedBox(height: 12),
          if (onNext != null) ...[
            FlowArtButton(
              key: const ValueKey('flow-next'),
              art: 'victory_button_primary_base',
              label: 'Следующий уровень',
              onPressed: busy ? null : onNext,
              width: double.infinity,
              height: 50,
              // 1.60: live text in Finora Potok, like every button in the game.
              child: Text('Дальше', style: flowText(17)),
            ),
            const SizedBox(height: 8),
          ] else
            const Text(
              'Все 20 уровней пройдены',
              style: TextStyle(color: flowInk),
            ),
          FlowArtButton(
            key: const ValueKey('flow-map'),
            art: 'victory_button_secondary_base',
            label: 'К уровням',
            onPressed: busy ? null : onLevels,
            width: double.infinity,
            height: 50,
            // 1.60: live text in Finora Potok, like every button in the game.
            child: Text('К уровням', style: flowText(17)),
          ),
          TextButton(
            key: const ValueKey('flow-replay'),
            onPressed: busy ? null : onReplay,
            child: Text(
              'Повторить уровень',
              style: flowText(14, color: const Color(0xFF27896C)),
            ),
          ),
          if (onExitWorld != null)
            TextButton(
              key: const ValueKey('flow-exit-world'),
              onPressed: busy ? null : onExitWorld,
              child: Text(
                'В Мир Финоры',
                style: flowText(14, color: const Color(0xFF27896C)),
              ),
            ),
        ],
      ),
    ],
  );
}

class FlowLossContent extends StatelessWidget {
  const FlowLossContent({
    super.key,
    required this.level,
    required this.session,
    required this.stock,
    required this.onExtraMoves,
    required this.onRestart,
    required this.onLevels,
    this.busy = false,
  });
  final FlowLevel level;
  final FlowSession session;
  final int stock;
  final VoidCallback onExtraMoves, onRestart, onLevels;
  final bool busy;
  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('flow-result'),
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        header: true,
        label: 'Закончились ходы',
        child: const FlowSprite('out_of_moves_title', height: 46),
      ),
      const SizedBox(height: 12),
      Semantics(
        label: 'Осталось собрать',
        child: const FlowSprite('out_of_moves_label_remaining', height: 18),
      ),
      const SizedBox(height: 12),
      FlowGoals(
        goals: level.goals
            .where((g) => (session.progress[g.key] ?? 0) < g.target)
            .toList(),
        progress: session.progress,
        remaining: true,
        iconSize: 58,
      ),
      const SizedBox(height: 12),
      FlowArtButton(
        key: const ValueKey('flow-extra-moves'),
        art: 'out_of_moves_button_primary_base',
        label: 'Ещё 5 ходов, запас $stock',
        onPressed: busy ? null : onExtraMoves,
        width: double.infinity,
        height: 50,
        // 1.60: live text in Finora Potok, like every button in the game.
        child: Text('Ещё 5 ходов', style: flowText(17)),
      ),
      Text(
        'Запас: $stock',
        style: const TextStyle(fontSize: 12, color: flowInk),
      ),
      const SizedBox(height: 8),
      FlowArtButton(
        key: const ValueKey('flow-replay'),
        art: 'out_of_moves_button_restart_base',
        label: 'Заново',
        onPressed: busy ? null : onRestart,
        width: double.infinity,
        height: 50,
        // 1.60: live text in Finora Potok, like every button in the game.
        child: Text('Заново', style: flowText(17)),
      ),
      const SizedBox(height: 8),
      FlowArtButton(
        key: const ValueKey('flow-map'),
        art: 'out_of_moves_button_levels_base',
        label: 'К уровням',
        onPressed: busy ? null : onLevels,
        width: double.infinity,
        height: 50,
        // 1.60: live text in Finora Potok, like every button in the game.
        child: Text('К уровням', style: flowText(17)),
      ),
    ],
  );
}

/// 1.61: the three stars arrive one after another and the earned ones pop.
class FlowVictoryStars extends StatefulWidget {
  const FlowVictoryStars({super.key, required this.stars});
  final int stars;
  @override
  State<FlowVictoryStars> createState() => _FlowVictoryStarsState();
}

class _FlowVictoryStarsState extends State<FlowVictoryStars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++)
          Builder(
            builder: (context) {
              final start = .12 + i * .2;
              final p = ((_c.value - start) / .4).clamp(0.0, 1.0);
              final earned = i < widget.stars;
              final scale = earned
                  ? Curves.easeOutBack.transform(p)
                  : Curves.easeOutCubic.transform(p);
              final size = i == 1 ? 52.0 : 42.0;
              return Padding(
                padding: EdgeInsets.only(bottom: i == 1 ? 8 : 0),
                child: Opacity(
                  opacity: p,
                  child: Transform.rotate(
                    angle: earned ? (1 - p) * -.6 : 0,
                    child: Transform.scale(
                      scale: (earned ? .2 : .7) + (earned ? .8 : .3) * scale,
                      child: FlowSprite(
                        earned ? 'victory_star_earned' : 'victory_star_empty',
                        width: size,
                        height: size,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}

/// 1.61: a short shower of confetti in the game's colors behind a victory.
class FlowConfetti extends StatefulWidget {
  const FlowConfetti({super.key});
  @override
  State<FlowConfetti> createState() => _FlowConfettiState();
}

class _FlowConfettiState extends State<FlowConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => _c.value >= 1
        ? const SizedBox.shrink()
        : CustomPaint(painter: _ConfettiPainter(_c.value)),
  );
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.t);
  final double t;
  static const _colors = [
    Color(0xFFFFC93C),
    Color(0xFF3FD6EA),
    Color(0xFFFF7FB0),
    Color(0xFF7AE0B8),
    Color(0xFFA77BF6),
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final origin = Offset(size.width / 2, size.height * .32);
    for (var i = 0; i < 46; i++) {
      final angle = -math.pi / 2 + (rng.nextDouble() - .5) * math.pi * 1.1;
      final speed = size.width * (.45 + rng.nextDouble() * .55);
      final spin = rng.nextDouble() * math.pi * 6;
      final delay = rng.nextDouble() * .12;
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final x = origin.dx + math.cos(angle) * speed * p;
      final y =
          origin.dy + math.sin(angle) * speed * p + size.height * 1.1 * p * p;
      final fade = (1 - p).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin * p);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 4.5),
          const Radius.circular(1.5),
        ),
        Paint()..color = _colors[i % _colors.length].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
