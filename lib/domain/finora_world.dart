import 'achievements.dart';
import 'finance_engine.dart';
import 'models.dart';
import 'wardrobe.dart';
import 'flow/models.dart';

import 'world_games.dart';

const _unchangedGardenGoal = Object();

/// Cosmetic economy. It never enters account, entry or analytics arithmetic.
class WorldRewardAmount {
  const WorldRewardAmount(this.xp, this.sparks);
  final int xp, sparks;
}

class WorldCosmetic {
  const WorldCosmetic(
    this.id,
    this.name,
    this.kind,
    this.price,
    this.minPoints,
    this.color,
  );
  final String id, name, kind;
  final int price, minPoints, color;
}

const worldCosmetics = <WorldCosmetic>[
  WorldCosmetic('mint', 'Мятный свет', 'background', 0, 0, 0xFF9DD6C3),
  WorldCosmetic('pearl', 'Жемчужное утро', 'background', 0, 0, 0xFFE9E0D4),
  WorldCosmetic('night', 'Лунное стекло', 'background', 30, 0, 0xFF8B9BCE),
  WorldCosmetic('garden', 'Тихий сад', 'background', 60, 50, 0xFF84B489),
  WorldCosmetic(
    'underwater',
    'Подводный дом',
    'background',
    60,
    50,
    0xFF78B9D3,
  ),
  WorldCosmetic(
    'aurora',
    'Северное сияние',
    'background',
    100,
    150,
    0xFFB5A5E6,
  ),
  WorldCosmetic('crystal', 'Мятный кристалл', 'decor', 15, 0, 0xFF9DE6D5),
  WorldCosmetic('tea', 'Жемчужная чашка', 'decor', 20, 0, 0xFFE2C7A1),
  WorldCosmetic('star', 'Парящая звезда', 'decor', 25, 0, 0xFFF1D98E),
  WorldCosmetic('plant', 'Стеклянный росток', 'decor', 35, 50, 0xFF8FCFA5),
  WorldCosmetic('moon', 'Лунный светильник', 'decor', 45, 50, 0xFFB8C0ED),
  WorldCosmetic('lantern', 'Жемчужный фонарь', 'decor', 60, 150, 0xFFE7CBB2),
];

abstract final class WorldCatalog {
  static const maxGoalRewards = 3;
  static const maxOutfits = 12;
  static const rewards = <String, WorldRewardAmount>{
    'first_payment': WorldRewardAmount(20, 30),
    'first_goal': WorldRewardAmount(20, 30),
    'categorized': WorldRewardAmount(25, 35),
    'tutorial': WorldRewardAmount(15, 20),
    'review_week': WorldRewardAmount(10, 15),
    'review_month': WorldRewardAmount(20, 25),
    'goal': WorldRewardAmount(30, 40),
    'game': WorldRewardAmount(5, 10),
    'finorio_task': WorldRewardAmount(10, 15),
    'finorio_research': WorldRewardAmount(30, 50),
    'magistrali_level': WorldRewardAmount(15, 20),
  };

  static WorldCosmetic? cosmetic(String id) =>
      worldCosmetics.where((c) => c.id == id).firstOrNull;

  /// The last *completed* calendar week, Monday to Sunday, in local time.
  static String weekKey(DateTime now) {
    final date = DateTime(now.year, now.month, now.day);
    final monday = DateTime(date.year, date.month, date.day - date.weekday + 1);
    return AchievementState.day(
      DateTime(monday.year, monday.month, monday.day - 7),
    );
  }

