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

/// 1.63: the game's one type style — Finora Potok, plum ink, a few fixed
/// roles. Every word in «Поток» is live text in one of these.
abstract final class FlowType {
  /// Window titles: «Пауза», «Уровень пройден!», «Закончились ходы».
  static TextStyle get title => flowText(24).copyWith(height: 1.08);

  /// Plate and section headings: «Уровень 3», «Очки», «Цели уровня».
  static TextStyle get heading => flowText(17);

  /// Small capitals over a number: «ХОДЫ», «ЦЕЛИ».
  static TextStyle get label => flowText(
    10.5,
    color: flowInk.withValues(alpha: .62),
  ).copyWith(letterSpacing: .9);

  /// Every button.
  static TextStyle get button => flowText(17);

  /// Notes and hints.
  static TextStyle get body => flowText(13.5, bold: false);
}

/// A button's live caption, shrinking to fit rather than wrapping.
class FlowButtonText extends StatelessWidget {
  const FlowButtonText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, style: FlowType.button),
    ),
  );
}

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

  static const _row = 48.0, _plate = 60.0, _score = 30.0, _spacing = 6.0;
  static const _value = 21.0;

  int _left(FlowGoal goal) =>
      math.max(0, goal.target - (session.progress[goal.key] ?? 0));

  /// The HUD's full height (it no longer depends on the width).
  static double heightFor(double width) =>
      _row + _spacing + _plate + _spacing + _score;

  /// 1.63: the compact top again — the level and pause on one row, moves
  /// and goals on one plate, the score track below. Plates are the empty
  /// pearl art from the library; every word and number is live Finora
  /// Potok in the game's one type style.
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: _row,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: 'Уровень ${level.id}',
                excludeSemantics: true,
                child: FlowArtPanel(
                  art: 'hud_level_header',
                  sliceByHeight: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Уровень ${level.id}',
                        style: FlowType.heading,
                      ),
                    ),
                  ),
                ),
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
              visualSize: 46,
            ),
          ],
        ),
      ),
      const SizedBox(height: _spacing),
      // 1.64: two matching plates — the same small label on top, the
      // value centred below it, numbers at one size and baseline.
      SizedBox(
        height: _plate,
        child: Row(
          children: [
            SizedBox(
              // Wide enough for the plate's corners at this height.
              width: 128,
              child: _StatPlate(
                key: const ValueKey('flow-hud-moves'),
                label: 'ХОДЫ',
                semantics: 'Ходы: ${session.remainingMoves}',
                child: FlowBump(session.remainingMoves, size: _value),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _StatPlate(
                key: const ValueKey('flow-hud-goals'),
                label: 'ЦЕЛИ',
                semantics: [
                  for (final goal in level.goals)
                    '${goal.title}: ${_left(goal)}',
                ].join(', '),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, goal) in level.goals.indexed) ...[
                      if (i > 0) const SizedBox(width: 14),
                      FlowGoalIcon(goal.key, size: _value + 4),
                      const SizedBox(width: 4),
                      FlowBump(_left(goal), size: _value),
                    ],
                  ],
                ),
              ),
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
              width: 60,
              child: Semantics(
                label: 'Счёт: ${session.score}',
                excludeSemantics: true,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FlowCountUp(session.score, size: 16),
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
}

/// One HUD plate: a small label on top, the value centred below it.
class _StatPlate extends StatelessWidget {
  const _StatPlate({
    super.key,
    required this.label,
    required this.semantics,
    required this.child,
  });
  final String label, semantics;
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    excludeSemantics: true,
    child: FlowArtPanel(
      art: 'hud_level_header',
      sliceByHeight: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Center(
        // Large system text shrinks to fit instead of spilling.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: FlowType.label),
              const SizedBox(height: 1),
              SizedBox(height: 27, child: Center(child: child)),
            ],
          ),
        ),
      ),
    ),
  );
}
