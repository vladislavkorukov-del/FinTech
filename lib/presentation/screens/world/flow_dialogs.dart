import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Text;

import '../../../domain/flow/flow.dart';
import '../../l10n_widgets.dart';
import 'flow_art.dart';
import 'flow_hud.dart';

part 'flow_dialogs_fx.dart';

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
                // 1.62: about 78% of the phone (the packs' 72–80%), never
                // wider than 360; a little wider on very narrow phones.
                child: SizedBox(
                  width: math.min(
                    360,
                    box.maxWidth * (box.maxWidth < 340 ? .9 : .78),
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
      Semantics(header: true, child: Text('Пауза', style: FlowType.title)),
      const SizedBox(height: 12),
      FlowArtButton(
        key: const ValueKey('flow-pause-continue'),
        art: 'victory_button_primary_base',
        label: 'Продолжить',
        onPressed: busy ? null : onContinue,
        width: double.infinity,
        height: 50,
        child: const FlowButtonText('Продолжить'),
      ),
      const SizedBox(height: 10),
      FlowArtButton(
        key: const ValueKey('flow-pause-restart'),
        art: 'out_of_moves_button_restart_base',
        label: 'Заново',
        onPressed: busy ? null : onRestart,
        width: double.infinity,
        height: 50,
        child: const FlowButtonText('Заново'),
      ),
      const SizedBox(height: 10),
      FlowArtButton(
        key: const ValueKey('flow-pause-exit'),
        art: 'victory_button_secondary_base',
        label: 'Выйти',
        onPressed: busy ? null : onExit,
        width: double.infinity,
        height: 50,
        child: const FlowButtonText('Выйти'),
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
            child: Text(
              'Уровень пройден!',
              textAlign: TextAlign.center,
              style: FlowType.title,
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Звёзд: ${session.stars(level)} из 3',
            child: FlowVictoryStars(stars: session.stars(level)),
          ),
          const SizedBox(height: 12),
          Text('Очки', style: FlowType.heading),
          SizedBox(height: 38, child: FlowNumber(session.score, size: 30)),
          const SizedBox(height: 8),
          Text('Награда', style: FlowType.heading),
          Semantics(
            label: 'Награда: $reward игровых искр',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const FlowSprite('victory_reward_coin', width: 36, height: 36),
                const SizedBox(width: 8),
                Flexible(
                  child: SizedBox(
                    height: 38,
                    child: FlowNumber(reward, size: 30),
                  ),
                ),
              ],
            ),
          ),
          if (reward == 0) Text('Награда уже получена', style: FlowType.body),
          const SizedBox(height: 12),
          if (onNext != null) ...[
            FlowArtButton(
              key: const ValueKey('flow-next'),
              art: 'victory_button_primary_base',
              label: 'Следующий уровень',
              onPressed: busy ? null : onNext,
              width: double.infinity,
              height: 52,
              child: const FlowButtonText('Дальше'),
            ),
            const SizedBox(height: 8),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Все 20 уровней пройдены',
                textAlign: TextAlign.center,
                style: FlowType.body,
              ),
            ),
          FlowArtButton(
            key: const ValueKey('flow-map'),
            art: 'victory_button_secondary_base',
            label: 'К уровням',
            onPressed: busy ? null : onLevels,
            width: double.infinity,
            height: 52,
            child: const FlowButtonText('К уровням'),
          ),
          const SizedBox(height: 8),
          // 1.63: all four actions on empty library bases, one live style.
          _VictorySecondary(
            buttonKey: const ValueKey('flow-replay'),
            text: 'Повторить уровень',
            onPressed: busy ? null : onReplay,
          ),
          if (onExitWorld != null) ...[
            const SizedBox(height: 6),
            _VictorySecondary(
              buttonKey: const ValueKey('flow-exit-world'),
              text: 'В Мир Финоры',
              onPressed: busy ? null : onExitWorld,
            ),
          ],
        ],
      ),
    ],
  );
}

class _VictorySecondary extends StatelessWidget {
  const _VictorySecondary({
    required this.buttonKey,
    required this.text,
    required this.onPressed,
  });
  final Key buttonKey;
  final String text;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FlowArtButton(
    key: buttonKey,
    art: 'victory_button_secondary_base',
    label: text,
    onPressed: onPressed,
    width: double.infinity,
    height: 48,
    child: FlowButtonText(text),
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
        child: Text(
          'Закончились ходы',
          textAlign: TextAlign.center,
          style: FlowType.title,
        ),
      ),
      const SizedBox(height: 12),
      Text('Осталось собрать', style: FlowType.heading),
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
        child: const FlowButtonText('Ещё 5 ходов'),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('Запас: $stock', style: FlowType.body),
      ),
      const SizedBox(height: 8),
      FlowArtButton(
        key: const ValueKey('flow-replay'),
        art: 'out_of_moves_button_restart_base',
        label: 'Заново',
        onPressed: busy ? null : onRestart,
        width: double.infinity,
        height: 50,
        child: const FlowButtonText('Заново'),
      ),
      const SizedBox(height: 8),
      FlowArtButton(
        key: const ValueKey('flow-map'),
        art: 'out_of_moves_button_levels_base',
        label: 'К уровням',
        onPressed: busy ? null : onLevels,
        width: double.infinity,
        height: 50,
        child: const FlowButtonText('К уровням'),
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
              final size = i == 1 ? 66.0 : 54.0;
              return Padding(
                padding: EdgeInsets.only(bottom: i == 1 ? 10 : 0),
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
