import 'dart:convert';

import 'package:finora/domain/achievements.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/finora_world.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 8, 12);
const ledger = FinanceData(
  accounts: [Account(id: 'a', name: 'Карта', openingMinor: 100000)],
  members: [Member(id: 'me', name: 'Я')],
  categories: [Category(id: 'food', name: 'Продукты', kind: EntryKind.expense)],
);
FinanceEntry entry(
  String id, {
  String? category,
  EntryKind kind = EntryKind.expense,
  String? goal,
  int amount = 1000,
  String status = 'posted',
}) => FinanceEntry(
  id: id,
  kind: kind,
  amountMinor: amount,
  currency: 'RUB',
  accountId: 'a',
  date: now,
  categoryId: category,
  toGoalId: goal,
  status: status,
);
WorldState grant(WorldState state, String id) =>
    WorldEngine.reward(state, id, now: now);

void main() {
  test(
    'empty old JSON needs no migration and has no manufactured currency',
    () {
      final old = WorldState.fromJson({});
      expect(old.experience, 0);
      expect(old.sparks, 0);
      expect(old.background, 'mint');
      expect(old.remarks, isTrue);
      expect(old.reducedMotion, isFalse);
      expect(old.hidePrivate, isTrue);
      expect(WorldEngine.sync(old, ledger, ledger, now: now).rewards, isEmpty);
    },
  );

  test(
    'explicit event receipts are idempotent and cannot be arbitrary IDs',
    () {
      final state = grant(const WorldState(), 'tutorial');
      expect(state.experience, 15);
      expect(state.sparks, 20);
      expect(identical(grant(state, 'tutorial'), state), isTrue);
      expect(() => grant(state, 'transaction:1'), throwsFormatException);
      expect(() => grant(state, 'game:constellation:3'), throwsFormatException);
      expect(() => grant(state, 'goal_reward:4'), throwsFormatException);
    },
  );

  test('reviews are bounded by last completed calendar week/month', () {
    final at = DateTime(2027, 1, 1, 8);
    expect(WorldCatalog.weekKey(at), '2026-12-21');
    expect(WorldCatalog.monthKey(at), '2026-12');
    final a = WorldEngine.reward(
      const WorldState(),
      'review:week:2026-12-21',
      now: at,
    );
    final b = WorldEngine.reward(a, 'review:month:2026-12', now: at);
    expect(b.sparks, 40);
    expect(
      () => WorldEngine.reward(b, 'review:week:2026-12-28', now: at),
      throwsFormatException,
    );
    expect(
      () => WorldEngine.reward(b, 'review:month:2027-01', now: at),
      throwsFormatException,
    );
    expect(WorldCatalog.rewardFor('review:week:2026-11-31'), isNull);
    expect(WorldCatalog.rewardFor('review:week:2026-11-08'), isNull);
    // Historical receipts remain readable after their eligible period passes.
    final loaded = WorldState.fromJson(
      jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>,
    );
    expect(loaded.rewards.length, 2);
    expect(loaded.sparks, 40);
  });

  test(
    'first mandatory payment/goal rewards are lifetime events, no demo awards',
    () {
      final next = ledger.copyWith(
        goals: const [Goal(id: 'g', name: 'Отпуск', targetMinor: 10000)],
        recurring: [
          RecurringRule(
            id: 'rent',
            name: 'Аренда',
            accountId: 'a',
            amountMinor: 10000,
            nextDate: now,
          ),
        ],
      );
      var state = WorldEngine.sync(const WorldState(), ledger, next, now: now);
      expect(
        state.rewards.keys,
        unorderedEquals(['first_payment', 'first_goal']),
      );
      expect(state.sparks, 60);
      state = WorldEngine.sync(state, next, ledger, now: now);
      state = WorldEngine.sync(state, ledger, next, now: now);
      expect(state.rewards.length, 2);
      expect(state.sparks, 60);
      final demo = WorldEngine.sync(
        const WorldState(),
        ledger,
        next.copyWith(demo: true),
        now: now,
      );
      expect(demo.rewards, isEmpty);
      final subscription = next.copyWith(
        goals: [],
        recurring: [
          next.recurring.single.copyWith(paymentType: 'subscription'),
        ],
      );
      expect(
        WorldEngine.sync(
          const WorldState(),
          ledger,
          subscription,
          now: now,
        ).rewards,
        isEmpty,
      );
    },
  );

  test(
    'categorisation requires resolving all posted entries without deleting them',
    () {
      final before = ledger.copyWith(entries: [entry('one'), entry('two')]);
      final partial = before.copyWith(
        entries: [
          entry('one', category: 'food'),
          entry('two'),
        ],
      );
      expect(
        WorldEngine.sync(const WorldState(), before, partial, now: now).rewards,
        isEmpty,
      );
      final removed = before.copyWith(
        entries: [entry('one', category: 'food')],
      );
      expect(
        WorldEngine.sync(const WorldState(), before, removed, now: now).rewards,
        isEmpty,
      );
      final movedToPending = before.copyWith(
        entries: [
          entry('one', category: 'food', status: 'pending'),
          entry('two', category: 'food'),
        ],
      );
      expect(
        WorldEngine.sync(
          const WorldState(),
          before,
          movedToPending,
          now: now,
        ).rewards,
        isEmpty,
      );
      final resolved = before.copyWith(
        entries: [
          entry('one', category: 'food'),
          entry('two', category: 'food'),
        ],
      );
      final state = WorldEngine.sync(
        const WorldState(),
        before,
        resolved,
        now: now,
      );
      expect(state.rewards.keys, ['categorized']);
      expect(
        WorldEngine.sync(state, before, resolved, now: now).sparks,
        state.sparks,
      );
      final createdCategorized = WorldEngine.sync(
        const WorldState(),
        ledger,
        resolved,
        now: now,
      );
      expect(createdCategorized.rewards, isEmpty);
    },
  );

  test(
    'goal stages use true saved percentage including posted contributions',
    () {
      const goal = Goal(
        id: 'g',
        name: 'Цель',
        targetMinor: 10000,
        savedMinor: 1000,
      );
      final contribution = entry(
        'transfer',
        kind: EntryKind.transfer,
        goal: 'g',
        amount: 3000,
      );
      final plant = WorldPlant.of(goal, [
        contribution,
        contribution.copyWith(id: 'pending', status: 'pending'),
      ]);
      expect(plant.savedMinor, 4000);
      expect(plant.ratio, .4);
      expect(plant.stage, 2);
      final scaled = WorldPlant.of(
        goal.copyWith(targetMinor: 100000, savedMinor: 40000),
        [],
      );
      expect(scaled.stage, plant.stage);
      expect(WorldPlant.of(goal.copyWith(savedMinor: 20000), []).ratio, 1);
      expect(WorldPlant.of(goal.copyWith(savedMinor: 0), []).stage, 0);
    },
  );

  test(
    'completed goals keep cosmetic rewards through decrease/delete/recreate, finite milestones',
    () {
      var state = const WorldState();
      for (var n = 0; n < 8; n++) {
        final next = ledger.copyWith(
          goals: [
            Goal(
              id: 'g$n',
              name: 'Мечта $n',
              targetMinor: 10000,
              savedMinor: 10000,
            ),
          ],
        );
        state = WorldEngine.sync(state, ledger, next, now: now);
        state = WorldEngine.sync(
          state,
          next,
          next.copyWith(goals: [next.goals.single.copyWith(savedMinor: 0)]),
          now: now,
        );
        state = WorldEngine.sync(state, next, ledger, now: now);
      }
      expect(state.completedGoals.length, 8);
      expect(
        state.rewards.keys.where((k) => k.startsWith('goal_reward:')).length,
        3,
      );
      expect(state.sparks, 30 + 3 * 40);
      expect(state.memories.keys.where((k) => k.startsWith('goal:')).length, 8);
      final previous = state.sparks;
      state = WorldEngine.sync(
        state,
        ledger,
        ledger.copyWith(
          goals: const [
            Goal(id: 'g0', name: 'Снова', targetMinor: 1, savedMinor: 1),
          ],
        ),
        now: now,
      );
      expect(state.sparks, previous);
    },
  );

  test('imported completed goals do not mint replayable rewards', () {
    final imported = ledger.copyWith(
      goals: const [
        Goal(id: 'g', name: 'Цель', targetMinor: 10000, savedMinor: 10000),
      ],
    );
    var state = WorldEngine.sync(
      const WorldState(),
      ledger,
      imported,
      now: now,
      events: false,
    );
    expect(state.rewards, isEmpty);
    expect(state.completedGoals, {'g'});
    state = WorldEngine.sync(state, imported, imported, now: now);
    expect(state.rewards, isNot(contains('goal_reward:1')));
  });

  test('shop enforces ownership, points, funds and charges only once', () {
    final state = grant(const WorldState(), 'first_payment');
    expect(
      () => WorldEngine.purchase(state, 'garden', points: 100),
      throwsFormatException,
    );
    expect(
      () => WorldEngine.purchase(state, 'plant', points: 0),
      throwsFormatException,
    );
    expect(
      () => WorldEngine.purchase(state, 'unknown', points: 100),
      throwsFormatException,
    );
    final bought = WorldEngine.purchase(state, 'crystal', points: 0);
    expect(bought.sparks, 15);
    expect(
      identical(WorldEngine.purchase(bought, 'crystal', points: 0), bought),
      isTrue,
    );
    expect(WorldEngine.owns(bought, 'mint'), isTrue);
    expect(WorldEngine.owns(bought, 'crystal'), isTrue);
    expect(WorldEngine.owns(bought, 'night'), isFalse);
  });

  test('home accepts only owned cosmetics and preserves first memory', () {
    var state = grant(const WorldState(), 'first_payment');
    state = WorldEngine.purchase(state, 'crystal', points: 0);
    state = WorldEngine.configure(
      state,
      background: 'pearl',
      decor: {'left': 'crystal'},
      now: now,
    );
    expect(state.background, 'pearl');
    expect(state.decor, {'left': 'crystal'});
    final first = state.memories['home:first'];
    state = WorldEngine.configure(
      state,
      background: 'mint',
      decor: {},
      now: now.add(const Duration(days: 1)),
    );
    expect(state.memories['home:first'], same(first));
    expect(
      () => WorldEngine.configure(
        state,
        background: 'night',
        decor: {},
        now: now,
      ),
      throwsFormatException,
    );
    expect(
      () => WorldEngine.configure(
        state,
        background: 'mint',
        decor: {'left': 'tea'},
        now: now,
      ),
      throwsFormatException,
    );
    expect(
      () => WorldEngine.configure(
        state,
        background: 'mint',
        decor: {'outside': 'crystal'},
        now: now,
      ),
      throwsFormatException,
    );
    expect(
      () => WorldEngine.configure(
        state,
        background: 'crystal',
        decor: {},
        now: now,
      ),
      throwsFormatException,
    );
  });

  test(
    'merge unions receipts, does not duplicate earnings and cannot overspend',
    () {
      var common = grant(const WorldState(), 'first_payment');
      final local = WorldEngine.purchase(
        common,
        'crystal',
        points: 0,
      ); // 15 left
      final remote = WorldEngine.purchase(common, 'tea', points: 0); // 10 left
      var merged = WorldEngine.merge(local, remote);
      expect(merged.earned, 30);
      expect(merged.sparks, 15);
      expect(merged.purchases, {'crystal'}); // cannot charge another 20
      common = grant(remote, 'tutorial');
      merged = WorldEngine.merge(local, common);
      expect(merged.earned, 50);
      expect(merged.purchases, {'crystal', 'tea'});
      expect(merged.sparks, 15);
      expect(WorldEngine.merge(merged, common).sparks, 15);
      expect(merged.rewards.length, 2);
    },
  );

  test(
    'roundtrip includes scene, settings, games, outfits and safe album export',
    () {
      var state = grant(const WorldState(), 'first_goal');
      state = WorldEngine.purchase(state, 'crystal', points: 0);
      state = WorldEngine.configure(
        state,
        background: 'pearl',
        decor: {'shelf': 'crystal'},
        now: now,
      );
      state = WorldEngine.saveOutfit(
        state,
        WorldOutfit(
          id: 'o',
          name: 'Вечер',
          date: now,
          equipped: const {WardrobeSlot.companion: 'lilac_ghost'},
        ),
      );
      final memory = WorldMemory(
        id: 'goal:private-id',
        date: now,
        title: 'Покупка по адресу X',
        description: 'Личное описание',
        goalId: 'private-id',
        amountMinor: 1234567,
        currency: 'RUB',
        asset: 'assets/finora/achievements/goal_done.webp',
      );
      state = state.copyWith(
        games: {
          'constellation:0': [0, 1],
        },
        reducedMotion: true,
        remarks: false,
        memories: {...state.memories, memory.id: memory},
      );
      final decoded = WorldState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.toJson(), state.toJson());
      expect(decoded.outfits.single.equipped, {
        WardrobeSlot.companion: 'lilac_ghost',
      });
      expect(decoded.games['constellation:0'], [0, 1]);
      final safe = jsonEncode(memory.toJson(hidePrivate: true));
      for (final secret in [
        'private-id',
        'Покупка',
        'Личное',
        '1234567',
        'RUB',
      ]) {
        expect(safe, isNot(contains(secret)), reason: secret);
      }
      expect(memory.toJson()['amountMinor'], 1234567);
    },
  );

  test(
    'corrupted reward amounts and impossible balance cannot silently create money',
    () {
      final state = grant(const WorldState(), 'tutorial');
      final raw =
          jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>;
      ((raw['rewards'] as Map)['tutorial'] as Map)['sparks'] = 999999;
      expect(() => WorldState.fromJson(raw), throwsFormatException);
      final overspent = {
        ...state.toJson(),
        'purchases': ['night'],
      };
      expect(() => WorldState.fromJson(overspent), throwsFormatException);
    },
  );

  test('corrupt game positions are discarded during restore', () {
    final state = WorldState.fromJson({
      'games': {
        'constellation:0': [999],
        'parcel:0': [999],
        'expedition:0': [0, 3],
        'unknown:0': [0],
        'constellation:1': [0, 2],
      },
    });
    expect(state.games, {
      'constellation:1': [0, 2],
    });
  });

  test(
    'collections reference real unchanged items; album pet and collection dedupe',
    () {
      final ids = {for (final i in wardrobeItems) i.id};
      for (final c in worldCollections) {
        expect(ids, containsAll(c.itemIds));
      }
      final collection = worldCollections.first;
      final wardrobe = WardrobeState(
        received: {for (final id in collection.itemIds) id: now},
        equipped: const {WardrobeSlot.companion: 'pearl_owl'},
      );
      expect(collection.completed(wardrobe), isTrue);
      final next = ledger.copyWith(wardrobe: wardrobe);
      final state = WorldEngine.sync(
        const WorldState(),
        ledger,
        next,
        now: now,
      );
      expect(
        state.memories.keys,
        containsAll(['pet:first', 'collection:stars']),
      );
      expect(
        WorldEngine.sync(state, ledger, next, now: now).memories.length,
        state.memories.length,
      );
      expect(state.rewards, isEmpty); // no earnings for opening/equipping
    },
  );

  test(
    'rare achievement memories keep original unlock date and exact artwork',
    () {
      final definition = achievementDefinitions.firstWhere(
        (d) => d.rarity == AchievementRarity.rare,
      );
      final unlockedAt = DateTime(2026, 10, 11);
      final next = ledger.copyWith(
        achievements: AchievementState(unlocked: {definition.id: unlockedAt}),
      );
      final state = WorldEngine.sync(
        const WorldState(),
        ledger,
        next,
        now: now,
      );
      final memory = state.memories['achievement:${definition.id}']!;
      expect(memory.date, unlockedAt);
      expect(memory.asset, 'assets/finora/achievements/${definition.id}.webp');
      expect(state.rewards, isEmpty);
      final again = WorldEngine.sync(
        state,
        next,
        next,
        now: now.add(const Duration(days: 1)),
      );
      expect(again.memories.length, state.memories.length);
    },
  );

  test('cosmetic economy cannot alter balances or statistics', () {
    final financial = ledger.copyWith(
      entries: [entry('expense', category: 'food')],
    );
    final balance = FinanceEngine.totalBalance(
      financial.accounts,
      financial.entries,
      'RUB',
      financial.goals,
    );
    final state = WorldEngine.purchase(
      grant(const WorldState(), 'first_payment'),
      'crystal',
      points: 0,
    );
    final evolved = financial.copyWith(world: state);
    expect(
      FinanceEngine.totalBalance(
        evolved.accounts,
        evolved.entries,
        'RUB',
        evolved.goals,
      ),
      balance,
    );
    expect(evolved.entries.single.amountMinor, 1000);
    expect(evolved.accounts.single.openingMinor, 100000);
  });
}