  /// The last completed calendar month; excludes a partial current month.
  static String monthKey(DateTime now) {
    final d = DateTime(now.year, now.month - 1);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  static WorldRewardAmount? rewardFor(String id) {
    if (rewards.containsKey(id) &&
        const {
          'first_payment',
          'first_goal',
          'categorized',
          'tutorial',
        }.contains(id)) {
      return rewards[id];
    }
    if (RegExp(r'^review:week:\d{4}-\d{2}-\d{2}$').hasMatch(id)) {
      final key = id.substring('review:week:'.length);
      final d = DateTime.tryParse(key);
      if (d != null &&
          AchievementState.day(d) == key &&
          d.weekday == DateTime.monday) {
        return rewards['review_week'];
      }
    }
    if (RegExp(r'^review:month:\d{4}-(0[1-9]|1[0-2])$').hasMatch(id)) {
      return rewards['review_month'];
    }
    if (RegExp(r'^goal_reward:[1-3]$').hasMatch(id)) return rewards['goal'];
    if (RegExp(
      r'^game:(constellation|parcel|expedition):[0-2]$',
    ).hasMatch(id)) {
      return rewards['game'];
    }
    // 1.62: «Поток» has 500 levels; each pays its first-pass reward once.
    final flow = RegExp(r'^flow:level:([1-9][0-9]{0,2}):v1$').firstMatch(id);
    if (flow != null && int.parse(flow[1]!) <= flowLevelCount) {
      return rewards['game'];
    }
    // «Магистрали»: the first delivery and every fifth company level up
    // to 100, each once.
    if (id == 'magistrali:first_delivery:v1') return rewards['game'];
    final mag = RegExp(
      r'^magistrali:level:([1-9][0-9]{0,2}):v1$',
    ).firstMatch(id);
    if (mag != null) {
      final n = int.parse(mag[1]!);
      if (n % 5 == 0 && n <= 100) return rewards['magistrali_level'];
    }
    // Finorio (1.63–1.67, removed in 1.68): its rewards already paid stay
    // valid so saved worlds keep loading.
    if (RegExp(r'^finorio:task:([1-9]|10):v1$').hasMatch(id)) {
      return rewards['finorio_task'];
    }
    if (id == 'finorio:research:logistics:v1') {
      return rewards['finorio_research'];
    }
    return null;
  }
}

class WorldReward {
  const WorldReward({
    required this.id,
    required this.date,
    required this.xp,
    required this.sparks,
  });
  final String id;
  final DateTime date;
  final int xp, sparks;
  Map<String, Object?> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'xp': xp,
    'sparks': sparks,
  };
  factory WorldReward.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    final amount = WorldCatalog.rewardFor(id);
    if (amount == null ||
        j['xp'] != amount.xp ||
        j['sparks'] != amount.sparks) {
      throw const FormatException('Некорректная награда Мира Финоры');
    }
    return WorldReward(
      id: id,
      date: DateTime.parse(j['date'] as String),
      xp: amount.xp,
      sparks: amount.sparks,
    );
  }
}

class WorldOutfit {
  const WorldOutfit({
    required this.id,
    required this.name,
    required this.equipped,
    required this.date,
  });
  final String id, name;
  final Map<WardrobeSlot, String> equipped;
  final DateTime date;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'date': date.toIso8601String(),
    'equipped': {for (final e in equipped.entries) e.key.name: e.value},
  };
  factory WorldOutfit.fromJson(Map<String, dynamic> j) {
    final slots = <WardrobeSlot, String>{};
    for (final e in (j['equipped'] as Map? ?? const {}).entries) {
      final slot = WardrobeSlot.values
          .where((s) => s.name == e.key)
          .firstOrNull;
      final item = e.value is String ? Wardrobe.item(e.value as String) : null;
      if (slot != null && item != null && item.slot == slot) {
        slots[slot] = item.id;
      }
    }
    return WorldOutfit(
      id: j['id'] as String,
      name: j['name'] as String,
      equipped: slots,
      date: DateTime.parse(j['date'] as String),
    );
  }
}

class WorldMemory {
  const WorldMemory({
    required this.id,
    required this.date,
    required this.title,
    required this.description,
    this.asset,
    this.goalId,
    this.amountMinor,
    this.currency,
  });
  final String id, title, description;
  final DateTime date;
  final String? asset, goalId, currency;
  final int? amountMinor;

