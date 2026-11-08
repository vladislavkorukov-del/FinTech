import 'achievements.dart';

/// Finora 1.46: the wardrobe — things for Finora to wear, received for
/// achievements and events (and, later, mini-games). 1.47: hats, crowns,
/// capes and companions.
///
/// The catalog is data; what the person has is [WardrobeState], stored with
/// the rest of the ledger. An item is open when its source is reached:
/// for an achievement — once that achievement is received (it is never
/// taken away, so neither is the item).

enum WardrobeCategory { headwear, crown, cape, companion }

/// Where an item is worn; one item per slot. Hats and crowns share «top»
/// so they never overlap.
enum WardrobeSlot { top, cape, companion }

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

  /// Whether the event is on at [now] (opening the app then gives its item).
  bool activeAt(DateTime now) => switch (eventId) {
    // New Year: 15 December … 15 January.
    'new_year' =>
      live &&
          ((now.month == 12 && now.day >= 15) ||
              (now.month == 1 && now.day <= 15)),
    _ => false,
  };

  /// What to do to receive it.
  String? get condition => switch (eventId) {
    'new_year' => 'Загляните в Finora с 15 декабря по 15 января',
    _ => null,
  };
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
    WardrobeCategory.headwear || WardrobeCategory.crown => WardrobeSlot.top,
    WardrobeCategory.cape => WardrobeSlot.cape,
    WardrobeCategory.companion => WardrobeSlot.companion,
  };

  WardrobeLayer get layer => switch (category) {
    WardrobeCategory.headwear ||
    WardrobeCategory.crown => WardrobeLayer.headwear,
    // 1.47: capes hang behind her; the cut-out follows her sphere.
    WardrobeCategory.cape => WardrobeLayer.behindCharacter,
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
    final clock = now ?? DateTime.now();
    // Items taken out of the catalog (1.47: glasses, headphones, old capes)
    // are forgotten.
    if (state.received.keys.any((id) => item(id) == null)) {
      received = {
        for (final e in state.received.entries)
          if (item(e.key) != null) e.key: e.value,
      };
    }
    for (final i in wardrobeItems) {
      if (state.received.containsKey(i.id)) continue;
      final at = switch (i.source) {
        AchievementReward(:final achievementId) =>
          achievements.unlocked[achievementId],
        final EventReward e => e.activeAt(clock) ? clock : null,
      };
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

/// The 33 items, each with its own fit (see [WardrobeFit]).
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
  // ── Плащи (1.47: сзади, вырез — по её сфере) ────────────────────────
  WardrobeItem(
    id: 'cape_new_year',
    name: 'Новогодний плащ',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.epic,
    source: EventReward('new_year', live: true),
    fit: WardrobeFit(width: 2.086, x: 0.003, y: -0.021),
  ),
  WardrobeItem(
    id: 'cape_star_wanderer',
    name: 'Плащ звёздного странника',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.common,
    source: AchievementReward('ten_records'),
    fit: WardrobeFit(width: 2.074, x: 0.004, y: 0.017),
  ),
  WardrobeItem(
    id: 'cape_pirate_tides',
    name: 'Плащ морских приливов',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.common,
    source: AchievementReward('first_account'),
    fit: WardrobeFit(width: 2.102, x: 0.002, y: -0.014),
  ),
  WardrobeItem(
    id: 'cape_emerald_wood',
    name: 'Плащ изумрудного леса',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.common,
    source: AchievementReward('first_topup'),
    fit: WardrobeFit(width: 2.218, x: 0.004, y: -0.116),
  ),
  WardrobeItem(
    id: 'cape_sand_prophecy',
    name: 'Плащ песчаного пророчества',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.uncommon,
    source: AchievementReward('full_picture'),
    fit: WardrobeFit(width: 2.153, x: 0.015, y: 0.001),
  ),
  WardrobeItem(
    id: 'cape_scarlet_flight',
    name: 'Плащ алого полёта',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.uncommon,
    source: AchievementReward('economy'),
    fit: WardrobeFit(width: 2.208, x: 0.003, y: 0.002),
  ),
  WardrobeItem(
    id: 'cape_emerald_city',
    name: 'Плащ изумрудного города',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.uncommon,
    source: AchievementReward('no_overdue'),
    fit: WardrobeFit(width: 2.083, x: 0.005, y: -0.012),
  ),
  WardrobeItem(
    id: 'cape_starlit_academy',
    name: 'Плащ звёздной академии',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.rare,
    source: AchievementReward('analyst_10'),
    fit: WardrobeFit(width: 2.103, x: 0.005, y: -0.013),
  ),
  WardrobeItem(
    id: 'cape_digital_grid',
    name: 'Плащ цифровой сетки',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.rare,
    source: AchievementReward('order'),
    fit: WardrobeFit(width: 2.121, x: 0.003, y: -0.013),
  ),
  WardrobeItem(
    id: 'cape_neon_noir',
    name: 'Плащ «Неоновая ночь»',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.epic,
    source: AchievementReward('streak_30'),
    fit: WardrobeFit(width: 2.024, x: 0.004, y: 0.010),
  ),
  WardrobeItem(
    id: 'cape_midnight_vigil',
    name: 'Плащ полуночного дозора',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.epic,
    source: AchievementReward('cushion_3'),
    fit: WardrobeFit(width: 2.125, x: 0.001, y: -0.033),
  ),
  WardrobeItem(
    id: 'cape_frost_queen',
    name: 'Плащ снежной королевы',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('budget_12'),
    fit: WardrobeFit(width: 2.020, x: 0.009, y: 0.011),
  ),
  WardrobeItem(
    id: 'cape_firebird_rebel',
    name: 'Плащ огненной птицы',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('ideal_year'),
    fit: WardrobeFit(width: 2.068, x: 0.002, y: 0.054),
  ),
  WardrobeItem(
    id: 'cape_royal_panther',
    name: 'Плащ королевской пантеры',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('veteran'),
    fit: WardrobeFit(width: 2.080, x: 0.002, y: 0.007),
  ),
  WardrobeItem(
    id: 'cape_mystic_portal',
    name: 'Плащ мистического портала',
    category: WardrobeCategory.cape,
    rarity: AchievementRarity.legendary,
    source: AchievementReward('perfectionist'),
    fit: WardrobeFit(width: 2.114, x: 0.007, y: -0.199),
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
  'anniversary_party_cap': 980 / 886,
  'budget_master_cap': 1024 / 620,
  'cape_digital_grid': 1024 / 479,
  'cape_emerald_city': 1024 / 479,
  'cape_emerald_wood': 1024 / 518,
  'cape_firebird_rebel': 1024 / 502,
  'cape_frost_queen': 1024 / 464,
  'cape_midnight_vigil': 1024 / 470,
  'cape_mystic_portal': 1024 / 502,
  'cape_neon_noir': 1024 / 498,
  'cape_new_year': 1024 / 487,
  'cape_pirate_tides': 1024 / 470,
  'cape_royal_panther': 1024 / 517,
  'cape_sand_prophecy': 1024 / 471,
  'cape_scarlet_flight': 1024 / 466,
  'cape_star_wanderer': 1024 / 478,
  'cape_starlit_academy': 1024 / 488,
  'cushion_sleep_cap': 1024 / 638,
  'dream_crystal_crown': 768 / 386,
  'dream_trophy': 930 / 831,
  'finora_legend_crown': 1024 / 616,
  'first_coin': 667 / 671,
  'first_step_cap': 1024 / 608,
  'habit_flame_cap': 1024 / 615,
  'marathon_headband': 1024 / 403,
  'mini_piggy_bank': 751 / 734,
  'night_cap': 882 / 467,
  'order_robot': 770 / 998,
  'organizer_helmet': 1024 / 678,
  'perfect_month_wreath': 1024 / 653,
  'savings_piggy_cap': 1024 / 525,
  'silver_spark_crown': 833 / 432,
  'steady_plus_top_hat': 968 / 532,
};
