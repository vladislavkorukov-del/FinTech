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
                child: SizedBox(
                  width: math.min(
                    430,
                    box.maxWidth * (box.maxWidth < 360 ? .90 : .84),
                  ),
                  child: FlowArtPanel(
                    art: art,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
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
        child: const FlowSprite('pause_title', height: 36),
      ),
      const SizedBox(height: 18),
      FlowArtButton(
        key: const ValueKey('flow-pause-continue'),
        art: 'pause_button_continue',
        label: 'Продолжить',
        onPressed: busy ? null : onContinue,
        width: double.infinity,
        height: 56,
      ),
      const SizedBox(height: 10),
      FlowArtButton(
        key: const ValueKey('flow-pause-restart'),
        art: 'pause_button_restart',
        label: 'Заново',
        onPressed: busy ? null : onRestart,
        width: double.infinity,
        height: 56,
      ),
      const SizedBox(height: 10),
      FlowArtButton(
        key: const ValueKey('flow-pause-exit'),
        art: 'pause_button_exit',
        label: 'Выйти',
        onPressed: busy ? null : onExit,
        width: double.infinity,
        height: 56,
      ),
      const SizedBox(height: 16),
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
        child: const FlowSprite('victory_title', height: 60),
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
                  width: i == 1 ? 64 : 52,
                  height: i == 1 ? 64 : 52,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Semantics(
        label: 'Очки',
        child: const FlowLabel('victory_label_score', capitalHeight: 16),
      ),
      SizedBox(height: 42, child: FlowNumber(session.score, size: 30)),
      const SizedBox(height: 8),
      Semantics(
        label: 'Награда',
        child: const FlowLabel('victory_label_reward', capitalHeight: 16),
      ),
      Semantics(
        label: 'Награда: $reward игровых искр',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FlowSprite('victory_reward_coin', width: 38, height: 38),
            const SizedBox(width: 8),
            Flexible(
              child: SizedBox(height: 42, child: FlowNumber(reward, size: 30)),
            ),
          ],
        ),
      ),
      if (reward == 0)
        const Text(
          'Награда уже получена',
          style: TextStyle(fontSize: 12, color: flowInk),
        ),
      const SizedBox(height: 16),
      if (onNext != null) ...[
        FlowArtButton(
          key: const ValueKey('flow-next'),
          art: 'victory_button_primary_base',
          labelArt: 'victory_label_next',
          label: 'Следующий уровень',
          onPressed: busy ? null : onNext,
          width: double.infinity,
          height: 56,
        ),
        const SizedBox(height: 8),
      ] else
        const Text('Все 20 уровней пройдены', style: TextStyle(color: flowInk)),
      FlowArtButton(
        key: const ValueKey('flow-map'),
        art: 'victory_button_secondary_base',
        labelArt: 'victory_label_levels',
        label: 'К уровням',
        onPressed: busy ? null : onLevels,
        width: double.infinity,
        height: 56,
      ),
      TextButton(
        key: const ValueKey('flow-replay'),
        onPressed: busy ? null : onReplay,
        child: const Text('Повторить уровень'),
      ),
      if (onExitWorld != null)
        TextButton(
          key: const ValueKey('flow-exit-world'),
          onPressed: busy ? null : onExitWorld,
          child: const Text('В Мир Финоры'),
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
        child: const FlowSprite('out_of_moves_title', height: 62),
      ),
      const SizedBox(height: 16),
      Semantics(
        label: 'Осталось собрать',
        child: const FlowSprite('out_of_moves_label_remaining', height: 22),
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
      const SizedBox(height: 16),
      FlowArtButton(
        key: const ValueKey('flow-extra-moves'),
        art: 'out_of_moves_button_primary_base',
        labelArt: 'out_of_moves_label_extra_moves',
        label: 'Ещё 5 ходов, запас $stock',
        onPressed: busy ? null : onExtraMoves,
        width: double.infinity,
        height: 56,
      ),
      Text(
        'Запас: $stock',
        style: const TextStyle(fontSize: 12, color: flowInk),
      ),
      const SizedBox(height: 8),
      FlowArtButton(
        key: const ValueKey('flow-replay'),
        art: 'out_of_moves_button_restart_base',
        labelArt: 'out_of_moves_label_restart',
        label: 'Заново',
        onPressed: busy ? null : onRestart,
        width: double.infinity,
        height: 56,
      ),
      const SizedBox(height: 8),
      FlowArtButton(
        key: const ValueKey('flow-map'),
        art: 'out_of_moves_button_levels_base',
        labelArt: 'out_of_moves_label_levels',
        label: 'К уровням',
        onPressed: busy ? null : onLevels,
        width: double.infinity,
        height: 56,
      ),
    ],
  );
}
