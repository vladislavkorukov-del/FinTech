import 'achievements.dart';

/// Finora 1.46: the wardrobe — things for Finora to wear, received for
/// achievements (and, later, for events and mini-games).
///
/// The catalog is data; what the person has is [WardrobeState], stored with
/// the rest of the ledger. An item is open when its source is reached:
/// for an achievement — once that achievement is received (it is never
/// taken away, so neither is the item).

enum WardrobeCategory { headwear, glasses, headphones, crown, cape, companion }

/// Where an item is worn; one item per slot. Hats, crowns and headphones
/// share «top» so they never overlap.
enum WardrobeSlot { top, eyes, cape, companion }

/// Drawing order around Finora, back to front.
enum WardrobeLayer {
  behindCharacter,
  body,
  cape,
  headwear,
  eyesAccessory,
  frontAccessory,
  particles,
}

/// Where an item comes from.
sealed class WardrobeSource {
  const WardrobeSource();
}

/// Received together with an achievement ([AchievementDefinition.id]).
class AchievementReward extends WardrobeSource {
  const AchievementReward(this.achievementId);
  final String achievementId;
}

/// A special event or a mini-game. [live] — whether it can be received in
/// this version at all; a future one is shown closed, as «???».
class EventReward extends WardrobeSource {
  const EventReward(this.eventId, {this.live = false});
  final String eventId;
  final bool live;
}

/// How a picture sits on Finora. Units: Finora's radius r, from the centre
/// of her sphere; [width] — of her diameter. [anchor] is the point of the
/// picture (−1…1, as Flutter's Alignment) put at ([x], [y]).
class WardrobeFit {
  const WardrobeFit({
    required this.width,
    this.x = 0,
    this.y = 0,
    this.anchorX = 0,
    this.anchorY = 0,
    this.rotation = 0,
    this.front,
  });

  final double width, x, y, anchorX, anchorY, rotation;

  /// Capes: the share of the picture, from its top, drawn in front of her
  /// (the collar and the clasp); the rest stays behind. Null — all behind.
  final double? front;
}

class WardrobeItem {
  const WardrobeItem({
    required this.id,
    required this.name,
    required this.category,
    required this.rarity,
    required this.source,
    required this.fit,
    this.secret = false,
  });

  final String id, name;
  final WardrobeCategory category;
  final AchievementRarity rarity;
  final WardrobeSource source;
  final WardrobeFit fit;

  /// Shown as «???» until received (a secret achievement or a future event).
  final bool secret;

  String get asset => 'assets/finora/wardrobe/$id.png';

  /// Width ÷ height of the picture (its transparent margins trimmed).
  double get ratio => wardrobeRatios[id] ?? 1;

  WardrobeSlot get slot => switch (category) {
    WardrobeCategory.headwear ||
    WardrobeCategory.headphones ||
    WardrobeCategory.crown => WardrobeSlot.top,
    WardrobeCategory.glasses => WardrobeSlot.eyes,
    WardrobeCategory.cape => WardrobeSlot.cape,
    WardrobeCategory.companion => WardrobeSlot.companion,
  };

  WardrobeLayer get layer => switch (category) {
    WardrobeCategory.headwear ||
    WardrobeCategory.headphones ||
    WardrobeCategory.crown => WardrobeLayer.headwear,
    WardrobeCategory.glasses => WardrobeLayer.eyesAccessory,
    WardrobeCategory.cape => WardrobeLayer.cape,
    WardrobeCategory.companion => WardrobeLayer.frontAccessory,
  };

  String? get achievementId => switch (source) {
    AchievementReward(:final achievementId) => achievementId,
    EventReward() => null,
  };
}

/// What the person has: when each item was received and what is worn.
class WardrobeState {
  const WardrobeState({this.received = const {}, this.equipped = const {}});

  /// Item id → when it appeared in the wardrobe.
  final Map<String, DateTime> received;

  /// Slot → item id.
  final Map<WardrobeSlot, String> equipped;

  WardrobeState copyWith({
    Map<String, DateTime>? received,
    Map<WardrobeSlot, String>? equipped,
  }) => WardrobeState(
    received: received ?? this.received,
    equipped: equipped ?? this.equipped,
  );

  Map<String, Object?> toJson() => {
    'received': {
      for (final e in received.entries) e.key: e.value.toIso8601String(),
    },
    'equipped': {for (final e in equipped.entries) e.key.name: e.value},
  };

