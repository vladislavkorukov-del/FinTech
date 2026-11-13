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
  Widget build(BuildContext context) => Column(
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == 1 ? 8 : 0),
                child: FlowSprite(
                  i < session.stars(level)
                      ? 'victory_star_earned'
                      : 'victory_star_empty',
                  width: i == 1 ? 52 : 42,
                  height: i == 1 ? 52 : 42,
                ),
              ),
          ],
        ),
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
              child: SizedBox(height: 32, child: FlowNumber(reward, size: 24)),
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
        const Text('Все 20 уровней пройдены', style: TextStyle(color: flowInk)),
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
