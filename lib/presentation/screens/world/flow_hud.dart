import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:intl/intl.dart';

import '../../../domain/flow/flow.dart';
import '../../l10n_widgets.dart';
import 'flow_art.dart';
import 'world_art.dart' show worldFontFamily;

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
        fontFamily: worldFontFamily,
        color: flowInk,
        fontSize: size,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// 1.60: the game's own type: Finora Potok in the plum ink.
TextStyle flowText(double size, {bool bold = true, Color color = flowInk}) =>
    TextStyle(
      fontFamily: worldFontFamily,
      fontSize: size,
      height: 1.15,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// 1.60: one compact pearl plate for the game's chrome — a soft milky
/// gradient, a thin champagne edge and a gentle shadow.
class FlowPearl extends StatelessWidget {
  const FlowPearl({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.height,
    this.radius = 18,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? height;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: padding,
    decoration: ShapeDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFCFE), Color(0xFFF3E9F4)],
      ),
      shape: RoundedSuperellipseBorder(
        side: const BorderSide(color: Color(0xFFE3C9A0), width: 1.2),
        borderRadius: BorderRadius.circular(radius),
      ),
      shadows: const [
        BoxShadow(
          color: Color(0x2A4B2346),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
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

  /// 1.60: a compact top — the level and pause on one row, moves and goals
  /// on one pearl plate, the score track below. All labels are live text.
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: FlowPearl(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Semantics(
                  label: 'Уровень ${level.id}',
                  excludeSemantics: true,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Уровень ${level.id}', style: flowText(18)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FlowArtButton(
              key: const ValueKey('flow-pause'),
              art: 'hud_pause_button',
              label: 'Пауза',
              onPressed: onPause,
              width: 48,
              height: 48,
              visualSize: 42,
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      FlowPearl(
        padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              Semantics(
                label: 'Ходы: ${session.remainingMoves}',
                excludeSemantics: true,
                child: SizedBox(
                  width: 54,
                  // Large system text shrinks to fit instead of spilling.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ХОДЫ',
                          style: flowText(
                            10,
                            color: flowInk.withValues(alpha: .6),
                          ).copyWith(letterSpacing: .8),
                        ),
                        SizedBox(
                          height: 26,
                          child: FlowNumber(session.remainingMoves, size: 24),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: const Color(0xFFE3C9A0),
              ),
              Text(
                'ЦЕЛИ',
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: flowText(
                  10,
                  color: flowInk.withValues(alpha: .6),
                ).copyWith(letterSpacing: .8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      for (final goal in level.goals)
                        Semantics(
                          label:
                              '${goal.title}: ${math.max(0, goal.target - (session.progress[goal.key] ?? 0))}',
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FlowGoalIcon(goal.key, size: 30),
                                const SizedBox(width: 4),
                                FlowNumber(
                                  math.max(
                                    0,
                                    goal.target -
                                        (session.progress[goal.key] ?? 0),
                                  ),
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 26,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Semantics(
                label: 'Счёт: ${session.score}',
                child: FlowNumber(session.score, size: 15),
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

  /// 1.60: a slim tool bar — each tool on a small tile, the icon kept
  /// inside it, the stock as a badge and «+» in the corner.
  @override
  Widget build(BuildContext context) => FlowPearl(
    padding: const EdgeInsets.all(6),
    radius: 20,
    child: LayoutBuilder(
      builder: (context, box) => Wrap(
        children: [
          for (final tool in FlowTool.values)
            SizedBox(
              width: box.maxWidth / columns,
              height: 66,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: FlowToolTile(
                  tool: tool,
                  stock: flow.available(tool),
                  selected: selected == tool,
                  buttonKey: ValueKey('flow-tool-${tool.name}'),
                  onPressed: enabled ? () => onUse(tool) : null,
                  moreKey: ValueKey('flow-tool-more-${tool.name}'),
                  onMore: enabled ? () => onMore(tool) : null,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// One booster on a small lavender tile (shared by the level and its start
/// screen): the icon always fits inside the tile.
class FlowToolTile extends StatelessWidget {
  const FlowToolTile({
    super.key,
    required this.tool,
    required this.stock,
    required this.selected,
    required this.buttonKey,
    required this.onPressed,
    this.moreKey,
    this.onMore,
    this.label,
  });
  final FlowTool tool;
  final int stock;
  final bool selected;
  final Key buttonKey;
  final Key? moreKey;
  final VoidCallback? onPressed, onMore;
  final String? label;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = math.min(box.maxWidth, box.maxHeight);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: ShapeDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF1E8F6), Color(0xFFE2D3EE)],
                ),
                shape: RoundedSuperellipseBorder(
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF3FC79F)
                        : const Color(0xFFE6D4C0),
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: FlowArtButton(
              key: buttonKey,
              art: flowToolArt(tool),
              label: label ?? '${flowToolName(tool)}, запас $stock',
              onPressed: onPressed,
              visualSize: math.max(24, side * .66),
            ),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: ShapeDecoration(
                  color: Colors.white.withValues(alpha: .92),
                  shape: const StadiumBorder(
                    side: BorderSide(color: Color(0xFFE3C9A0)),
                  ),
                ),
                child: Text(
                  '$stock',
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: flowText(12),
                ),
              ),
            ),
          ),
          if (selected)
            const Positioned(
              right: 4,
              top: 4,
              child: IgnorePointer(
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF27896C),
                  size: 18,
                ),
              ),
            ),
          if (onMore != null || moreKey != null)
            Positioned(
              right: -8,
              bottom: -8,
              child: FlowArtButton(
                key: moreKey,
                art: 'booster_plus_button',
                visualSize: 22,
                label: 'Запас: ${flowToolName(tool)}',
                onPressed: onMore,
                width: 44,
                height: 44,
              ),
            ),
        ],
      );
    },
  );
}