  /// Safe foundation for future card exports: financial and personal goal data
  /// are excluded before an export renderer ever sees the record.
  Map<String, Object?> toJson({bool hidePrivate = false}) {
    final private = hidePrivate && goalId != null;
    return {
      'id': private ? 'goal-memory' : id,
      'date': date.toIso8601String(),
      'title': private ? 'Цель достигнута' : title,
      'description': private
          ? 'В саду Финоры распустилось новое растение.'
          : description,
      if (asset != null) 'asset': asset,
      if (!hidePrivate && goalId != null) 'goalId': goalId,
      if (!hidePrivate && amountMinor != null) 'amountMinor': amountMinor,
      if (!hidePrivate && currency != null) 'currency': currency,
    };
  }

  factory WorldMemory.fromJson(Map<String, dynamic> j) => WorldMemory(
    id: j['id'] as String,
    date: DateTime.parse(j['date'] as String),
    title: j['title'] as String,
    description: j['description'] as String? ?? '',
    // Do not accept remote URLs, file paths or arbitrary app assets from backup.
    asset: _safeAsset(j['asset']),
    goalId: j['goalId'] as String?,
    amountMinor: (j['amountMinor'] as num?)?.toInt(),
    currency: j['currency'] as String?,
  );
}

String? _safeAsset(Object? value) {
  if (value is! String) return null;
  if (wardrobeItems.any((i) => i.asset == value)) return value;
  if (achievementDefinitions.any(
    (a) => value == 'assets/finora/achievements/${a.id}.webp',
  )) {
    return value;
  }
  return null;
}

class WorldState {
  const WorldState({
    this.rewards = const {},
    this.purchases = const {},
    this.background = 'mint',
    this.decor = const {},
    this.outfits = const [],
    this.completedGoals = const {},
    this.memories = const {},
    this.games = const {},
    this.reducedMotion = false,
    this.remarks = true,
    this.hidePrivate = true,
    this.gardenGoalId,
    this.flow = const FlowProgress(),
  });
  final Map<String, WorldReward> rewards;
  final Set<String> purchases;
  final String background;
  final Map<String, String> decor;
  final List<WorldOutfit> outfits;
  final Set<String> completedGoals;
  final Map<String, WorldMemory> memories;
  final Map<String, List<int>> games;
  final bool reducedMotion, remarks, hidePrivate;
  final String? gardenGoalId;
  final FlowProgress flow;
  int get experience => rewards.values.fold(0, (n, r) => n + r.xp);
  int get earned => rewards.values.fold(0, (n, r) => n + r.sparks);
  int get sparks =>
      earned -
      purchases.fold(0, (n, id) => n + (WorldCatalog.cosmetic(id)?.price ?? 0));

  WorldState copyWith({
    Map<String, WorldReward>? rewards,
    Set<String>? purchases,
    String? background,
    Map<String, String>? decor,
    List<WorldOutfit>? outfits,
    Set<String>? completedGoals,
    Map<String, WorldMemory>? memories,
    Map<String, List<int>>? games,
    bool? reducedMotion,
    bool? remarks,
    bool? hidePrivate,
    Object? gardenGoalId = _unchangedGardenGoal,
    FlowProgress? flow,
  }) => WorldState(
    rewards: rewards ?? this.rewards,
    purchases: purchases ?? this.purchases,
    background: background ?? this.background,
    decor: decor ?? this.decor,
    outfits: outfits ?? this.outfits,
    completedGoals: completedGoals ?? this.completedGoals,
    memories: memories ?? this.memories,
    games: games ?? this.games,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    remarks: remarks ?? this.remarks,
    hidePrivate: hidePrivate ?? this.hidePrivate,
    gardenGoalId: identical(gardenGoalId, _unchangedGardenGoal)
        ? this.gardenGoalId
        : gardenGoalId as String?,
    flow: flow ?? this.flow,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'rewards': {for (final e in rewards.entries) e.key: e.value.toJson()},
    'purchases': purchases.toList()..sort(),
    'background': background,
    'decor': decor,
    'outfits': outfits.map((o) => o.toJson()).toList(),
    'completedGoals': completedGoals.toList()..sort(),
    'memories': {for (final e in memories.entries) e.key: e.value.toJson()},
    'games': games,
    'reducedMotion': reducedMotion,
    'remarks': remarks,
    'hidePrivate': hidePrivate,
    'gardenGoalId': gardenGoalId,
    'flow': flow.toJson(),
  };

