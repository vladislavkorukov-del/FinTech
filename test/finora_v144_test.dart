import 'dart:io';
import 'dart:math' as math;

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/achievements.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/finora_assets.dart';
import 'package:finora/presentation/screens/achievements_screen.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

const base = FinanceData(
  accounts: [Account(id: 'a', name: 'Карта')],
  categories: [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'pay', name: 'Зарплата', kind: EntryKind.income),
  ],
  members: [Member(id: 'me', name: 'Я')],
);

FinanceEntry spend(
  String id,
  DateTime date, {
  int minor = 10000,
  EntryKind kind = EntryKind.expense,
  String? toGoalId,
}) => FinanceEntry(
  id: id,
  kind: kind,
  amountMinor: minor,
  currency: 'RUB',
  accountId: 'a',
  categoryId: kind == EntryKind.income ? 'pay' : 'food',
  date: date,
  toGoalId: toGoalId,
);

AchievementStatus status(FinanceData d, String id, DateTime now) =>
    AchievementEngine.report(
      d,
      d.achievements,
      now: now,
    ).statuses.firstWhere((s) => s.definition.id == id);

/// One change through the engine, like the controller does.
(FinanceData, List<String>) step(
  FinanceData before,
  FinanceData after,
  DateTime now, {
  bool activity = false,
}) {
  final (state, fresh) = AchievementEngine.update(
    before,
    after,
    after.achievements,
    now: now,
    activity: activity,
  );
  return (after.copyWith(achievements: state), [for (final d in fresh) d.id]);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  setUp(() => FinanceController.screenNotes = true);
  tearDown(() => FinanceController.screenNotes = false);
  final now = DateTime(2026, 11, 7, 12);

  test('больше 50 достижений, у всех свои картинки и реплики', () {
    expect(achievementDefinitions.length, greaterThanOrEqualTo(50));
    final ids = achievementDefinitions.map((d) => d.id).toSet();
    expect(ids.length, achievementDefinitions.length);
    for (final d in achievementDefinitions) {
      expect(FinoraAssets.art, contains(d.art), reason: d.id);
      expect(d.quotes.length, greaterThanOrEqualTo(3), reason: d.id);
      expect(d.target, greaterThan(0), reason: d.id);
    }
    for (final category in AchievementCategory.values) {
      expect(
        achievementDefinitions.where((d) => d.category == category),
        isNotEmpty,
        reason: category.name,
      );
    }
    for (final name in FinoraAssets.art) {
      expect(File(FinoraAssets.path(name)).existsSync(), isTrue, reason: name);
    }
  });

  test('первая операция открывает «Первый шаг»', () {
    final (d, fresh) = step(
      base,
      base.copyWith(entries: [spend('e1', now)]),
      now,
    );
    expect(fresh, contains('first_step'));
    expect(fresh, contains('first_account'));
    expect(d.achievements.unlocked['first_step'], now);
    // Again — nothing new.
    final (_, again) = step(d, d.copyWith(entries: [...d.entries]), now);
    expect(again, isNot(contains('first_step')));
  });

  test('накопительный прогресс: 5 из 10 операций', () {
    final d = base.copyWith(
      entries: [for (var i = 0; i < 5; i++) spend('e$i', now)],
    );
    final s = status(d, 'ten_records', now);
    expect((s.current, s.target, s.unlocked), (5, 10, false));
    expect(s.progress, .5);
    expect(achievementProgressText(s, 'RUB'), '5 / 10');
    final money = status(
      d
          .copyWith(
            goals: const [Goal(id: 'g', name: 'Отпуск', targetMinor: 900000)],
          )
          .copyWith(
            goals: const [
              Goal(
                id: 'g',
                name: 'Отпуск',
                targetMinor: 900000,
                savedMinor: 74500,
              ),
            ],
          ),
      'saved_1000',
      now,
    );
    expect(achievementProgressText(money, 'RUB'), contains('745'));
  });

  test('серия дней: три дня подряд, перерыв без упрёков', () {
    var d = base;
    for (var i = 0; i < 3; i++) {
      final day = DateTime(2026, 11, 1 + i, 10);
      final (next, fresh) = step(d, d, day, activity: true);
      d = next;
      if (i == 2) expect(fresh, contains('streak_3'));
    }
    var r = AchievementEngine.report(
      d,
      d.achievements,
      now: DateTime(2026, 11, 3, 20),
    );
    expect(r.metrics.currentStreak, 3);
    // Two days missed: the series starts again, the best one stays.
    r = AchievementEngine.report(d, d.achievements, now: DateTime(2026, 11, 6));
    expect(r.metrics.currentStreak, 0);
    expect(r.metrics.bestStreak, 3);
    expect(achievementStreakText(0), 'Начнём новую серию?');
    expect(d.achievements.unlocked, contains('streak_3'));
    // Records dated back do not make a series.
    final back = base.copyWith(
      entries: [
        for (var i = 0; i < 10; i++) spend('b$i', DateTime(2026, 10, 1 + i)),
      ],
    );
    expect(
      AchievementEngine.report(
        back,
        back.achievements,
        now: now,
      ).metrics.bestStreak,
      0,
    );
  });

  test('бюджет: первый бюджет и месяц в рамках плана', () {
    final budget = const Budget(id: 'b', name: 'Месяц', limitMinor: 50000);
    var (d, fresh) = step(base, base.copyWith(budgets: [budget]), now);
    expect(fresh, contains('first_budget'));
    expect(d.achievements.budgetSince, now);
    // The budget existed from October; October spent 300 ₽ of 500 ₽.
    d = d.copyWith(
      achievements: d.achievements.copyWith(budgetSince: DateTime(2026, 9, 30)),
      entries: [
        spend('o1', DateTime(2026, 10, 2), minor: 20000),
        spend('o2', DateTime(2026, 10, 20), minor: 10000),
      ],
    );
    final (after, got) = step(d, d.copyWith(entries: [...d.entries]), now);
    expect(got, containsAll(['budget_month', 'reserve_90', 'reserve_80']));
    expect(after.achievements.unlocked, contains('budget_month'));
    // Over the limit — no «Держу план».
    final over = d.copyWith(
      entries: [spend('o1', DateTime(2026, 10, 2), minor: 60000)],
    );
    expect(status(over, 'budget_month', now).current, 0);
  });

  test('цель достигнута; удаление цели не забирает награду', () {
    var (d, fresh) = step(
      base,
      base.copyWith(
        goals: const [
          Goal(
            id: 'g',
            name: 'Велосипед',
            targetMinor: 100000,
            savedMinor: 100000,
          ),
        ],
      ),
      now,
    );
    expect(
      fresh,
      containsAll(['goal_set', 'goal_half', 'goal_90', 'goal_done']),
    );
    expect(d.achievements.completedGoals, {'g'});
    final (gone, _) = step(d, d.copyWith(goals: const []), now);
    expect(gone.achievements.unlocked, contains('goal_done'));
    expect(status(gone, 'goal_done', now).unlocked, isTrue);
    expect(status(gone, 'goals_3', now).current, 1);
  });

  test('удаление операций не отнимает полученное', () {
    final (d, _) = step(base, base.copyWith(entries: [spend('e1', now)]), now);
    final (empty, fresh) = step(d, d.copyWith(entries: const []), now);
    expect(fresh, isEmpty);
    expect(empty.achievements.unlocked, contains('first_step'));
    expect(status(empty, 'first_step', now).unlocked, isTrue);
  });

  test('секретные: скрыты до получения, «Ночная бухгалтерия» в 3 ночи', () {
    final night = DateTime(2026, 11, 7, 3, 10);
    final (d, fresh) = step(
      base,
      base.copyWith(entries: [spend('n1', night)]),
      night,
    );
    expect(fresh, contains('night'));
    final def = achievementDefinitions.firstWhere((x) => x.id == 'night');
    expect(def.secret, isTrue);
    // In the daytime nothing secret happens.
    final (_, day) = step(
      base,
      base.copyWith(entries: [spend('n1', now)]),
      now,
    );
    expect(day, isNot(contains('night')));
    expect(d.achievements.flags, contains('night'));
    // A record dated 40 days back.
    final (_, old) = step(
      base,
      base.copyWith(
        entries: [spend('x', now.subtract(const Duration(days: 40)))],
      ),
      now,
    );
    expect(old, contains('archaeologist'));
  });

  test('несколько достижений за один раз', () {
    final (_, fresh) = step(
      base,
      base.copyWith(
        accounts: const [
          Account(id: 'a', name: 'Карта'),
          Account(id: 'c', name: 'Наличные', type: 'cash'),
          Account(id: 's', name: 'Копилка', type: 'savings'),
        ],
        entries: [
          spend('e1', now),
          FinanceEntry(
            id: 't1',
            kind: EntryKind.transfer,
            amountMinor: 500,
            currency: 'RUB',
            accountId: 'a',
            toAccountId: 'c',
            date: now,
          ),
        ],
      ),
      now,
    );
    expect(
      fresh,
      containsAll([
        'first_step',
        'first_account',
        'full_picture',
        'cash',
        'first_transfer',
      ]),
    );
  });

  test('пример (демо) не даёт достижений', () {
    final demo = createDemoData(now);
    final (_, fresh) = step(const FinanceData(), demo, now);
    expect(fresh, isNot(contains('first_step')));
    expect(fresh, isNot(contains('fifty_records')));
  });

  test('реакции Финоры: картинки, рисунки и запасные варианты', () {
    expect(FinoraAssets.artFor(FinoraReactionType.celebrating), 'goal_done');
    expect(FinoraAssets.artFor(FinoraReactionType.proud), 'budget_master');
    expect(FinoraAssets.artFor(FinoraReactionType.success), 'limit_kept');
    // celebrating → happy, proud → happy, focused → neutral, supportive → calm.
    const only = {
      FinoraReactionType.happy: 'balance_plus',
      FinoraReactionType.neutral: 'first_step',
      FinoraReactionType.calm: 'finance_zen',
    };
    expect(
      FinoraAssets.artFor(FinoraReactionType.celebrating, available: only),
      'balance_plus',
    );
    expect(
      FinoraAssets.artFor(FinoraReactionType.proud, available: only),
      'balance_plus',
    );
    expect(
      FinoraAssets.artFor(FinoraReactionType.focused, available: only),
      'first_step',
    );
    expect(
      FinoraAssets.artFor(FinoraReactionType.supportive, available: only),
      'finance_zen',
    );
    expect(
      FinoraAssets.resolve(
        FinoraReactionType.celebrating,
        available: {FinoraReactionType.happy},
      ),
      FinoraReactionType.happy,
    );
    expect(
      FinoraAssets.resolve(FinoraReactionType.warning),
      FinoraReactionType.neutral,
    );
    // Nothing at all — the drawn Finora.
    expect(
      FinoraAssets.artFor(FinoraReactionType.sleepy, available: const {}),
      isNull,
    );
    for (final t in FinoraReactionType.values) {
      expect(FinoraAssets.mood(t), isA<FinoraMood>());
    }
    expect(AchievementEngine.moodFor(0), FinoraReactionType.supportive);
    expect(AchievementEngine.moodFor(1), FinoraReactionType.celebrating);
  });

  test('реплика выбирается случайно из своего набора', () {
    final d = achievementDefinitions.first;
    final picked = {
      for (var seed = 0; seed < 40; seed++)
        AchievementEngine.quote(d, math.Random(seed)),
    };
    expect(picked, d.quotes.toSet());
  });

  test('уровни по очкам, без валюты', () {
    expect(AchievementRarity.common.points, 10);
    expect(AchievementRarity.legendary.points, 150);
    final r = AchievementEngine.report(
      base,
      AchievementState(
        unlocked: {for (final d in achievementDefinitions.take(8)) d.id: now},
      ),
      now: now,
    );
    expect(r.points, greaterThan(0));
    expect(r.level.title, isNot('Финансовый гуру'));
    expect(achievementLevels.first.title, 'Новичок');
    expect(achievementLevels.last.title, 'Финансовый гуру');
  });

  test('хранение: база, копия JSON и импорт не теряют полученное', () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('finora-v144-');
    final repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/db',
    );
    await repo.save(base);
    final c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
    final got = <String>[];
    final sub = c.achievementUnlocks.listen(
      (list) => got.addAll(list.map((d) => d.id)),
    );
    await c.saveEntry(spend('e1', now));
    await Future<void>.delayed(Duration.zero);
    expect(got, contains('first_step'));
    expect((await repo.load()).achievements.unlocked, contains('first_step'));
    // Deleting and importing an old copy keeps it.
    await c.deleteEntry('e1');
    expect(c.data.achievements.unlocked, contains('first_step'));
    final json = FinanceData.fromJson(base.toJson());
    expect(json.achievements.unlocked, isEmpty);
    await c.resetAll();
    expect(c.data.achievements.unlocked, contains('first_step'));
    // Analytics periods and the budgets count as activity.
    await c.noteAnalytics('Месяц:2026-11-01');
    await c.noteAnalytics('Месяц:2026-11-01');
    expect(c.data.achievements.analyticsPeriods.length, 1);
    expect(c.data.achievements.unlocked, contains('analytics_open'));
    await c.markAchievementsSeen();
    expect(c.data.achievements.seenAt, now);
    await sub.cancel();
    c.dispose();
    await repo.close();
    await temp.delete(recursive: true);
  });

  test('платёж оплачен вовремя — «Всё вовремя»', () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('finora-v144-pay-');
    final repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/db',
    );
    await repo.save(
      base.copyWith(
        recurring: [
          RecurringRule(
            id: 'r',
            name: 'Интернет',
            kind: EntryKind.expense,
            amountMinor: 50000,
            currency: 'RUB',
            accountId: 'a',
            categoryId: 'food',
            frequency: 'monthly',
            nextDate: DateTime(2026, 11, 10),
          ),
        ],
      ),
    );
    final c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
    await c.confirmPayment('r');
    expect(c.data.achievements.payments.single.onTime, isTrue);
    expect(c.data.achievements.unlocked, contains('on_time'));
    c.dispose();
    await repo.close();
    await temp.delete(recursive: true);
  });

  test('«Что нового» 1.44 — про достижения', () {
    expect(WhatsNew.items.first.$2, 'Достижения');
  });

  testWidgets('экран «Достижения», карточка на главной и окно получения', (
    tester,
  ) async {
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repo;
    late FinanceController c;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('finora-v144-ui-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      await repo.save(base);
      c = FinanceController(repo, _Quiet(), await repo.load())
        ..achievementClock = () => now;
      await c.saveEntry(spend('e1', now));
    });
    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AchievementsCard()),
          ),
        ),
      ),
    );
    await settle();
    expect(
      find.byKey(const ValueKey('dashboard-achievements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('achievements-new-badge')),
      findsOneWidget,
    );
    expect(find.textContaining('Получено'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('dashboard-achievements')));
    await settle();
    expect(find.byKey(const ValueKey('achievements-count')), findsOneWidget);
    final count = tester.widget<Text>(
      find.byKey(const ValueKey('achievements-count')),
    );
    expect(count.data, startsWith('Получено '));
    // Opening the screen clears «Новое».
    expect(c.data.achievements.seenAt, now);
    // Secret achievements are hidden.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('achievements-filters')),
      find.byKey(const ValueKey('achievements-list')),
      const Offset(0, -80),
    );
    await settle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('achievements-filter-secret')),
      150,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('achievements-filters')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('achievements-filter-secret')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('achievements-filter-secret')));
    await settle();
    expect(find.text('???'), findsWidgets);
    expect(find.text('Секретное достижение'), findsWidgets);
    expect(find.text('Ночная бухгалтерия'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('achievements-filter-got')),
      -150,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('achievements-filters')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('achievements-filter-got')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('achievements-filter-got')));
    await settle();
    expect(
      find.byKey(const ValueKey('achievement-first_step')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('achievement-first_step')));
    await settle();
    expect(
      find.byKey(const ValueKey('achievement-sheet-first_step')),
      findsOneWidget,
    );

    // The popup: several at once become one message.
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          key: const ValueKey('popup-app'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => AchievementPopup.show(
                    context,
                    achievementDefinitions.take(3).toList(),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    AchievementPopup.enabled = true;
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Получено 3 новых достижений'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('achievement-popup-open')));
    await settle();
    expect(find.byKey(const ValueKey('achievements-count')), findsOneWidget);
    AchievementPopup.enabled = false;
    AchievementPopup.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
    await tester.runAsync(() async {
      c.dispose();
      await repo.close();
      await temp.delete(recursive: true);
    });
  });
}