  factory WardrobeState.fromJson(Map<String, dynamic> j) {
    final received = <String, DateTime>{};
    for (final e in (j['received'] as Map? ?? const {}).entries) {
      final at = DateTime.tryParse('${e.value}');
      if (at != null) received['${e.key}'] = at;
    }
    final equipped = <WardrobeSlot, String>{};
    for (final e in (j['equipped'] as Map? ?? const {}).entries) {
      final slot = WardrobeSlot.values
          .where((s) => s.name == e.key)
          .firstOrNull;
      if (slot != null && e.value is String) equipped[slot] = e.value as String;
    }
    return WardrobeState(received: received, equipped: equipped);
  }
}

abstract final class Wardrobe {
  static WardrobeItem? item(String id) =>
      wardrobeItems.where((i) => i.id == id).firstOrNull;

  /// Whether [item]'s source is reached by [achievements] (or it was given).
  static bool open(
    WardrobeItem item,
    AchievementState achievements,
    WardrobeState state,
  ) =>
      state.received.containsKey(item.id) ||
      switch (item.source) {
        AchievementReward(:final achievementId) =>
          achievements.unlocked.containsKey(achievementId),
        EventReward() => false,
      };

  /// Items an achievement gives.
  static List<WardrobeItem> rewardsOf(String achievementId) => [
    for (final i in wardrobeItems)
      if (i.achievementId == achievementId) i,
  ];

  /// [state] with every item whose source is reached; each one is added
  /// once, with the date its achievement was received (never twice).
  static WardrobeState sync(
    WardrobeState state,
    AchievementState achievements, {
    DateTime? now,
  }) {
    Map<String, DateTime>? received;
    for (final i in wardrobeItems) {
      if (state.received.containsKey(i.id)) continue;
      final id = i.achievementId;
      final at = id == null ? null : achievements.unlocked[id];
      if (at == null) continue;
      (received ??= {...state.received})[i.id] = at;
    }
    // Only received items can be worn.
    final equipped = {
      for (final e in state.equipped.entries)
        if ((received ?? state.received).containsKey(e.value) &&
            item(e.value)?.slot == e.key)
          e.key: e.value,
    };
    if (received == null && equipped.length == state.equipped.length) {
      return state;
    }
    return WardrobeState(
      received: received ?? state.received,
      equipped: equipped,
    );
  }

  /// Puts [itemId] on, taking off whatever was in its slot.
  static WardrobeState wear(WardrobeState state, String itemId) {
    final i = item(itemId);
    if (i == null || !state.received.containsKey(itemId)) {
      throw const FormatException('Этот предмет ещё не открыт');
    }
    return state.copyWith(equipped: {...state.equipped, i.slot: itemId});
  }

  static WardrobeState takeOff(WardrobeState state, WardrobeSlot slot) =>
      state.copyWith(
        equipped: {
          for (final e in state.equipped.entries)
            if (e.key != slot) e.key: e.value,
        },
      );

  /// What is worn, back to front.
  static List<WardrobeItem> worn(WardrobeState state) =>
      [for (final id in state.equipped.values) ?item(id)]
        ..sort((a, b) => a.layer.index.compareTo(b.layer.index));
}

const _top = -1.0; // the top of her sphere, in r

