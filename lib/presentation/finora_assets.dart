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

  /// 1.45: every achievement has its own card (1706×922 from the owner,
  /// shipped as 1024×553 WebP), named by the achievement's id.
  static const art = {
    'analyst_10',
    'analytics_open',
    'archaeologist',
    'archive',
    'balance_6',
    'big_check',
    'budget_12',
    'budget_3',
    'budget_6',
    'budget_month',
    'cash',
    'categorized_100',
    'categorized_95',
    'cushion_1',
    'cushion_3',
    'cushion_6',
    'economy',
    'fifty_records',
    'first_account',
    'first_budget',
    'first_step',
    'first_topup',
    'first_transfer',
    'full_picture',
    'goal_90',
    'goal_done',
    'goal_half',
    'goal_set',
    'goals_10',
    'goals_3',
    'ideal_year',
    'legend',
    'night',
    'no_overdue',
    'on_time',
    'order',
    'organizer',
    'own_category',
    'perfect_month',
    'perfectionist',
    'plus_3',
    'plus_month',
    'reserve_80',
    'reserve_90',
    'saved_1000',
    'saved_10000',
    'streak_100',
    'streak_3',
    'streak_30',
    'streak_7',
    'ten_records',
    'tiny',
    'veteran',
    'year',
  };

  /// Width to height of a card.
  static const cardRatio = 1024 / 553;

  /// The card of each reaction.
  static const reactionArt = <FinoraReactionType, String>{
    FinoraReactionType.neutral: 'first_step',
    FinoraReactionType.happy: 'plus_month',
    FinoraReactionType.proud: 'budget_6',
    FinoraReactionType.excited: 'streak_7',
    FinoraReactionType.celebrating: 'goal_done',
    FinoraReactionType.thinking: 'analyst_10',
    FinoraReactionType.focused: 'budget_month',
    FinoraReactionType.calm: 'budget_12',
    FinoraReactionType.supportive: 'cushion_1',
    FinoraReactionType.love: 'first_topup',
    FinoraReactionType.success: 'on_time',
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

  /// An achievement's own card; a missing one falls back to its reaction.
  static String? achievementArt(AchievementDefinition d) =>
      art.contains(d.id) ? d.id : artFor(d.reaction);
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
    this.frame = true,
  });

  final String? name;
  final FinoraReactionType reaction;
  final BoxFit fit;

  /// Not received yet: no colour, dimmed.
  final bool locked;
  final String? semanticLabel;

  /// False: the card's own glowing frame is cut off (small pictures in
  /// lists, where the app draws its own border).
  final bool frame;

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
    if (!frame && name != null) {
      child = ClipRect(child: Transform.scale(scale: 1.09, child: child));
    }
    if (locked) {
      child = Opacity(
        opacity: .45,
        child: ColorFiltered(colorFilter: _grey, child: child),
      );
    }
    return child;
  }
}
