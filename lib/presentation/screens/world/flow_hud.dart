import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:intl/intl.dart';

import '../../../domain/flow/flow.dart';
import '../../l10n_widgets.dart';
import 'flow_art.dart';

const flowInk = Color(0xFF4B1038);
String flowNumber(int value) => NumberFormat.decimalPattern('ru').format(value);
String flowToolName(FlowTool tool) => switch (tool) {
  FlowTool.hammer => 'Молоток',
  FlowTool.bomb => 'Бомба',
  FlowTool.shuffle => 'Перемешивание',
  FlowTool.extraMoves => 'Пять дополнительных ходов',
};
String flowToolArt(FlowTool tool) => switch (tool) {
  FlowTool.hammer => 'booster_hammer',
  FlowTool.bomb => 'booster_bomb',
  FlowTool.shuffle => 'booster_shuffle',
  FlowTool.extraMoves => 'booster_extra_moves',
};

class FlowNumber extends StatelessWidget {
  const FlowNumber(this.value, {super.key, this.size = 24});
  final int value;
  final double size;
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      flowNumber(value),
      style: TextStyle(
        fontFamily: 'sans-serif',
        color: flowInk,
        fontSize: size,
        fontWeight: FontWeight.w900,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

class FlowGoalIcon extends StatelessWidget {
  const FlowGoalIcon(this.goalKey, {super.key, this.size = 42});
  final String goalKey;
  final double size;
  @override
  Widget build(BuildContext context) {
    final id = switch (goalKey) {
      'ice' => 'obstacle_ice_intact',
      'chain' => 'obstacle_chain_intact',
      'crate' => 'obstacle_crate_intact',
      'stack' => 'match3_receipt',
      _ => 'match3_${goalKey.split(':').last}',
    };
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          if (goalKey == 'ice' || goalKey == 'chain')
            const Positioned.fill(
              child: FlowSprite('match3_coin', trim: false),
            ),
          Positioned.fill(child: FlowSprite(id, trim: false)),
        ],
      ),
    );
  }
}