  factory WorldState.fromJson(Map<String, dynamic> j) {
    final rewards = <String, WorldReward>{};
    for (final e in (j['rewards'] as Map? ?? const {}).entries) {
      final reward = WorldReward.fromJson(
        Map<String, dynamic>.from(e.value as Map),
      );
      if (reward.id != e.key) {
        throw const FormatException('Несовпадающий ключ награды');
      }
      rewards[reward.id] = reward;
    }
    final purchases = <String>{};
    for (final id in j['purchases'] as List? ?? const []) {
      if (id is String && WorldCatalog.cosmetic(id) != null) purchases.add(id);
    }
    final memories = <String, WorldMemory>{};
    for (final e in (j['memories'] as Map? ?? const {}).entries) {
      final memory = WorldMemory.fromJson(
        Map<String, dynamic>.from(e.value as Map),
      );
      if (memory.id == e.key) memories[memory.id] = memory;
    }
    final outfits = [
      for (final o in j['outfits'] as List? ?? const [])
        WorldOutfit.fromJson(Map<String, dynamic>.from(o as Map)),
    ];
    if (outfits.length > WorldCatalog.maxOutfits ||
        outfits.map((o) => o.id).toSet().length != outfits.length) {
      throw const FormatException('Некорректный список образов');
    }
    final games = <String, List<int>>{};
    for (final e in (j['games'] as Map? ?? const {}).entries) {
      if (e.key is String &&
          e.value is List &&
          (e.value as List).every((v) => v is int)) {
        final moves = List<int>.from(e.value as List);
        if (WorldGames.validate(e.key as String, moves)) {
          games[e.key as String] = moves;
        }
      }
    }
    var state = WorldState(
      rewards: rewards,
      purchases: purchases,
      outfits: outfits,
      memories: memories,
      games: games,
      completedGoals: {
        for (final id in j['completedGoals'] as List? ?? const [])
          if (id is String) id,
      },
      reducedMotion: j['reducedMotion'] as bool? ?? false,
      remarks: j['remarks'] as bool? ?? true,
      hidePrivate: j['hidePrivate'] as bool? ?? true,
      gardenGoalId: j['gardenGoalId'] is String
          ? j['gardenGoalId'] as String
          : null,
      flow: _readFlow(j['flow']),
    );
    if (state.sparks < 0) {
      throw const FormatException('Недостаточно искр в сохранении');
    }
    final background = j['background'] as String? ?? 'mint';
    final decor = <String, String>{};
    for (final e in (j['decor'] as Map? ?? const {}).entries) {
      if (const {'left', 'right', 'shelf'}.contains(e.key) &&
          e.value is String &&
          WorldEngine.owns(state, e.value as String) &&
          WorldCatalog.cosmetic(e.value as String)?.kind == 'decor') {
        decor[e.key as String] = e.value as String;
      }
    }
    state = state.copyWith(
      background:
          WorldEngine.owns(state, background) &&
              WorldCatalog.cosmetic(background)?.kind == 'background'
          ? background
          : 'mint',
      decor: decor,
    );
    return state;
  }

  static FlowProgress _readFlow(Object? raw) {
    if (raw is! Map) return const FlowProgress();
    try {
      return FlowProgress.fromJson(Map<String, dynamic>.from(raw));
    } on Object {
      // A broken optional game snapshot cannot erase finances or old rewards.
      return const FlowProgress();
    }
  }
}

class WorldCollection {
  const WorldCollection(this.id, this.name, this.itemIds);
  final String id, name;
  final List<String> itemIds;
  int count(WardrobeState state) =>
      itemIds.where(state.received.containsKey).length;
  bool completed(WardrobeState state) => count(state) == itemIds.length;
}

