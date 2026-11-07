import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../domain/achievements.dart';
import 'widgets/finora_orb.dart';

/// 1.44: one place that knows which picture of Finora goes with what.
///
/// A reaction has a picture (an illustration from the owner's sheets) or,
/// when there is none, a drawn mood of the living Finora. A missing
/// reaction falls back to a related one, and in the end to the neutral one:
/// the app never shows an empty place instead of her.
abstract final class FinoraAssets {
  static const folder = 'assets/finora/achievements';

  /// Every illustration that ships with the app (file names without
  /// the extension).
  static const art = {
    'accounts_added',
    'analyst',
    'balance_plus',
    'budget_created',
    'budget_master',
    'cashback',
    'categories_set',
    'category_master',
    'debt_closed',
    'expenses_control',
    'finance_zen',
    'first_expense',
    'first_income',
    'first_record',
    'first_step',
    'goal_done',
    'goal_set',
    'income_grows',
    'invest_started',
    'limit_kept',
    'month_discipline',
    'month_plan',
    'no_spend_day',
    'payment_on_time',
    'piggy_opened',
    'report_ready',
    'safety_cushion',
    'seven_days',
    'subs_control',
    'week_tracking',
  };

  /// The illustration of each reaction, where there is one.
  static const reactionArt = <FinoraReactionType, String>{
    FinoraReactionType.neutral: 'first_step',
    FinoraReactionType.happy: 'balance_plus',
    FinoraReactionType.proud: 'budget_master',
    FinoraReactionType.excited: 'seven_days',
    FinoraReactionType.celebrating: 'goal_done',
    FinoraReactionType.thinking: 'analyst',
    FinoraReactionType.focused: 'month_plan',
    FinoraReactionType.calm: 'finance_zen',
    FinoraReactionType.supportive: 'no_spend_day',
    FinoraReactionType.love: 'piggy_opened',
    FinoraReactionType.success: 'limit_kept',
  };

  /// What to show instead when a reaction has nothing of its own.
  static const fallback = <FinoraReactionType, FinoraReactionType>{
    FinoraReactionType.celebrating: FinoraReactionType.happy,
    FinoraReactionType.proud: FinoraReactionType.happy,
    FinoraReactionType.excited: FinoraReactionType.happy,
    FinoraReactionType.success: FinoraReactionType.happy,
    FinoraReactionType.love: FinoraReactionType.happy,
    FinoraReactionType.focused: FinoraReactionType.neutral,
    FinoraReactionType.thinking: FinoraReactionType.neutral,
    FinoraReactionType.supportive: FinoraReactionType.calm,
    FinoraReactionType.calm: FinoraReactionType.neutral,
    FinoraReactionType.happy: FinoraReactionType.neutral,
    FinoraReactionType.sleepy: FinoraReactionType.calm,
    FinoraReactionType.surprised: FinoraReactionType.neutral,
    FinoraReactionType.worried: FinoraReactionType.supportive,
    FinoraReactionType.warning: FinoraReactionType.worried,
  };

  /// The drawn Finora of each reaction (always there).
  static FinoraMood mood(FinoraReactionType type) => switch (type) {
    FinoraReactionType.neutral => FinoraMood.idle,
    FinoraReactionType.happy => FinoraMood.happy,
    FinoraReactionType.proud => FinoraMood.wink,
    FinoraReactionType.excited => FinoraMood.delight,
    FinoraReactionType.celebrating => FinoraMood.delight,
    FinoraReactionType.surprised => FinoraMood.surprised,
    FinoraReactionType.thinking => FinoraMood.thinking,
    FinoraReactionType.focused => FinoraMood.processing,
    FinoraReactionType.calm => FinoraMood.calm,
    FinoraReactionType.supportive => FinoraMood.support,
    FinoraReactionType.worried => FinoraMood.doubt,
    FinoraReactionType.warning => FinoraMood.attention,
    FinoraReactionType.sleepy => FinoraMood.sleep,
    FinoraReactionType.love => FinoraMood.pleasure,
    FinoraReactionType.success => FinoraMood.done,
  };

  /// The illustration for [type] following the fallbacks, or null when only
  /// the drawn Finora is left. [available] is for tests.
  static String? artFor(
    FinoraReactionType type, {
    Map<FinoraReactionType, String> available = reactionArt,
  }) {
    final seen = <FinoraReactionType>{};
    FinoraReactionType? t = type;
    while (t != null && seen.add(t)) {
      final name = available[t];
      if (name != null && art.contains(name)) return name;
      t = fallback[t];
    }
    final neutral = available[FinoraReactionType.neutral];
    return neutral != null && art.contains(neutral) ? neutral : null;
  }

  /// The reaction that ends up shown for [type] (for tests and labels).
  static FinoraReactionType resolve(
    FinoraReactionType type, {
    Set<FinoraReactionType> available = const {},
  }) {
    final seen = <FinoraReactionType>{};
    FinoraReactionType? t = type;
    while (t != null && seen.add(t)) {
      if (available.contains(t)) return t;
      t = fallback[t];
    }
    return FinoraReactionType.neutral;
  }

  static String path(String name) => '$folder/$name.webp';

  /// An achievement's own picture; a missing one falls back to its reaction.
  static String? achievementArt(AchievementDefinition d) =>
      art.contains(d.art) ? d.art : artFor(d.reaction);
}

/// A picture of Finora: an illustration, or the drawn Finora when the file
/// cannot be shown.
class FinoraArt extends StatelessWidget {
  const FinoraArt({
    super.key,
    required this.name,
    this.reaction = FinoraReactionType.neutral,
    this.fit = BoxFit.cover,
    this.locked = false,
    this.semanticLabel,
  });

  final String? name;
  final FinoraReactionType reaction;
  final BoxFit fit;

  /// Not received yet: no colour, dimmed.
  final bool locked;
  final String? semanticLabel;

  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final drawn = LayoutBuilder(
      builder: (context, box) => Center(
        child: FinoraCharacter(
          size: (box.biggest.shortestSide * .8).clamp(24, 160),
          moods: [FinoraAssets.mood(reaction)],
          rings: false,
        ),
      ),
    );
    Widget child = name == null
        ? drawn
        : Image.asset(
            FinoraAssets.path(name!),
            fit: fit,
            semanticLabel: semanticLabel,
            excludeFromSemantics: semanticLabel == null,
            errorBuilder: (_, _, _) => drawn,
          );
    if (locked) {
      child = Opacity(
        opacity: .45,
        child: ColorFiltered(colorFilter: _grey, child: child),
      );
    }
    return child;
  }
}
