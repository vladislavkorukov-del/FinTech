import 'dart:convert';
import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/achievements.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final now = DateTime(2026, 11, 8, 12);
  WardrobeState grant(List<String> ids) =>
      WardrobeState(received: {for (final id in ids) id: now});

  test(
    'all28 pack IDs and image geometry match source JSON alongside four legacy items',
    () {
      final companions =
          jsonDecode(
                File(
                  'assets/finora/wardrobe_pack/companions.json',
                ).readAsStringSync(),
              )
              as List;
      final capes =
          jsonDecode(
                File(
                  'assets/finora/wardrobe_pack/capes.json',
                ).readAsStringSync(),
              )
              as List;
      expect(companions, hasLength(13));
      expect(capes, hasLength(15));
      expect(wardrobeItems, hasLength(32));
      expect(wardrobeItems.map((i) => i.id).toSet(), hasLength(32));
      for (final raw in [...companions, ...capes]) {
        final data = raw as Map;
        final item = Wardrobe.item(data['id'] as String)!;
        expect(item.id, data['id']);
        expect(item.name, data['name_ru']);
        expect(item.asset, data['file']);
        expect(
          item.ratio,
          closeTo((data['width'] as int) / (data['height'] as int), 1e-10),
        );
        expect(File(item.asset).existsSync(), isTrue, reason: item.id);
        if (item.category == WardrobeCategory.companion) {
          expect(item.slot, WardrobeSlot.companion);
          // Full canvases include transparent padding; visible40% is verified by renderer tests.
          expect(item.fit.width, inInclusiveRange(.35, .7));
          expect(item.fit.x.isNegative, data['side_default'] == 'left');
          expect(item.layer, WardrobeLayer.frontAccessory);
        } else {
          expect(item.slot, WardrobeSlot.cape);
          expect(item.layer, WardrobeLayer.behindCharacter);
          expect(item.ratio, 1.5);
        }
      }
    },
  );

  test(
    'legacy rewards and actual historical cape achievement IDs remain valid',
    () {
      const rewards = {
        'first_coin': 'first_topup',
        'dream_trophy': 'goal_done',
        'mini_piggy_bank': 'saved_10000',
        'order_robot': 'order',
        'star_wanderer': 'ten_records',
        'pirate_tides': 'first_account',
        'emerald_wood': 'first_topup',
        'sand_prophecy': 'full_picture',
        'scarlet_flight': 'economy',
        'emerald_city': 'no_overdue',
        'starlit_academy': 'analyst_10',
        'digital_grid': 'order',
        'neon_noir': 'streak_30',
        'midnight_vigil': 'cushion_3',
        'frost_queen': 'budget_12',
        'firebird_rebel': 'ideal_year',
        'royal_panther': 'veteran',
        'mystic_portal': 'perfectionist',
      };
      final achievementIds = achievementDefinitions.map((a) => a.id).toSet();
      for (final e in rewards.entries) {
        expect(Wardrobe.item(e.key)!.achievementId, e.value);
        expect(achievementIds, contains(e.value));
      }
      expect(Wardrobe.item('new_year')!.source, isA<EventReward>());
      const companionRewards = {
        'lilac_ghost': 'first_step',
        'moon_cat': 'night',
        'pearl_owl': 'analytics_open',
        'investment_sprout': 'first_topup',
        'midnight_raven': 'categorized_100',
        'moon_rabbit': 'streak_7',
        'pink_mushroom': 'first_budget',
        'pearl_crab': 'reserve_90',
        'red_panda': 'economy',
        'amethyst_jellyfish': 'balance_6',
        'forest_frog': 'cash',
        'aviator_octopus': 'full_picture',
        'pearl_koi': 'plus_3',
      };
      for (final e in companionRewards.entries) {
        final item = Wardrobe.item(e.key)!;
        final achievement = achievementDefinitions.singleWhere(
          (a) => a.id == e.value,
        );
        expect(item.achievementId, e.value);
        expect(item.rarity, achievement.rarity);
        expect(item.secret, achievement.secret);
      }
    },
  );

  test(
    'existing reward sync grants once without invented achievement conditions',
    () {
      final achievements = AchievementState(
        unlocked: {
          'first_topup': now,
          'ten_records': now,
          'goal_done': now,
          'order': now,
        },
      );
      final state = Wardrobe.sync(
        const WardrobeState(),
        achievements,
        now: now,
      );
      expect(state.received.keys.toSet(), {
        'first_coin',
        'dream_trophy',
        'order_robot',
        'emerald_wood',
        'star_wanderer',
        'digital_grid',
        'investment_sprout',
      });
      expect(
        identical(
          Wardrobe.sync(
            state,
            achievements,
            now: now.add(const Duration(days: 1)),
          ),
          state,
        ),
        isTrue,
      );
      expect(Wardrobe.rewardsOf('order').map((i) => i.id).toSet(), {
        'order_robot',
        'digital_grid',
      });
    },
  );

  test(
    'new companion inherits existing achievement date and is not free by default',
    () {
      final item = Wardrobe.item('lilac_ghost')!;
      expect(
        Wardrobe.open(item, const AchievementState(), const WardrobeState()),
        isFalse,
      );
      expect(
        () => Wardrobe.wear(const WardrobeState(), item.id),
        throwsFormatException,
      );
      final achieved = now.subtract(const Duration(days: 3));
      final state = Wardrobe.sync(
        const WardrobeState(),
        AchievementState(unlocked: {'first_step': achieved}),
        now: now,
      );
      expect(state.received['lilac_ghost'], achieved);
      expect(Wardrobe.open(item, const AchievementState(), state), isTrue);
      expect(
        Wardrobe.wear(state, item.id).equipped[WardrobeSlot.companion],
        item.id,
      );
    },
  );

  test(
    'cape and companion equip independently, replace only their own slot and sort behind first',
    () {
      var state = grant([
        'lilac_ghost',
        'moon_cat',
        'star_wanderer',
        'neon_noir',
      ]);
      state = Wardrobe.wear(state, 'star_wanderer');
      state = Wardrobe.wear(state, 'lilac_ghost');
      expect(Wardrobe.worn(state).map((i) => i.id), [
        'star_wanderer',
        'lilac_ghost',
      ]);
      state = Wardrobe.wear(state, 'moon_cat');
      expect(state.equipped, {
        WardrobeSlot.cape: 'star_wanderer',
        WardrobeSlot.companion: 'moon_cat',
      });
      state = Wardrobe.wear(state, 'neon_noir');
      expect(state.equipped, {
        WardrobeSlot.cape: 'neon_noir',
        WardrobeSlot.companion: 'moon_cat',
      });
      state = Wardrobe.takeOff(state, WardrobeSlot.cape);
      expect(state.equipped, {WardrobeSlot.companion: 'moon_cat'});
      state = Wardrobe.wear(state, 'neon_noir');
      state = Wardrobe.takeOff(state, WardrobeSlot.companion);
      expect(state.equipped, {WardrobeSlot.cape: 'neon_noir'});
      expect(() => Wardrobe.wear(state, 'pearl_koi'), throwsFormatException);
    },
  );

  test(
    'historical cape aliases migrate to stable JSON IDs and keep earliest unlock date',
    () {
      final early = now.subtract(const Duration(days: 20));
      final state = WardrobeState.fromJson({
        'received': {
          'cape_star_wanderer': early.toIso8601String(),
          'star_wanderer': now.toIso8601String(),
          'first_coin': now.toIso8601String(),
        },
        'equipped': {'cape': 'cape_star_wanderer', 'companion': 'first_coin'},
      });
      expect(state.received, {'star_wanderer': early, 'first_coin': now});
      expect(state.equipped, {
        WardrobeSlot.cape: 'star_wanderer',
        WardrobeSlot.companion: 'first_coin',
      });
      final restored = WardrobeState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), state.toJson());
      expect(Wardrobe.item('cape_star_wanderer')!.id, 'star_wanderer');
      expect(
        Wardrobe.wear(state, 'cape_star_wanderer').equipped[WardrobeSlot.cape],
        'star_wanderer',
      );
    },
  );

  test(
    'sync canonicalizes raw old state without resetting another equipped slot',
    () {
      final state = WardrobeState(
        received: {'cape_star_wanderer': now, 'moon_cat': now},
        equipped: {
          WardrobeSlot.cape: 'cape_star_wanderer',
          WardrobeSlot.companion: 'moon_cat',
        },
      );
      final synced = Wardrobe.sync(state, const AchievementState(), now: now);
      expect(synced.received.keys.toSet(), {'star_wanderer', 'moon_cat'});
      expect(synced.equipped, {
        WardrobeSlot.cape: 'star_wanderer',
        WardrobeSlot.companion: 'moon_cat',
      });
      expect(
        identical(
          Wardrobe.sync(synced, const AchievementState(), now: now),
          synced,
        ),
        isTrue,
      );
    },
  );

  test('restored New Year source uses only its historical event window', () {
    final source = Wardrobe.item('new_year')!.source as EventReward;
    for (final date in [DateTime(2026, 12, 15), DateTime(2027, 1, 15)]) {
      expect(source.activeAt(date), isTrue);
      expect(
        Wardrobe.sync(
          const WardrobeState(),
          const AchievementState(),
          now: date,
        ).received,
        contains('new_year'),
      );
    }
    for (final date in [DateTime(2026, 12, 14), DateTime(2027, 1, 16)]) {
      expect(source.activeAt(date), isFalse);
      expect(
        Wardrobe.sync(
          const WardrobeState(),
          const AchievementState(),
          now: date,
        ).received,
        isNot(contains('new_year')),
      );
    }
  });

  test(
    'SQLite restart and portable JSON preserve both slots and financial data',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp(
        'finora-wardrobe-pack-',
      );
      var repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/ledger',
      );
      const fixture = FinanceData(
        accounts: [Account(id: 'card', name: 'Карта', openingMinor: 125050)],
        categories: [
          Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
        ],
        members: [Member(id: 'me', name: 'Я')],
        demo: false,
      );
      final dressed = Wardrobe.wear(
        Wardrobe.wear(grant(['pearl_koi', 'royal_panther']), 'pearl_koi'),
        'royal_panther',
      );
      await repo.save(fixture.copyWith(wardrobe: dressed));
      final backup = await repo.exportJson();
      await repo.close();
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/ledger',
      );
      expect((await repo.load()).wardrobe.toJson(), dressed.toJson());
      await repo.importJson(backup);
      final restored = await repo.load();
      expect(restored.wardrobe.toJson(), dressed.toJson());
      expect(
        restored.accounts.map((a) => a.toJson()),
        fixture.accounts.map((a) => a.toJson()),
      );
      expect(
        restored.members.map((m) => m.toJson()),
        fixture.members.map((m) => m.toJson()),
      );
      expect(restored.entries, isEmpty);
      await repo.close();
      await dir.delete(recursive: true);
    },
  );
}