/// References, not renamed items or a second wardrobe catalog.
const worldCollections = [
  WorldCollection('stars', 'Звёздный бухгалтер', [
    'pearl_owl',
    'star_wanderer',
    'starlit_academy',
  ]),
  WorldCollection('tea', 'Чайный вечер', [
    'lilac_ghost',
    'red_panda',
    'moon_rabbit',
  ]),
  WorldCollection('garden', 'Хранитель сада', [
    'investment_sprout',
    'forest_frog',
    'emerald_wood',
  ]),
  WorldCollection('polar', 'Полярная экспедиция', [
    'moon_cat',
    'pearl_koi',
    'frost_queen',
  ]),
];

class WorldPlant {
  const WorldPlant._(this.goal, this.savedMinor, this.ratio, this.stage);
  factory WorldPlant.of(Goal goal, List<FinanceEntry> entries) {
    final saved = FinanceEngine.goalSaved(goal, entries);
    final ratio = goal.targetMinor <= 0
        ? 0.0
        : (saved / goal.targetMinor).clamp(0.0, 1.0);
    final stage = ratio >= 1
        ? 4
        : ratio >= .75
        ? 3
        : ratio >= .4
        ? 2
        : ratio > 0
        ? 1
        : 0;
    return WorldPlant._(goal, saved, ratio, stage);
  }
  final Goal goal;
  final int savedMinor, stage;
  final double ratio;

  /// Preserve the existing growth milestones and add an opening-flower frame
  /// within the former bud interval. Financial completion remains unchanged.
  int get visualStage => switch (stage) {
    0 => 0,
    1 => 1,
    2 => 2,
    3 => ratio >= .8 ? 4 : 3,
    _ => 5,
  };
  String get stageName =>
      const ['Семя', 'Росток', 'Листья', 'Бутон', 'Цветение'][stage];
}

/// Pure state transitions, committed with the financial snapshot by its existing
/// repository/controller transaction. All award IDs are bounded or period-scoped.
abstract final class WorldEngine {
  static bool owns(WorldState state, String id) {
    final item = WorldCatalog.cosmetic(id);
    return item != null && (item.price == 0 || state.purchases.contains(id));
  }

  static WorldState reward(
    WorldState state,
    String eventId, {
    required DateTime now,
  }) {
    if (state.rewards.containsKey(eventId)) return state;
    final amount = WorldCatalog.rewardFor(eventId);
    if (amount == null) {
      throw const FormatException('Неизвестное событие награды');
    }
    if ((eventId.startsWith('review:week:') &&
            eventId != 'review:week:${WorldCatalog.weekKey(now)}') ||
        (eventId.startsWith('review:month:') &&
            eventId != 'review:month:${WorldCatalog.monthKey(now)}')) {
      throw const FormatException('Можно подтвердить только завершённый обзор');
    }
    return state.copyWith(
      rewards: {
        ...state.rewards,
        eventId: WorldReward(
          id: eventId,
          date: now,
          xp: amount.xp,
          sparks: amount.sparks,
        ),
      },
    );
  }

  static WorldState purchase(
    WorldState state,
    String id, {
    required int points,
  }) {
    final item = WorldCatalog.cosmetic(id);
    if (item == null) {
      throw const FormatException('Такого декора нет в каталоге');
    }
    if (owns(state, id)) return state;
    if (points < item.minPoints) {
      throw const FormatException('Нужен следующий уровень опыта');
    }
    if (state.sparks < item.price) {
      throw const FormatException('Недостаточно искр');
    }
    return state.copyWith(purchases: {...state.purchases, id});
  }

  static WorldState configure(
    WorldState state, {
    required String background,
    required Map<String, String> decor,
    required DateTime now,
  }) {
    if (!owns(state, background) ||
        WorldCatalog.cosmetic(background)?.kind != 'background') {
      throw const FormatException('Этот фон пока не открыт');
    }
    for (final e in decor.entries) {
      if (!const {'left', 'right', 'shelf'}.contains(e.key) ||
          !owns(state, e.value) ||
          WorldCatalog.cosmetic(e.value)?.kind != 'decor') {
        throw const FormatException('Этот декор нельзя разместить');
      }
    }
    final changed =
        state.background != background || !_sameMap(state.decor, decor);
    var updated = state.copyWith(background: background, decor: Map.of(decor));
    if (changed && !updated.memories.containsKey('home:first')) {
      updated = _memory(
        updated,
        WorldMemory(
          id: 'home:first',
          date: now,
          title: 'Первый оформленный дом',
          description: 'У Финоры появилось своё уютное место.',
          asset: 'assets/finora/achievements/first_step.webp',
        ),
      );
    }
    return updated;
  }