class FlowGoals extends StatelessWidget {
  const FlowGoals({
    super.key,
    required this.goals,
    this.progress = const {},
    this.remaining = false,
    this.iconSize = 42,
  });
  final List<FlowGoal> goals;
  final Map<String, int> progress;
  final bool remaining;
  final double iconSize;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = math.min(goals.length, 3);
      final width = (box.maxWidth / math.max(1, count)).clamp(38.0, 112.0);
      return Wrap(
        alignment: WrapAlignment.center,
        runSpacing: 6,
        children: [
          for (final goal in goals)
            SizedBox(
              width: width,
              child: Semantics(
                label:
                    '${goal.title}: ${remaining ? math.max(0, goal.target - (progress[goal.key] ?? 0)) : goal.target}',
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FlowGoalIcon(goal.key, size: iconSize),
                      SizedBox(
                        height: (iconSize * .6).clamp(16, 25),
                        child: FlowNumber(
                          remaining
                              ? math.max(
                                  0,
                                  goal.target - (progress[goal.key] ?? 0),
                                )
                              : goal.target,
                          size: (iconSize * .5).clamp(12, 21),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class FlowTopHud extends StatelessWidget {
  const FlowTopHud({
    super.key,
    required this.level,
    required this.session,
    required this.onPause,
  });
  final FlowLevel level;
  final FlowSession session;
  final VoidCallback? onPause;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      final cardHeight = (w * .28).clamp(58.0, 106.0);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned.fill(
                        child: FlowSprite('hud_level_header', fit: BoxFit.fill),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: FlowSprite(
                                'hud_level_label',
                                width: math.min(112, w * .36),
                                height: 26,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: FlowNumber(level.id, size: 25)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                FlowArtButton(
                  key: const ValueKey('flow-pause'),
                  art: 'hud_pause_button',
                  label: 'Пауза',
                  onPressed: onPause,
                  width: 48,
                  height: 48,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: cardHeight,
            child: Row(
              children: [
                SizedBox(
                  width: w * .27,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: FlowSprite('hud_moves_card', fit: BoxFit.fill),
                      ),
                      Positioned.fill(
                        top: cardHeight * .36,
                        bottom: cardHeight * .10,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Semantics(
                            label: 'Ходы: ${session.remainingMoves}',
                            child: FlowNumber(session.remainingMoves, size: 40),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: w * .025),
                Expanded(
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: FlowSprite('hud_goals_card', fit: BoxFit.fill),
                      ),
                      Positioned.fill(
                        top: cardHeight * .27,
                        bottom: 3,
                        left: 6,
                        right: 6,
                        child: FlowGoals(
                          goals: level.goals,
                          progress: session.progress,
                          remaining: true,
                          iconSize: math.min(42, cardHeight * .38),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                SizedBox(
                  width: w < 260 ? 48 : 64,
                  child: Semantics(
                    label: 'Счёт: ${session.score}',
                    child: FlowNumber(session.score, size: 19),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FlowScoreTrack(
                    score: session.score,
                    thresholds: level.scoreThresholds,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class FlowScoreTrack extends StatelessWidget {
  const FlowScoreTrack({
    super.key,
    required this.score,
    required this.thresholds,
  });
  final int score;
  final List<int> thresholds;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final maximum = math.max(1, thresholds.last);
      final value = (score / maximum).clamp(0.0, 1.0);
      return Semantics(
        label: 'Прогресс звёзд: $score из $maximum',
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Positioned(
              left: 0,
              right: 0,
              top: 11,
              height: 14,
              child: FlowSprite('hud_progress_track', fit: BoxFit.fill),
            ),
            Positioned(
              left: 2,
              right: 2,
              top: 13,
              height: 10,
              child: ClipRect(
                key: const ValueKey('flow-score-fill'),
                clipper: _ProgressClipper(value),
                child: const FlowSprite('hud_progress_fill', fit: BoxFit.fill),
              ),
            ),
            for (final threshold in thresholds)
              Positioned(
                left: ((threshold / maximum) * (box.maxWidth - 22)).clamp(
                  0,
                  box.maxWidth - 22,
                ),
                top: 5,
                width: 24,
                height: 24,
                child: FlowSprite(
                  score >= threshold ? 'hud_star_active' : 'hud_star_inactive',
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _ProgressClipper extends CustomClipper<Rect> {
  const _ProgressClipper(this.value);
  final double value;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * value, size.height);
  @override
  bool shouldReclip(_ProgressClipper oldClipper) => value != oldClipper.value;
}

class FlowBottomTools extends StatelessWidget {
  const FlowBottomTools({
    super.key,
    required this.flow,
    required this.onUse,
    required this.onMore,
    this.selected,
    this.enabled = true,
    this.columns = 4,
  });
  final FlowProgress flow;
  final ValueChanged<FlowTool> onUse, onMore;
  final FlowTool? selected;
  final bool enabled;
  final int columns;
  @override
  Widget build(BuildContext context) => FlowArtPanel(
    art: 'bottom_panel_base',
    padding: const EdgeInsets.all(6),
    child: LayoutBuilder(
      builder: (context, box) => Wrap(
        children: [
          for (final tool in FlowTool.values)
            SizedBox(
              width: box.maxWidth / columns,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: FlowSprite('booster_slot', fit: BoxFit.fill),
                    ),
                    if (selected == tool)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF59DDB2),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: columns == 4 ? 53 : 48,
                          child: Center(
                            child: FlowArtButton(
                              key: ValueKey('flow-tool-${tool.name}'),
                              art: flowToolArt(tool),
                              label:
                                  '${flowToolName(tool)}, запас ${flow.available(tool)}',
                              onPressed: enabled ? () => onUse(tool) : null,
                              width: 58,
                              height: 48,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 48,
                          child: Row(
                            children: [
                              Expanded(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Positioned.fill(
                                      child: FlowSprite(
                                        'booster_counter_badge',
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: FlowNumber(
                                        flow.available(tool),
                                        size: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              FlowArtButton(
                                key: ValueKey('flow-tool-more-${tool.name}'),
                                art: 'booster_plus_button',
                                visualSize: 28,
                                label: 'Запас: ${flowToolName(tool)}',
                                onPressed: enabled ? () => onMore(tool) : null,
                                width: 48,
                                height: 48,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
