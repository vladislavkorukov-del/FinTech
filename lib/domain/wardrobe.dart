import 'achievements.dart';

part 'wardrobe_imported.dart';

/// The existing wardrobe, extended with the supplied companion and cape pack.
/// Legacy items and their rewards remain unchanged.
///
/// The catalog is data; what the person has is [WardrobeState], stored with
/// the rest of the ledger. An item is open when its source is reached:
/// for an achievement — once that achievement is received (it is never
/// taken away, so neither is the item).

enum WardrobeCategory { companion, cape }

/// Where an item goes; one item per slot.
enum WardrobeSlot { companion, cape }

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

  /// Existing 1.47 event policy; no new event or reward condition is added.
  bool activeAt(DateTime now) => switch (eventId) {
    'new_year' =>
      live &&
          ((now.month == 12 && now.day >= 15) ||
              (now.month == 1 && now.day <= 15)),
    _ => false,
  };

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
    this.assetPath,
    this.aspectRatio,
  });

  final String id, name;
  final WardrobeCategory category;
  final AchievementRarity rarity;
  final WardrobeSource source;
  final WardrobeFit fit;

  /// Shown as «???» until received (a secret achievement or a future event).
  final bool secret;
  final String? assetPath;
  final double? aspectRatio;

  String get asset => assetPath ?? 'assets/finora/wardrobe/$id.png';

  /// Width ÷ height of the picture (its transparent margins trimmed).
  double get ratio => aspectRatio ?? wardrobeRatios[id] ?? 1;

  WardrobeSlot get slot => category == WardrobeCategory.cape
      ? WardrobeSlot.cape
      : WardrobeSlot.companion;

  WardrobeLayer get layer => category == WardrobeCategory.cape
      ? WardrobeLayer.behindCharacter
      : WardrobeLayer.frontAccessory;

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
      if (at != null) {
        final id = Wardrobe.canonicalId('${e.key}');
        final previous = received[id];
        if (previous == null || at.isBefore(previous)) received[id] = at;
      }
    }
    final equipped = <WardrobeSlot, String>{};
    for (final e in (j['equipped'] as Map? ?? const {}).entries) {
      final slot = WardrobeSlot.values
          .where((s) => s.name == e.key)
          .firstOrNull;
      if (slot != null && e.value is String) {
        equipped[slot] = Wardrobe.canonicalId(e.value as String);
      }
    }
    return WardrobeState(received: received, equipped: equipped);
  }
}

abstract final class Wardrobe {
  static String canonicalId(String id) => legacyCapeAliases[id] ?? id;

  static WardrobeItem? item(String id) =>
      wardrobeItems.where((i) => i.id == canonicalId(id)).firstOrNull;

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
    final normalized = <String, DateTime>{};
    var receivedChanged = false;
    for (final e in state.received.entries) {
      final id = canonicalId(e.key);
      if (item(id) == null) {
        receivedChanged = true;
        continue;
      }
      final previous = normalized[id];
      if (previous == null || e.value.isBefore(previous)) {
        normalized[id] = e.value;
      }
      if (id != e.key || previous != null) receivedChanged = true;
    }
    Map<String, DateTime>? received = receivedChanged ? normalized : null;
    final clock = now ?? DateTime.now();
    for (final i in wardrobeItems) {
      if ((received ?? state.received).containsKey(i.id)) continue;
      final at = switch (i.source) {
        AchievementReward(:final achievementId) =>
          achievements.unlocked[achievementId],
        final EventReward e => e.activeAt(clock) ? clock : null,
      };
      if (at == null) continue;
      (received ??= {...state.received})[i.id] = at;
    }
    // Canonicalize historical cape IDs; one received item per matching slot.
    final equipped = <WardrobeSlot, String>{};
    for (final e in state.equipped.entries) {
      final id = canonicalId(e.value);
      if ((received ?? state.received).containsKey(id) &&
          item(id)?.slot == e.key) {
        equipped[e.key] = id;
      }
    }
    final equippedChanged =
        equipped.length != state.equipped.length ||
        equipped.entries.any((e) => state.equipped[e.key] != e.value);
    if (received == null && !equippedChanged) return state;
    return WardrobeState(
      received: received ?? state.received,
      equipped: equipped,
    );
  }

  /// Puts [itemId] on, taking off whatever was in its slot.
  static WardrobeState wear(WardrobeState state, String itemId) {
    final i = item(itemId);
    if (i == null || !state.received.containsKey(i.id)) {
      throw const FormatException('Этот предмет ещё не открыт');
    }
    return state.copyWith(equipped: {...state.equipped, i.slot: i.id});
  }

  static WardrobeState takeOff(WardrobeState state, WardrobeSlot slot) =>
      state.copyWith(
        equipped: {
          for (final e in state.equipped.entries)
            if (e.key != slot) e.key: e.value,
        },
      );

  /// What is worn, back to front.
  static List<WardrobeItem> worn(WardrobeState state) => [
    for (final e in state.equipped.entries)
      if (item(e.value)?.slot == e.key) ?item(e.value),
  ]..sort((a, b) => a.layer.index.compareTo(b.layer.index));
}

/// Legacy companions remain owned and usable; the supplied pack is additive.
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
  ...importedWardrobeItems,
];

/// Picture proportions (pixel sizes of the trimmed PNGs).
const wardrobeRatios = <String, double>{
  'dream_trophy': 930 / 831,
  'first_coin': 667 / 671,
  'mini_piggy_bank': 751 / 734,
  'order_robot': 770 / 998,
};