  static WorldState saveOutfit(WorldState state, WorldOutfit outfit) {
    final name = outfit.name.trim();
    if (outfit.id.trim().isEmpty || name.isEmpty || name.length > 60) {
      throw const FormatException('Введите название образа до 60 символов');
    }
    for (final e in outfit.equipped.entries) {
      if (Wardrobe.item(e.value)?.slot != e.key) {
        throw const FormatException('Предмет не подходит к этому образу');
      }
    }
    final list = state.outfits.where((o) => o.id != outfit.id).toList();
    if (list.length >= WorldCatalog.maxOutfits) {
      throw const FormatException('Можно сохранить до 12 образов');
    }
    return state.copyWith(
      outfits: [
        ...list,
        WorldOutfit(
          id: outfit.id,
          name: name,
          equipped: Map.of(outfit.equipped),
          date: outfit.date,
        ),
      ],
    );
  }

  static WorldState removeOutfit(WorldState state, String id) =>
      state.copyWith(outfits: state.outfits.where((o) => o.id != id).toList());

  static WorldState sync(
    WorldState state,
    FinanceData before,
    FinanceData after, {
    required DateTime now,
    bool events = true,
  }) {
    var updated = state;
    final selectedGoal =
        state.gardenGoalId == null ||
            after.goals.any((g) => g.id == state.gardenGoalId)
        ? state.gardenGoalId
        : after.goals.firstOrNull?.id;
    if (selectedGoal != state.gardenGoalId) {
      updated = updated.copyWith(gardenGoalId: selectedGoal);
    }
    // Demo data is never a source of spendable rewards or completed real goals.
    if (!after.demo) {
      if (events &&
          after.recurring.any(
            (r) =>
                r.enabled &&
                r.kind == EntryKind.expense &&
                r.paymentType == 'mandatory',
          )) {
        updated = reward(updated, 'first_payment', now: now);
      }
      if (events && after.goals.isNotEmpty) {
        updated = reward(updated, 'first_goal', now: now);
      }
      if (events && !before.demo) {
        final unresolved = before.entries
            .where((e) => _needsCategory(e, before))
            .toList();
        // Removing an uncategorised operation is not resolving it.
        if (unresolved.isNotEmpty &&
            unresolved.every(
              (old) => after.entries.any(
                (e) =>
                    e.id == old.id &&
                    e.kind == old.kind &&
                    e.status == 'posted' &&
                    !_needsCategory(e, after),
              ),
            ) &&
            !after.entries.any((e) => _needsCategory(e, after))) {
          updated = reward(updated, 'categorized', now: now);
        }
      }
      for (final goal in after.goals) {
        if (updated.completedGoals.contains(goal.id) ||
            FinanceEngine.goalSaved(goal, after.entries) < goal.targetMinor) {
          continue;
        }
        final completed = {...updated.completedGoals, goal.id};
        // Finite lifetime milestones prevent deletion/recreation farming.
        final milestone = completed.length;
        updated = updated.copyWith(completedGoals: completed);
        if (events && milestone <= WorldCatalog.maxGoalRewards) {
          updated = reward(updated, 'goal_reward:$milestone', now: now);
        }
        updated = _memory(
          updated,
          WorldMemory(
            id: 'goal:${goal.id}',
            date: now,
            title: goal.name,
            description: 'Цель достигнута. В саду распустилось новое растение.',
            asset: 'assets/finora/achievements/goal_done.webp',
            goalId: goal.id,
            amountMinor: FinanceEngine.goalSaved(goal, after.entries),
            currency: goal.currency,
          ),
        );
      }
    }
    final pet = after.wardrobe.equipped[WardrobeSlot.companion];
    final petItem = pet == null ? null : Wardrobe.item(pet);
    if (petItem != null && after.wardrobe.received.containsKey(petItem.id)) {
      updated = _memory(
        updated,
        WorldMemory(
          id: 'pet:first',
          date: now,
          title: 'Первый выбранный питомец',
          description: petItem.name,
          asset: petItem.asset,
        ),
      );
    }
    for (final collection in worldCollections) {
      if (!collection.completed(after.wardrobe)) continue;
      updated = _memory(
        updated,
        WorldMemory(
          id: 'collection:${collection.id}',
          date: now,
          title: collection.name,
          description: 'Коллекция собрана.',
          asset: Wardrobe.item(collection.itemIds.first)?.asset,
        ),
      );
    }
    for (final definition in achievementDefinitions) {
      if (definition.rarity.index < AchievementRarity.rare.index) continue;
      final at = after.achievements.unlocked[definition.id];
      if (at == null) continue;
      updated = _memory(
        updated,
        WorldMemory(
          id: 'achievement:${definition.id}',
          date: at,
          title: definition.title,
          description: 'Получено редкое достижение.',
          asset: 'assets/finora/achievements/${definition.id}.webp',
        ),
      );
    }
    return updated;
  }

