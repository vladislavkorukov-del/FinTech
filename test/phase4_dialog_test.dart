import 'dart:convert';

import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/actions/ai_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 18, 12, 30);
  const cash = Account(id: 'cash', name: 'Наличные');
  const card = Account(id: 'card', name: 'Сбербанк', lastFour: '1234');
  const archived = Account(id: 'old', name: 'Архивный', archived: true);
  const food = Category(id: 'food', name: 'Продукты', kind: EntryKind.expense);
  const cafe = Category(id: 'cafe', name: 'Кафе', kind: EntryKind.expense);
  const data = FinanceData(
    accounts: [cash, card, archived],
    categories: [food, cafe],
  );
  String json(String action, Map<String, Object?> args) =>
      jsonEncode({'action': action, 'args': args});
  AiActionResolution start(
    AiActionSession s, {
    String text = 'Добавь расход 850 на продукты',
    String id = 'first',
  }) => s.resolveDeterministic(text, data: data, now: now, requestId: id)!;
  AiActionResolution follow(
    AiActionSession s,
    String text, {
    int seconds = 10,
    String? id,
  }) {
    s.beginUserTurn(text, now: now.add(Duration(seconds: seconds)));
    return s.resolveDeterministic(
      text,
      data: data,
      now: now.add(Duration(seconds: seconds)),
      requestId: id ?? 'turn-$seconds',
    )!;
  }

  test(
    'multiple turns amend one exact draft, never create ledger operations',
    () {
      final s = AiActionSession();
      expect(start(s).needsClarification, true);
      final id = s.unfinishedDraftId;
      expect(follow(s, 'Это было вчера').needsClarification, true);
      final selected = follow(s, 'Спиши с наличных', seconds: 20).pending!;
      expect(selected.draftId, id);
      expect(selected.entry!.amountMinor, 85000);
      expect(selected.entry!.accountId, 'cash');
      expect(selected.entry!.date.day, 17);
      final corrected = follow(s, 'Не 850, а 900,25', seconds: 30).pending!;
      expect(corrected.draftId, id);
      expect(corrected.entry!.amountMinor, 90025);
      final category = follow(s, 'Категория кафе', seconds: 40).pending!;
      expect(category.entry!.categoryId, 'cafe');
      expect(category.entry!.amountMinor, 90025);
      expect(
        s.isCurrent(selected, data, now: now.add(const Duration(seconds: 40))),
        false,
      );
      expect(data.entries, isEmpty);
    },
  );

  test('latest amount wins; model cannot resurrect an earlier correction', () {
    final s = AiActionSession();
    start(s, text: 'Добавь 850 на продукты с наличных');
    follow(s, 'Не 850, а 900,25');
    final stale = s.resolve(
      json('create_entry', {'amountMinor': 85000}),
      userText: 'С наличных',
      data: data,
      now: now.add(const Duration(seconds: 20)),
      requestId: 'stale',
    );
    expect(stale.pending, isNull);
    expect(data.entries, isEmpty);
  });

  test('last four card digits select account and never replace money', () {
    final s = AiActionSession();
    start(s);
    final result = follow(s, 'Спиши с карты 1234').pending!;
    expect(result.entry!.accountId, 'card');
    expect(result.entry!.amountMinor, 85000);
    final same = follow(s, '1234', seconds: 20).pending!;
    expect(same.entry!.amountMinor, 85000);
  });

  test('unknown card digits ask for account instead of changing amount', () {
    final s = AiActionSession();
    start(s, text: 'Добавь 850 на продукты с наличных');
    final result = follow(s, 'С карты 5678');
    expect(result.pending, isNull);
    expect(result.needsClarification, true);
    expect((s.unfinishedAction!['args'] as Map)['amountMinor'], 85000);
    final guessed = s.resolve(
      json('create_entry', {'accountId': 'cash'}),
      userText: 'С карты 5678',
      data: data,
      now: now.add(const Duration(seconds: 20)),
      requestId: 'guessed',
    );
    expect(guessed.pending, isNull);
  });

  test('known card digits equal to money do not erase an actual amount', () {
    final s = AiActionSession();
    final result = start(
      s,
      text: 'Добавь расход 1234 на продукты с карты 1234',
    );
    expect(result.pending!.entry!.amountMinor, 123400);
  });

  test('positive correction before an explicit rejected amount wins', () {
    final s = AiActionSession();
    start(s, text: 'Добавь 850 на продукты с наличных');
    expect(follow(s, '900,25, а не 850').pending!.entry!.amountMinor, 90025);
  });

  test('explicit absolute date is not parsed as an amount correction', () {
    final s = AiActionSession();
    start(s, text: 'Добавь 850 на продукты с наличных');
    final result = follow(s, 'Это было 2026-11-15').pending!;
    expect(result.entry!.amountMinor, 85000);
    expect(result.entry!.date.day, 15);
  });

  test(
    'confirmed primary alias is usable, missing or archived aliases are not guessed',
    () {
      final s = AiActionSession()..primaryAccountId = 'card';
      start(s);
      expect(follow(s, 'С основного счёта').pending!.entry!.accountId, 'card');
      for (final id in [null, 'old', 'invented']) {
        final missing = AiActionSession()..primaryAccountId = id;
        start(missing);
        expect(
          missing
              .resolveDeterministic(
                'С основного счёта',
                data: data,
                now: now.add(const Duration(seconds: 10)),
              )
              ?.pending,
          isNull,
        );
      }
    },
  );

  test('cancellation removes draft and authority without creating data', () {
    final s = AiActionSession();
    start(s, text: 'Добавь 850 на продукты с наличных');
    final result = follow(s, 'Нет, отмени');
    expect(result.pending, isNull);
    expect(s.unfinishedAction, isNull);
    expect(s.unfinishedDraftId, isNull);
    expect(data.entries, isEmpty);
  });

  test('topic switch expires scope immediately', () {
    final s = AiActionSession();
    start(s);
    s.beginUserTurn(
      'Почему трачу больше?',
      now: now.add(const Duration(seconds: 10)),
    );
    expect(s.unfinishedAction, isNull);
    expect(
      s
          .resolveDeterministic(
            'С наличных',
            data: data,
            now: now.add(const Duration(seconds: 20)),
          )
          ?.pending,
      isNull,
    );
  });

  test('five minute TTL checked before handling a follow-up', () {
    final s = AiActionSession();
    start(s);
    final result = s.resolveDeterministic(
      'С наличных',
      data: data,
      now: now.add(const Duration(minutes: 5)),
    );
    expect(result?.pending, isNull);
    expect(s.unfinishedAction, isNull);
  });

  test('relative date stays anchored over local midnight', () {
    final day = DateTime(2026, 11, 18, 23, 59);
    final s = AiActionSession();
    s.resolveDeterministic(
      'Добавь расход 850 на продукты сегодня',
      data: data,
      now: day,
      requestId: 'night',
    );
    final result = s.resolveDeterministic(
      'С наличных',
      data: data,
      now: DateTime(2026, 11, 19, 0, 1),
      requestId: 'cash',
    );
    expect(result!.pending!.entry!.date.day, 18);
  });

  test('restart restores a typed draft but never restores approval', () {
    final original = AiActionSession();
    start(original);
    final id = original.unfinishedDraftId;
    final exported =
        jsonDecode(
              jsonEncode(
                original.exportSession(
                  now: now.add(const Duration(seconds: 2)),
                ),
              ),
            )
            as Map<String, dynamic>;
    final restored = AiActionSession();
    expect(
      restored.restoreSession(
        exported,
        data,
        now: now.add(const Duration(seconds: 5)),
      ),
      true,
    );
    expect(restored.pending, isNull);
    expect(restored.unfinishedDraftId, id);
    final completed = restored.resolveDeterministic(
      'С наличных',
      data: data,
      now: now.add(const Duration(seconds: 10)),
      requestId: 'after-restart',
    );
    expect(completed!.pending!.draftId, id);
    expect(completed.pending!.entry!.amountMinor, 85000);
  });

  test(
    'complete restored drafts still require a new user turn and confirmation',
    () {
      final s = AiActionSession();
      final old = start(s, text: 'Добавь 850 на продукты с наличных').pending!;
      final restored = AiActionSession();
      expect(
        restored.restoreSession(s.exportSession(now: now), data, now: now),
        true,
      );
      expect(restored.pending, isNull);
      expect(restored.consume(old, data, now: now), false);
    },
  );

  test('restoration rejects stale, invented, archived and unknown fields', () {
    final s = AiActionSession();
    start(s);
    final saved = s.exportSession(now: now);
    Map<String, dynamic> copy() =>
        jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
    final expired = AiActionSession();
    expect(
      expired.restoreSession(
        copy(),
        data,
        now: now.add(const Duration(minutes: 5)),
      ),
      false,
    );
    for (final id in ['invented', 'old']) {
      final changed = copy();
      ((changed['draft'] as Map)['args'] as Map)['accountId'] = id;
      final restored = AiActionSession();
      expect(restored.restoreSession(changed, data, now: now), false);
      expect(restored.pending, isNull);
    }
    final injected = copy();
    (injected['draft'] as Map)['confirmed'] = true;
    expect(AiActionSession().restoreSession(injected, data, now: now), false);
    final badAmount = copy();
    ((badAmount['draft'] as Map)['args'] as Map)['amountMinor'] = 99900;
    expect(AiActionSession().restoreSession(badAmount, data, now: now), false);
  });

  test(
    'consumed request IDs persist and duplicate delivery cannot authorize twice',
    () {
      final s = AiActionSession();
      final action = start(
        s,
        text: 'Добавь 850 на продукты с наличных',
      ).pending!;
      expect(s.consume(action, data, now: now), true);
      final restored = AiActionSession();
      expect(
        restored.restoreSession(s.exportSession(now: now), data, now: now),
        true,
      );
      expect(
        start(restored, text: 'Добавь 850 на продукты с наличных').pending,
        isNull,
      );
      expect(restored.unfinishedAction, isNull);
    },
  );

  test(
    'stable draft identity refuses restoration after its operation already exists',
    () {
      final s = AiActionSession();
      final action = start(
        s,
        text: 'Добавь 850 на продукты с наличных',
      ).pending!;
      final ledger = data.copyWith(
        entries: [action.entry!.copyWith(id: 'assistant:${action.draftId}')],
      );
      expect(
        AiActionSession().restoreSession(
          s.exportSession(now: now),
          ledger,
          now: now,
        ),
        false,
      );
    },
  );

  test('new explicit creation gets a new logical identity', () {
    final s = AiActionSession();
    start(s);
    final first = s.unfinishedDraftId;
    start(s, id: 'next');
    expect(s.unfinishedDraftId, isNot(first));
  });

  test(
    'registry provides risk and provenance for every whitelisted capability',
    () {
      expect(AppActionRegistry.descriptors.length, 8);
      final s = AiActionSession();
      final action = start(
        s,
        text: 'Добавь 850 на продукты с наличных',
      ).pending!;
      expect(action.risk, AiActionRisk.financialDraft);
      expect(action.source, AiActionSource.deterministic);
      expect(
        AppActionRegistry.forKind(AiActionKind.reviewWeek).risk,
        AiActionRisk.readOnly,
      );
    },
  );

  test('debt planning route opens a draft and never invents parameters', () {
    final s = AiActionSession();
    final result = s.resolveDeterministic(
      'Посчитай все мои долги, распредели и запланируй платежи на каждую неделю',
      data: data,
      now: now,
    );
    expect(result!.pending!.kind, AiActionKind.planDebts);
    expect(result.pending!.command, isNull);
    expect(result.pending!.arguments, isEmpty);
    final explicit = s.resolve(
      json('plan_debts', {
        'accountId': 'cash',
        'budgetMinor': 500000,
        'reserveMinor': 100000,
        'horizonDays': 30,
      }),
      userText:
          'Составь план долгов с наличных: бюджет 5000, резерв 1000, на 30 дней',
      data: data,
      now: now,
      requestId: 'plan',
    );
    expect(explicit.pending!.kind, AiActionKind.planDebts);
    expect(data.entries, isEmpty);
    expect(
      s
          .resolve(
            json('plan_debts', {'budgetMinor': 990000}),
            userText: 'Запланируй погашение долгов',
            data: data,
            now: now,
            requestId: 'guess',
          )
          .pending,
      isNull,
    );
  });

  test('planning rejects negative intent and guessed object or horizon', () {
    for (final text in [
      'Не планируй долги',
      'Привет',
      'Что написано в магазине?',
    ]) {
      expect(
        AiActionSession()
            .resolve(
              json('plan_debts', {}),
              userText: text,
              data: data,
              now: now,
            )
            .pending,
        isNull,
      );
    }
    expect(
      AiActionSession()
          .resolve(
            json('plan_debts', {'accountId': 'invented'}),
            userText: 'Составь план долгов',
            data: data,
            now: now,
          )
          .pending,
      isNull,
    );
    expect(
      AiActionSession()
          .resolve(
            json('plan_debts', {'horizonDays': 91}),
            userText: 'Составь план долгов на 91 день',
            data: data,
            now: now,
          )
          .pending,
      isNull,
    );
    expect(
      AiActionSession()
          .resolve(
            json('plan_debts', {'horizonDays': 30}),
            userText: 'Составь план долгов',
            data: data,
            now: now,
          )
          .pending,
      isNull,
    );
  });

  test(
    'week and memory routes use current UI capabilities, no arbitrary writes',
    () {
      final s = AiActionSession();
      expect(
        s
            .resolveDeterministic(
              'Покажи недельный разбор',
              data: data,
              now: now,
            )!
            .pending!
            .kind,
        AiActionKind.reviewWeek,
      );
      expect(
        s
            .resolveDeterministic(
              'Открой мои предпочтения и сценарии',
              data: data,
              now: now,
            )!
            .pending!
            .kind,
        AiActionKind.assistantMemory,
      );
      expect(
        s
            .resolve(
              json('assistant_memory', {'primaryAccountId': 'card'}),
              userText: 'Открой память',
              data: data,
              now: now,
            )
            .pending,
        isNull,
      );
      expect(
        s
            .resolve(
              json('review_week', {}),
              userText: 'Привет',
              data: data,
              now: now,
            )
            .pending,
        isNull,
      );
    },
  );

  test('quoted purchase instructions are data, not write authority', () {
    final s = AiActionSession();
    expect(
      s
          .resolve(
            json('create_entry', {
              'kind': 'expense',
              'amountMinor': 85000,
              'accountId': 'cash',
              'categoryId': 'food',
            }),
            userText: 'Комментарий: «добавь расход 850 на продукты с наличных»',
            data: data,
            now: now,
          )
          .pending,
      isNull,
    );
  });
}