/// The 30 items, each with its own fit (see [WardrobeFit]).
const wardrobeItems = <WardrobeItem>[
  // ── Шапки ─────────────────────────────────────────────────────────────
  WardrobeItem(
    id: 'first_step_cap',
    name: 'Кепка первого шага',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.common,
    source: AchievementReward('first_step'),
    fit: WardrobeFit(width: .98, y: _top + .5, anchorY: 1, rotation: -.06),
  ),
  WardrobeItem(
    id: 'habit_flame_cap',
    name: 'Кепка с огоньком привычки',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.uncommon,
    source: AchievementReward('streak_7'),
    fit: WardrobeFit(width: 1.02, y: _top + .5, anchorY: 1),
  ),
  WardrobeItem(
    id: 'budget_master_cap',
    name: 'Кепка мастера бюджета',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.epic,
    source: AchievementReward('budget_6'),
    fit: WardrobeFit(width: 1.0, y: _top + .5, anchorY: 1, rotation: -.04),
  ),
  WardrobeItem(
    id: 'cushion_sleep_cap',
    name: 'Сонный колпак запаса',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.rare,
    source: AchievementReward('cushion_1'),
    fit: WardrobeFit(width: 1.12, x: .12, y: _top + .5, anchorY: 1),
  ),
  WardrobeItem(
    id: 'night_cap',
    name: 'Ночной колпак',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.rare,
    source: AchievementReward('night'),
    secret: true,
    fit: WardrobeFit(width: 1.1, x: .1, y: _top + .5, anchorY: 1),
  ),
  WardrobeItem(
    id: 'anniversary_party_cap',
    name: 'Праздничный колпак годовщины',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.epic,
    source: AchievementReward('year'),
    fit: WardrobeFit(width: .9, x: .12, y: _top + .42, anchorY: 1),
  ),
  WardrobeItem(
    id: 'organizer_helmet',
    name: 'Шлем организатора',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.uncommon,
    source: AchievementReward('organizer'),
    fit: WardrobeFit(width: 1.06, y: _top + .52, anchorY: 1),
  ),
  WardrobeItem(
    id: 'steady_plus_top_hat',
    name: 'Цилиндр стабильного плюса',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.rare,
    source: AchievementReward('plus_3'),
    fit: WardrobeFit(width: .78, y: _top + .3, anchorY: 1, rotation: .08),
  ),
  WardrobeItem(
    id: 'savings_piggy_cap',
    name: 'Шапка-копилка',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.rare,
    source: AchievementReward('saved_10000'),
    fit: WardrobeFit(width: 1.0, y: _top + .48, anchorY: 1),
  ),
  WardrobeItem(
    id: 'marathon_headband',
    name: 'Повязка марафонца',
    category: WardrobeCategory.headwear,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('streak_100'),
    fit: WardrobeFit(width: 1.04, y: _top + .5, anchorY: 1),
  ),
  // ── Очки ──────────────────────────────────────────────────────────────
  WardrobeItem(
    id: 'round_accounting_glasses',
    name: 'Круглые очки бухгалтера',
    category: WardrobeCategory.glasses,
    rarity: AchievementRarity.common,
    source: AchievementReward('ten_records'),
    fit: WardrobeFit(width: .82, y: -.07),
  ),
  WardrobeItem(
    id: 'analyst_glasses',
    name: 'Очки аналитика',
    category: WardrobeCategory.glasses,
    rarity: AchievementRarity.rare,
    source: AchievementReward('analyst_10'),
    fit: WardrobeFit(width: .84, y: -.07),
  ),
  WardrobeItem(
    id: 'fintech_visor',
    name: 'Финтех-визор',
    category: WardrobeCategory.glasses,
    rarity: AchievementRarity.uncommon,
    source: AchievementReward('full_picture'),
    fit: WardrobeFit(width: .96, y: -.1),
  ),
  WardrobeItem(
    id: 'heart_glasses',
    name: 'Очки-сердечки',
    category: WardrobeCategory.glasses,
    rarity: AchievementRarity.epic,
    source: EventReward('valentine'),
    secret: true,
    fit: WardrobeFit(width: .84, y: -.06),
  ),
  WardrobeItem(
    id: 'golden_perspective_glasses',
    name: 'Золотые очки перспективы',
    category: WardrobeCategory.glasses,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('budget_12'),
    fit: WardrobeFit(width: .84, y: -.07),
  ),
  // ── Наушники ──────────────────────────────────────────────────────────
  WardrobeItem(
    id: 'mint_buds',
    name: 'Мятные наушники-капли',
    category: WardrobeCategory.headphones,
    rarity: AchievementRarity.common,
    source: AchievementReward('first_account'),
    fit: WardrobeFit(width: 1.06, y: .1),
  ),
  WardrobeItem(
    id: 'weekly_rhythm_headphones',
    name: 'Наушники недельного ритма',
    category: WardrobeCategory.headphones,
    rarity: AchievementRarity.uncommon,
    source: AchievementReward('streak_7'),
    fit: WardrobeFit(width: 1.2, y: .2, anchorY: 1),
  ),
  WardrobeItem(
    id: 'cyan_pulse_headphones',
    name: 'Наушники «Бирюзовый пульс»',
    category: WardrobeCategory.headphones,
    rarity: AchievementRarity.epic,
    source: AchievementReward('streak_30'),
    fit: WardrobeFit(width: 1.2, y: .22, anchorY: 1),
  ),
  WardrobeItem(
    id: 'champagne_sound_headphones',
    name: 'Наушники «Шампань»',
    category: WardrobeCategory.headphones,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('veteran'),
    fit: WardrobeFit(width: 1.2, y: .2, anchorY: 1),
  ),
  // ── Короны ────────────────────────────────────────────────────────────
  WardrobeItem(
    id: 'silver_spark_crown',
    name: 'Серебряная корона-искра',
    category: WardrobeCategory.crown,
    rarity: AchievementRarity.rare,
    source: AchievementReward('goal_done'),
    fit: WardrobeFit(width: .6, y: _top + .2, anchorY: 1),
  ),
  WardrobeItem(
    id: 'dream_crystal_crown',
    name: 'Корона с кристаллом мечты',
    category: WardrobeCategory.crown,
    rarity: AchievementRarity.epic,
    source: AchievementReward('goals_3'),
    fit: WardrobeFit(width: .7, y: _top + .24, anchorY: 1),
  ),
  WardrobeItem(
    id: 'perfect_month_wreath',
    name: 'Лавровый венок идеального месяца',
    category: WardrobeCategory.crown,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('perfect_month'),
    fit: WardrobeFit(width: .92, y: _top + .45, anchorY: 1),
  ),
  WardrobeItem(
    id: 'finora_legend_crown',
    name: 'Корона легенды Finora',
    category: WardrobeCategory.crown,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('legend'),
    fit: WardrobeFit(width: .78, y: _top + .26, anchorY: 1),
  ),
  // ── Накидки ───────────────────────────────────────────────────────────
  WardrobeItem(
    id: 'reserve_scarf',
    name: 'Шарф запаса',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.epic,
    source: AchievementReward('cushion_3'),
    fit: WardrobeFit(width: 1.22, y: .28, anchorY: -1, front: .34),
  ),
  WardrobeItem(
    id: 'punctuality_shield_cape',
    name: 'Плащ пунктуальности',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.uncommon,
    source: AchievementReward('no_overdue'),
    fit: WardrobeFit(width: 1.42, y: .22, anchorY: -1, front: .26),
  ),
  WardrobeItem(
    id: 'veteran_mantle',
    name: 'Мантия ветерана',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('veteran'),
    fit: WardrobeFit(width: 1.5, y: -.2, anchorY: -1),
  ),
  // ── Компаньоны ────────────────────────────────────────────────────────
  WardrobeItem(
    id: 'first_coin',
    name: 'Первая монетка',
    category: WardrobeCategory.companion,
    rarity: AchievementRarity.common,
    source: AchievementReward('first_topup'),
    fit: WardrobeFit(width: .34, x: 1.32, y: .55),
  ),
  WardrobeItem(
    id: 'dream_trophy',
    name: 'Кубок мечты',
    category: WardrobeCategory.companion,
    rarity: AchievementRarity.rare,
    source: AchievementReward('goal_done'),
    fit: WardrobeFit(width: .46, x: 1.38, y: 1.0, anchorY: 1),
  ),
  WardrobeItem(
    id: 'mini_piggy_bank',
    name: 'Мини-копилка',
    category: WardrobeCategory.companion,
    rarity: AchievementRarity.rare,
    source: AchievementReward('saved_10000'),
    fit: WardrobeFit(width: .44, x: 1.38, y: 1.0, anchorY: 1),
  ),
  WardrobeItem(
    id: 'order_robot',
    name: 'Робот порядка',
    category: WardrobeCategory.companion,
    rarity: AchievementRarity.rare,
    source: AchievementReward('order'),
    fit: WardrobeFit(width: .4, x: 1.38, y: .5),
  ),
];

