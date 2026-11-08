import 'achievements.dart';

/// Finora 1.46: the wardrobe — received for achievements (and, later, for
/// events and mini-games). 1.48: companions only — a coin, a trophy, a
/// piggy bank and a robot floating beside her.
///
/// The catalog is data; what the person has is [WardrobeState], stored with
/// the rest of the ledger. An item is open when its source is reached:
/// for an achievement — once that achievement is received (it is never
/// taken away, so neither is the item).

enum WardrobeCategory { companion }

/// Where an item goes; one item per slot.
enum WardrobeSlot { companion }

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
  });

  final double width, x, y, anchorX, anchorY, rotation;
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

  WardrobeSlot get slot => WardrobeSlot.companion;

  WardrobeLayer get layer => WardrobeLayer.frontAccessory;

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
    // Items taken out of the catalog (1.48: all but companions) are
    // forgotten.
    if (state.received.keys.any((id) => item(id) == null)) {
      received = {
        for (final e in state.received.entries)
          if (item(e.key) != null) e.key: e.value,
      };
    }
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

/// The 4 companions, each with its own place beside her.
const wardrobeItems = <WardrobeItem>[
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
  'dream_trophy': 930 / 831,
  'first_coin': 667 / 671,
  'mini_piggy_bank': 751 / 734,
  'order_robot': 770 / 998,
};