  /// Union immutable event receipts, never totals. Keep local cosmetics and
  /// refuse incoming conflicting purchases that would overspend merged earnings.
  static WorldState merge(WorldState local, WorldState incoming) {
    final rewards = {...incoming.rewards, ...local.rewards};
    var merged = local.copyWith(
      rewards: rewards,
      completedGoals: {...local.completedGoals, ...incoming.completedGoals},
      memories: {...incoming.memories, ...local.memories},
      outfits: [
        ...local.outfits,
        ...incoming.outfits.where(
          (o) => !local.outfits.any((l) => l.id == o.id),
        ),
      ].take(WorldCatalog.maxOutfits).toList(),
      games: {...incoming.games, ...local.games},
      gardenGoalId: local.gardenGoalId ?? incoming.gardenGoalId,
      flow: FlowProgress.merge(local.flow, incoming.flow),
    );
    final incomingIds = incoming.purchases.toList()..sort();
    for (final id in incomingIds) {
      final cosmetic = WorldCatalog.cosmetic(id);
      if (cosmetic != null &&
          !merged.purchases.contains(id) &&
          merged.sparks >= cosmetic.price) {
        merged = merged.copyWith(purchases: {...merged.purchases, id});
      }
    }
    // A first restore into an empty world adopts its scene and preferences.
    final pristine =
        local.rewards.isEmpty &&
        local.purchases.isEmpty &&
        local.memories.isEmpty &&
        local.outfits.isEmpty &&
        local.decor.isEmpty &&
        local.background == 'mint' &&
        local.games.isEmpty &&
        local.flow.results.isEmpty &&
        local.flow.session == null;
    if (pristine) {
      merged = merged.copyWith(
        background: owns(merged, incoming.background)
            ? incoming.background
            : 'mint',
        decor: {
          for (final e in incoming.decor.entries)
            if (owns(merged, e.value)) e.key: e.value,
        },
        reducedMotion: incoming.reducedMotion,
        remarks: incoming.remarks,
        hidePrivate: incoming.hidePrivate,
      );
    }
    return merged;
  }

  static WorldState _memory(WorldState state, WorldMemory memory) =>
      state.memories.containsKey(memory.id)
      ? state
      : state.copyWith(memories: {...state.memories, memory.id: memory});

  static bool _needsCategory(FinanceEntry entry, FinanceData data) {
    if (entry.status != 'posted' || entry.kind == EntryKind.transfer) {
      return false;
    }
    final c = data.categories
        .where((c) => c.id == entry.categoryId)
        .firstOrNull;
    if (c == null) return true;
    final name = c.name.trim().toLowerCase();
    return const {
      'прочее',
      'другое',
      'other',
      'uncategorized',
      'без категории',
    }.contains(name);
  }

  static bool _sameMap(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