/// Picture proportions (pixel sizes of the trimmed PNGs).
const wardrobeRatios = <String, double>{
  'analyst_glasses': 1024 / 365,
  'anniversary_party_cap': 980 / 886,
  'budget_master_cap': 1024 / 620,
  'champagne_sound_headphones': 1024 / 759,
  'cushion_sleep_cap': 1024 / 638,
  'cyan_pulse_headphones': 1024 / 792,
  'dream_crystal_crown': 768 / 386,
  'dream_trophy': 930 / 831,
  'finora_legend_crown': 1024 / 616,
  'fintech_visor': 1024 / 217,
  'first_coin': 667 / 671,
  'first_step_cap': 1024 / 608,
  'golden_perspective_glasses': 1024 / 382,
  'habit_flame_cap': 1024 / 615,
  'heart_glasses': 1024 / 350,
  'marathon_headband': 1024 / 403,
  'mini_piggy_bank': 751 / 734,
  'mint_buds': 1024 / 283,
  'night_cap': 882 / 467,
  'order_robot': 770 / 998,
  'organizer_helmet': 1024 / 678,
  'perfect_month_wreath': 1024 / 653,
  'punctuality_shield_cape': 1024 / 564,
  'reserve_scarf': 1024 / 681,
  'round_accounting_glasses': 1024 / 350,
  'savings_piggy_cap': 1024 / 525,
  'silver_spark_crown': 833 / 432,
  'steady_plus_top_hat': 968 / 532,
  'veteran_mantle': 1024 / 452,
  'weekly_rhythm_headphones': 1024 / 718,
};
