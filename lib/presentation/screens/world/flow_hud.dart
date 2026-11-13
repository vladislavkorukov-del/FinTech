import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:intl/intl.dart';

import '../../../domain/flow/flow.dart';
import '../../l10n_widgets.dart';
import 'flow_art.dart';
import 'world_art.dart' show worldFontFamily;

part 'flow_hud_tools.dart';

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

/// 1.61: a number that counts to its new value (or, with reduced motion,
/// changes at once).
class FlowCountUp extends StatelessWidget {
  const FlowCountUp(this.value, {super.key, this.size = 24});
  final int value;
  final double size;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 520),
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => FlowNumber(v.round(), size: size),
  );
}

/// 1.61: a number that gives a little bump when it changes.
class FlowBump extends StatelessWidget {
  const FlowBump(this.value, {super.key, this.size = 24});
  final int value;
  final double size;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    switchInCurve: Curves.easeOutBack,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .6, end: 1.0).animate(animation),
        child: child,
      ),
    ),
    layoutBuilder: (current, previous) =>
        Stack(alignment: Alignment.center, children: [...previous, ?current]),
    child: FlowNumber(value, key: ValueKey(value), size: size),
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

  /// Visible aspect ratios of the two cards (from the pack's alpha bounds).
  static double get _movesAspect => FlowArt.aspectRatio('hud_moves_card');
  static double get _goalsAspect => FlowArt.aspectRatio('hud_goals_card');
  static const _gap = 8.0, _header = 48.0, _score = 30.0, _spacing = 6.0;

  /// 1.62: the cards keep their pack proportions (moves ≈ 29%, goals ≈ 71%
  /// of the row) and never grow taller than 108.
  static double cardHeight(double width) =>
      math.min(108.0, (width - _gap) / (_movesAspect + _goalsAspect));

  /// The HUD's full height for a given width, for the screen's layout.
  static double heightFor(double width) =>
      _header + _spacing + cardHeight(width) + _spacing + _score;

  /// 1.62: the pack's top HUD — the level plate with its «Уровень» lettering
  /// and a live number, pause on the right; separate «ХОДЫ» and «ЦЕЛИ»
  /// cards with live numbers; the score track with three stars.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final card = cardHeight(box.maxWidth);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _header,
            child: Row(
              children: [
                Expanded(child: _LevelPlate(level: level.id)),
                const SizedBox(width: 6),
                FlowArtButton(
                  key: const ValueKey('flow-pause'),
                  art: 'hud_pause_button',
                  label: 'Пауза',
                  onPressed: onPause,
                  width: 48,
                  height: 48,
                  visualSize: 46,
                ),
              ],
            ),
          ),
          const SizedBox(height: _spacing),
          SizedBox(
            height: card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MovesCard(moves: session.remainingMoves, height: card),
                const SizedBox(width: _gap),
                _GoalsCard(
                  goals: level.goals,
                  progress: session.progress,
                  height: card,
                ),
              ],
            ),
          ),
          const SizedBox(height: _spacing),
          SizedBox(
            height: _score,
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Semantics(
                    label: 'Счёт: ${session.score}',
                    excludeSemantics: true,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FlowCountUp(session.score, size: 17),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: session.score.toDouble()),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 620),
                    curve: Curves.easeOutCubic,
                    builder: (context, score, _) => FlowScoreTrack(
                      score: score.round(),
                      thresholds: level.scoreThresholds,
                    ),
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

/// The empty pearl plate (nine-slice) with the «Уровень» lettering PNG and
/// the live level number beside it.
class _LevelPlate extends StatelessWidget {
  const _LevelPlate({required this.level});
  final int level;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Уровень $level',
    excludeSemantics: true,
    child: FlowArtPanel(
      art: 'hud_level_header',
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const FlowSprite('hud_level_label', height: 26),
              const SizedBox(width: 7),
              // The lettering's baseline sits ~22% above its bottom edge
              // (the descenders of «у» and «р»).
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '$level',
                  textScaler: TextScaler.noScaling,
                  style: flowText(28).copyWith(height: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// «ХОДЫ» is baked into the card; the number below it is live.
class _MovesCard extends StatelessWidget {
  const _MovesCard({required this.moves, required this.height});
  final int moves;
  final double height;
  @override
  Widget build(BuildContext context) {
    final width = height * FlowTopHud._movesAspect;
    return Semantics(
      label: 'Ходы: $moves',
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey('flow-hud-moves'),
        width: width,
        height: height,
        child: Stack(
          children: [
            const Positioned.fill(child: FlowSprite('hud_moves_card')),
            // Below the baked label (top 11–25% of the card).
            Positioned(
              left: width * .1,
              right: width * .1,
              top: height * .28,
              bottom: height * .1,
              child: Center(child: FlowBump(moves, size: height * .46)),
            ),
          ],
        ),
      ),
    );
  }
}

/// «ЦЕЛИ» is baked into the card; the level's goal pieces and the live
/// remaining counts sit below it.
class _GoalsCard extends StatelessWidget {
  const _GoalsCard({
    required this.goals,
    required this.progress,
    required this.height,
  });
  final List<FlowGoal> goals;
  final Map<String, int> progress;
  final double height;
  @override
  Widget build(BuildContext context) {
    final width = height * FlowTopHud._goalsAspect;
    final icon = height * .36;
    return SizedBox(
      key: const ValueKey('flow-hud-goals'),
      width: width,
      height: height,
      child: Stack(
        children: [
          const Positioned.fill(child: FlowSprite('hud_goals_card')),
          Positioned(
            left: width * .06,
            right: width * .06,
            top: height * .27,
            bottom: height * .08,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final goal in goals)
                    Builder(
                      builder: (context) {
                        final left = math.max(
                          0,
                          goal.target - (progress[goal.key] ?? 0),
                        );
                        return Semantics(
                          label: '${goal.title}: $left',
                          excludeSemantics: true,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: height * .08,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FlowGoalIcon(goal.key, size: icon),
                                SizedBox(
                                  height: height * .28,
                                  child: FlowBump(left, size: height * .26),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
