import '../finance_engine.dart';
import '../models.dart';
import '../payee_summary.dart';
import 'goal_planner.dart';
import 'income_planner.dart';

/// Something that happened, for the rules.
class RuleEvent {
  const RuleEvent(
    this.type,
    this.key, {
    this.entry,
    this.budget,
    this.goal,
    this.rule,
    this.percent,
  });

  /// income · refund · budgetThreshold · incomeDateChanged · goalFunded
  final String type;

  /// Unique per real event: the same key is processed once, ever.
  final String key;
  final FinanceEntry? entry;
  final Budget? budget;
  final Goal? goal;
  final RecurringRule? rule;

  /// Budget use in percent (budgetThreshold).
  final int? percent;
}

/// What one rule did (or would do) with one event.
class RuleOutcome {
  const RuleOutcome(
    this.rule,
    this.event,
    this.fired,
    this.explanation, {
    this.notices = const [],
    this.adjustments = const [],
  });
  final PersonalRule rule;
  final RuleEvent event;
  final bool fired;
  final String explanation;
  final List<RuleNotice> notices;
  final List<BudgetAdjustment> adjustments;
}

/// «Личные финансовые правила» (Phase 8): deterministic «если → то». Each
/// event has a key; a rule processes a key once (the run is stored, so a
/// restart repeats nothing). Rule outputs are notices, suggestions and — only
/// where the person turned it on — an internal budget change; they never
/// create operations, so a rule cannot trigger another (no cycles). Rules
/// run by priority; two rules changing the same budget for one event — only
/// the first does. A dry run computes the same outcome without saving.
abstract final class RulesEngine {
  static const triggers = {
    'income': 'Получен доход',
    'refund': 'Возврат покупки',
    'budgetThreshold': 'Бюджет близок к лимиту',
    'incomeDateChanged': 'Изменилась дата ожидаемого дохода',
    'goalFunded': 'Цель накоплена',
  };
  static const conditionFields = {
    'tag': 'Метка содержит',
    'payee': 'Получатель/плательщик содержит',
    'category': 'Категория',
    'amountMin': 'Сумма не меньше',
    'account': 'Счёт',
    'budget': 'Бюджет',
    'percentMin': 'Использовано бюджета не меньше, %',
  };
  static const actionTypes = {
    'notify': 'Уведомить',
    'suggestGoals': 'Предложить распределить между целями',
    'restoreBudget': 'Вернуть сумму в бюджет категории',
    'recalcForecast': 'Пересчитать прогноз',
    'suggestNextGoal': 'Предложить направлять взносы на следующую цель',
  };

  /// Which conditions and actions fit a trigger.
  static const compatible = {
    'income': (
      {'tag', 'payee', 'category', 'amountMin', 'account'},
      {'notify', 'suggestGoals'},
    ),
    'refund': (
      {'payee', 'category', 'amountMin', 'account'},
      {'notify', 'restoreBudget'},
    ),
    'budgetThreshold': ({'budget', 'percentMin'}, {'notify'}),
    'incomeDateChanged': ({'payee'}, {'notify', 'recalcForecast'}),
    'goalFunded': (<String>{}, {'notify', 'suggestNextGoal'}),
  };

  /// Problems that stop a rule from being saved (empty — fine).
  static List<String> validate(PersonalRule r, FinanceData data) {
    final out = <String>[];
    final fit = compatible[r.trigger];
    if (fit == null) return ['Неизвестное событие'];
    if (r.name.trim().isEmpty) out.add('Назовите правило');
    if (r.actions.isEmpty) out.add('Добавьте действие');
    for (final c in r.conditions) {
      if (!fit.$1.contains(c['field'])) {
        out.add(
          'Условие «${conditionFields[c['field']] ?? c['field']}» не подходит к событию',
        );
      }
    }
    for (final a in r.actions) {
      if (!fit.$2.contains(a['type'])) {
        out.add(
          'Действие «${actionTypes[a['type']] ?? a['type']}» не подходит к событию',
        );
      }
      if (a['type'] == 'suggestGoals') {
        final shares = Map<String, Object?>.from(a['shares'] as Map? ?? {});
        final sum = shares.values.fold<int>(
          0,
          (s, v) => s + ((v as num?)?.toInt() ?? 0),
        );
        if (shares.isEmpty) out.add('Укажите цели и доли');
        if (sum > 100) out.add('Доли целей больше 100 %');
        for (final id in shares.keys) {
          if (!data.goals.any((g) => g.id == id)) out.add('Цель не найдена');
        }
      }
    }
    return out;
  }

  /// Conflicts with the other enabled rules (same trigger, same budget).
  static List<String> conflicts(PersonalRule r, List<PersonalRule> all) {
    final out = <String>[];
    bool changesBudget(PersonalRule x) =>
        x.actions.any((a) => a['type'] == 'restoreBudget');
    bool splitsIncome(PersonalRule x) =>
        x.actions.any((a) => a['type'] == 'suggestGoals');
    for (final o in all) {
      if (o.id == r.id || !o.enabled || o.trigger != r.trigger) continue;
      if (changesBudget(r) && changesBudget(o)) {
        out.add(
          '«${o.name}» тоже меняет бюджет при этом событии — сработает правило с меньшим номером приоритета.',
        );
      }
      if (splitsIncome(r) && splitsIncome(o)) {
        out.add(
          '«${o.name}» тоже распределяет этот доход — предложения могут пересекаться.',
        );
      }
    }
    return out;
  }

  /// Events in the change [before] → [after].
  static List<RuleEvent> events(
    FinanceData before,
    FinanceData after, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final out = <RuleEvent>[];
    final old = {for (final e in before.entries) e.id: e};
    for (final e in after.entries) {
      if (old.containsKey(e.id) || e.status != 'posted' || !e.isOrdinary) {
        continue;
      }
      if (e.kind == EntryKind.income) {
        final key = PayeeSummary.key(e.payee);
        final refund =
            e.tags.any((t) => t.toLowerCase().contains('возврат')) ||
            (key.isNotEmpty &&
                after.entries.any(
                  (x) =>
                      x.kind == EntryKind.expense &&
                      PayeeSummary.key(x.payee) == key &&
                      !x.date.isAfter(e.date) &&
                      e.date.difference(x.date).inDays <= 90,
                ));
        out.add(
          RuleEvent(
            refund ? 'refund' : 'income',
            '${refund ? 'refund' : 'income'}:${e.id}',
            entry: e,
          ),
        );
      }
      if (e.kind == EntryKind.expense) {
        for (final b in after.budgets) {
          if (b.categoryId != null && b.categoryId != e.categoryId) continue;
          final (start, end) = _period(after, clock);
          final limit = effectiveLimit(after, b, start);
          if (limit <= 0) continue;
          final spent = FinanceEngine.budgetSpent(b, after.entries, start, end);
          final pct = spent * 100 ~/ limit;
          out.add(
            RuleEvent(
              'budgetThreshold',
              'budget:${b.id}:${start.toIso8601String()}',
              budget: b,
              entry: e,
              percent: pct,
            ),
          );
        }
      }
    }
    final oldRules = {for (final r in before.recurring) r.id: r};
    for (final r in after.recurring) {
      final was = oldRules[r.id];
      if (was != null &&
          r.kind == EntryKind.income &&
          was.nextDate != r.nextDate) {
        out.add(
          RuleEvent(
            'incomeDateChanged',
            'incomeDate:${r.id}:${r.nextDate.toIso8601String()}',
            rule: r,
          ),
        );
      }
    }
    for (final g in after.goals) {
      final was = before.goals.where((x) => x.id == g.id).firstOrNull;
      final savedBefore = was == null
          ? 0
          : FinanceEngine.goalSaved(was, before.entries);
      final savedAfter = FinanceEngine.goalSaved(g, after.entries);
      if (savedBefore < g.targetMinor && savedAfter >= g.targetMinor) {
        out.add(RuleEvent('goalFunded', 'goalFunded:${g.id}', goal: g));
      }
    }
    return out;
  }

  /// A budget's room for the period starting [start]: its limit plus the
  /// adjustments made for that period.
  static int effectiveLimit(FinanceData data, Budget b, DateTime start) =>
      b.limitMinor +
      data.extras.budgetAdjustments
          .where((a) => a.budgetId == b.id && a.periodStart == start)
          .fold<int>(0, (s, a) => s + a.amountMinor);

  static (DateTime, DateTime) _period(FinanceData data, DateTime now) {
    final day = data.preferences.monthStart;
    var start = DateTime(now.year, now.month, day);
    if (start.isAfter(now)) start = DateTime(now.year, now.month - 1, day);
    return (start, DateTime(start.year, start.month + 1, start.day));
  }

  /// Runs the enabled rules on [events]. Returns the outcomes and, unless
  /// [dryRun], [data] with the runs, notices and budget changes saved.
  static (FinanceData, List<RuleOutcome>) process(
    FinanceData data,
    List<RuleEvent> events, {
    DateTime? now,
    bool dryRun = false,
    List<PersonalRule>? only,
  }) {
    final clock = now ?? DateTime.now();
    final rules = [
      ...(only ?? data.extras.rules).where((r) => r.enabled || only != null),
    ]..sort((a, b) => a.priority.compareTo(b.priority));
    final done = {
      for (final r in data.extras.ruleRuns) '${r.ruleId}|${r.eventKey}',
    };
    final outcomes = <RuleOutcome>[];
    final runs = <RuleRun>[],
        notices = <RuleNotice>[],
        adjustments = <BudgetAdjustment>[];
    final budgetTouched = <String>{};
    var n = 0;
    String id() => 'rule-${clock.microsecondsSinceEpoch}-${n++}';
    for (final event in events) {
      for (final rule in rules) {
        if (rule.trigger != event.type) continue;
        if (done.contains('${rule.id}|${event.key}')) {
          if (dryRun) {
            outcomes.add(
              RuleOutcome(
                rule,
                event,
                false,
                'Это событие уже обработано раньше — повторно не выполняется.',
              ),
            );
          }
          continue;
        }
        // Budget notices: once per the rule's period.
        final failed = _failedCondition(rule, event, data);
        if (failed != null) {
          final o = RuleOutcome(rule, event, false, 'Не сработало: $failed.');
          outcomes.add(o);
          // A budget below the threshold may still cross it later this
          // period, so it is not marked as processed.
          if (event.type != 'budgetThreshold') {
            runs.add(
              RuleRun(
                ruleId: rule.id,
                eventKey: event.key,
                at: clock,
                fired: false,
                explanation: o.explanation,
              ),
            );
          }
          continue;
        }
        final myNotices = <RuleNotice>[];
        final myAdjust = <BudgetAdjustment>[];
        final words = <String>[];
        for (final a in rule.actions) {
          switch (a['type']) {
            case 'notify':
              final text = _text(
                a['text'] as String? ?? rule.name,
                event,
                data,
              );
              myNotices.add(
                RuleNotice(
                  id: id(),
                  ruleId: rule.id,
                  at: clock,
                  kind: 'notify',
                  text: text,
                ),
              );
              words.add('уведомление');
            case 'suggestGoals':
              final shares = Map<String, Object?>.from(
                a['shares'] as Map? ?? {},
              );
              final amount = event.entry?.amountMinor ?? 0;
              final parts = <String, int>{
                for (final e in shares.entries)
                  e.key: amount * ((e.value as num?)?.toInt() ?? 0) ~/ 100,
              };
              final names = {for (final g in data.goals) g.id: g.name};
              myNotices.add(
                RuleNotice(
                  id: id(),
                  ruleId: rule.id,
                  at: clock,
                  kind: 'suggestGoals',
                  text:
                      'Доход ${_m(amount)}: предлагаю отложить ${parts.entries.map((e) => '${_m(e.value)} в «${names[e.key]}»').join(', ')}.',
                  payload: {'entryId': event.entry?.id, 'parts': parts},
                ),
              );
              words.add('предложение распределить');
            case 'restoreBudget':
              final entry = event.entry!;
              final budget = data.budgets
                  .where(
                    (b) =>
                        b.categoryId == entry.categoryId ||
                        // A refund is an income; its expense category is found by
                        // the place it came from.
                        b.categoryId == _expenseCategoryOf(entry, data),
                  )
                  .firstOrNull;
              if (budget == null) {
                words.add(
                  'бюджета для этой категории нет — ничего не изменено',
                );
                break;
              }
              if (budgetTouched.contains(budget.id)) {
                words.add(
                  'бюджет «${budget.name}» уже изменён другим правилом — пропущено',
                );
                break;
              }
              budgetTouched.add(budget.id);
              final (start, _) = _period(data, clock);
              if (a['auto'] == true) {
                myAdjust.add(
                  BudgetAdjustment(
                    id: id(),
                    budgetId: budget.id,
                    periodStart: start,
                    amountMinor: entry.amountMinor,
                    reason: 'Возврат ${_m(entry.amountMinor)} (${rule.name})',
                  ),
                );
                words.add(
                  'бюджет «${budget.name}» увеличен на ${_m(entry.amountMinor)} в этом периоде',
                );
              } else {
                myNotices.add(
                  RuleNotice(
                    id: id(),
                    ruleId: rule.id,
                    at: clock,
                    kind: 'restoreBudget',
                    text:
                        'Возврат ${_m(entry.amountMinor)}: вернуть эту сумму в бюджет «${budget.name}»?',
                    payload: {
                      'budgetId': budget.id,
                      'amountMinor': entry.amountMinor,
                      'periodStart': start.toIso8601String(),
                    },
                  ),
                );
                words.add('предложение вернуть в бюджет');
              }
            case 'recalcForecast':
              final plan = IncomePlanner.plan(data, now: clock);
              myNotices.add(
                RuleNotice(
                  id: id(),
                  ruleId: rule.id,
                  at: clock,
                  kind: 'notify',
                  text: plan.gapDate == null
                      ? 'Дата дохода «${event.rule?.name}» изменилась. Прогноз пересчитан: разрыва нет, свободно ${_m(plan.availableNowMinor)}.'
                      : 'Дата дохода «${event.rule?.name}» изменилась. ${_d(plan.gapDate!)} не хватит ${_m(plan.gapMinor)} на платежи.',
                ),
              );
              words.add('прогноз пересчитан');
            case 'suggestNextGoal':
              final plan = GoalPlanner.plan(data, now: clock);
              final freed = data.extras.goalFunding
                  .planFor(event.goal!.id)
                  .monthlyMinor;
              final next =
                  plan.goals
                      .where((g) => !g.done && g.goal.id != event.goal!.id)
                      .toList()
                    ..sort(
                      (a, b) => data.extras.goalFunding
                          .planFor(a.goal.id)
                          .priority
                          .compareTo(
                            data.extras.goalFunding.planFor(b.goal.id).priority,
                          ),
                    );
              if (next.isEmpty) {
                words.add('других целей нет');
                break;
              }
              myNotices.add(
                RuleNotice(
                  id: id(),
                  ruleId: rule.id,
                  at: clock,
                  kind: 'suggestNextGoal',
                  text:
                      '«${event.goal!.name}» накоплена. Направлять ${_m(freed)} в месяц на «${next.first.goal.name}»?',
                  payload: {
                    'from': event.goal!.id,
                    'to': next.first.goal.id,
                    'monthlyMinor': freed,
                  },
                ),
              );
              words.add('предложение для следующей цели');
          }
        }
        final explanation =
            'Сработало: ${_why(rule, event, data)}. Действие: ${words.join('; ')}.';
        outcomes.add(
          RuleOutcome(
            rule,
            event,
            true,
            explanation,
            notices: myNotices,
            adjustments: myAdjust,
          ),
        );
        runs.add(
          RuleRun(
            ruleId: rule.id,
            eventKey: event.key,
            at: clock,
            fired: true,
            explanation: explanation,
          ),
        );
        notices.addAll(myNotices);
        adjustments.addAll(myAdjust);
        done.add('${rule.id}|${event.key}');
      }
    }
    if (dryRun || runs.isEmpty) return (data, outcomes);
    final keepRuns = [...data.extras.ruleRuns, ...runs];
    return (
      data.copyWith(
        extras: data.extras.copyWith(
          ruleRuns: keepRuns.length > 2000
              ? keepRuns.sublist(keepRuns.length - 2000)
              : keepRuns,
          notices: [...data.extras.notices, ...notices],
          budgetAdjustments: [...data.extras.budgetAdjustments, ...adjustments],
        ),
      ),
      outcomes,
    );
  }

  static String? _expenseCategoryOf(FinanceEntry income, FinanceData data) {
    final key = PayeeSummary.key(income.payee);
    if (key.isEmpty) return null;
    final paid =
        data.entries
            .where(
              (e) =>
                  e.kind == EntryKind.expense &&
                  PayeeSummary.key(e.payee) == key,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return paid.firstOrNull?.categoryId;
  }

  /// The first condition that does not hold, in words; null — all hold.
  static String? _failedCondition(
    PersonalRule rule,
    RuleEvent e,
    FinanceData data,
  ) {
    for (final c in rule.conditions) {
      final v = c['value'];
      final text = '$v'.toLowerCase().trim();
      switch (c['field']) {
        case 'tag':
          if (!(e.entry?.tags.any((t) => t.toLowerCase().contains(text)) ??
              false)) {
            return 'нет метки «$v»';
          }
        case 'payee':
          final p = (e.entry?.payee ?? e.rule?.name ?? '').toLowerCase();
          if (!p.contains(text)) return 'в названии нет «$v»';
        case 'category':
          if (e.entry?.categoryId != v) {
            return 'другая категория';
          }
        case 'amountMin':
          final min = (v as num?)?.toInt() ?? 0;
          if ((e.entry?.amountMinor ?? 0) < min) {
            return 'сумма меньше ${_m(min)}';
          }
        case 'account':
          if (e.entry?.accountId != v) return 'другой счёт';
        case 'budget':
          if (e.budget?.id != v) return 'другой бюджет';
        case 'percentMin':
          final min = (v as num?)?.toInt() ?? 80;
          if ((e.percent ?? 0) < min) {
            return 'использовано ${e.percent ?? 0} %, порог $min %';
          }
      }
    }
    return null;
  }

  static String _why(PersonalRule rule, RuleEvent e, FinanceData data) {
    final what = switch (e.type) {
      'income' =>
        'доход ${_m(e.entry!.amountMinor)}${e.entry!.payee.isEmpty ? '' : ' от «${e.entry!.payee}»'}',
      'refund' =>
        'возврат ${_m(e.entry!.amountMinor)}${e.entry!.payee.isEmpty ? '' : ' от «${e.entry!.payee}»'}',
      'budgetThreshold' =>
        'бюджет «${e.budget!.name}» использован на ${e.percent} %',
      'incomeDateChanged' =>
        'дата дохода «${e.rule!.name}» теперь ${_d(e.rule!.nextDate)}',
      'goalFunded' => 'цель «${e.goal!.name}» накоплена',
      _ => e.type,
    };
    return rule.conditions.isEmpty ? what : '$what, все условия выполнены';
  }

  static String _text(String template, RuleEvent e, FinanceData data) =>
      template
          .replaceAll('{сумма}', _m(e.entry?.amountMinor ?? 0))
          .replaceAll('{процент}', '${e.percent ?? ''}')
          .replaceAll('{бюджет}', e.budget?.name ?? '')
          .replaceAll('{цель}', e.goal?.name ?? '');

  /// The five starting rules (off until the person turns them on).
  static List<PersonalRule> templates(
    FinanceData data,
    String Function() newId,
  ) {
    final goals = data.goals;
    return [
      PersonalRule(
        id: newId(),
        name: 'Доход с меткой — в цели',
        trigger: 'income',
        enabled: false,
        conditions: const [
          {'field': 'tag', 'value': 'проект'},
        ],
        actions: [
          {
            'type': 'suggestGoals',
            'shares': {if (goals.isNotEmpty) goals.first.id: 20},
          },
        ],
      ),
      PersonalRule(
        id: newId(),
        name: 'Возврат покупки — обратно в бюджет',
        trigger: 'refund',
        enabled: false,
        actions: const [
          {'type': 'restoreBudget', 'auto': false},
        ],
      ),
      PersonalRule(
        id: newId(),
        name: 'Бюджет близок к лимиту',
        trigger: 'budgetThreshold',
        enabled: false,
        conditions: [
          if (data.budgets.isNotEmpty)
            {'field': 'budget', 'value': data.budgets.first.id},
          const {'field': 'percentMin', 'value': 80},
        ],
        actions: const [
          {
            'type': 'notify',
            'text': 'Бюджет «{бюджет}» использован на {процент} %.',
          },
        ],
      ),
      PersonalRule(
        id: newId(),
        name: 'Перенос дохода — пересчитать прогноз',
        trigger: 'incomeDateChanged',
        enabled: false,
        actions: const [
          {'type': 'recalcForecast'},
        ],
      ),
      PersonalRule(
        id: newId(),
        name: 'Цель накоплена — взносы на следующую',
        trigger: 'goalFunded',
        enabled: false,
        actions: const [
          {'type': 'suggestNextGoal'},
        ],
      ),
    ];
  }

  /// «Когда получаю оплату за проект, предлагай 20% в резерв» → a rule
  /// draft; null when the phrase is not understood. Works without a model;
  /// the result is checked by [validate] before it can be turned on.
  static PersonalRule? fromPhrase(
    String text,
    FinanceData data,
    String Function() newId,
  ) {
    final t = text.toLowerCase().replaceAll('ё', 'е');
    final pct = RegExp(r'(\d{1,3})\s*%').firstMatch(t);
    if (RegExp(r'получ|доход|оплат|зарплат').hasMatch(t) && pct != null) {
      final about = RegExp(
        r'(?:за|от|по)\s+([а-яa-z0-9-]{3,})',
      ).firstMatch(t)?.group(1);
      final goal = data.goals.where((g) {
        final n = g.name.toLowerCase().replaceAll('ё', 'е');
        final stem = n.length > 5 ? n.substring(0, 5) : n;
        return t.contains(stem);
      }).firstOrNull;
      if (goal == null) return null;
      return PersonalRule(
        id: newId(),
        name: text.trim().length > 60
            ? '${text.trim().substring(0, 60)}…'
            : text.trim(),
        trigger: 'income',
        enabled: false,
        conditions: [
          if (about != null && !RegExp(r'^\d').hasMatch(about))
            {
              'field': 'payee',
              'value': about.length > 6
                  ? about.substring(0, about.length - 2)
                  : about,
            },
        ],
        actions: [
          {
            'type': 'suggestGoals',
            'shares': {goal.id: int.parse(pct.group(1)!)},
          },
        ],
      );
    }
    final limit = RegExp(r'(\d{1,3})\s*%').firstMatch(t);
    if (RegExp(r'бюджет|лимит').hasMatch(t) &&
        limit != null &&
        data.budgets.isNotEmpty) {
      final budget =
          data.budgets
              .where((b) => t.contains(b.name.toLowerCase()))
              .firstOrNull ??
          data.budgets.first;
      return PersonalRule(
        id: newId(),
        name: 'Бюджет «${budget.name}» — ${limit.group(1)} %',
        trigger: 'budgetThreshold',
        enabled: false,
        conditions: [
          {'field': 'budget', 'value': budget.id},
          {'field': 'percentMin', 'value': int.parse(limit.group(1)!)},
        ],
        actions: const [
          {
            'type': 'notify',
            'text': 'Бюджет «{бюджет}» использован на {процент} %.',
          },
        ],
      );
    }
    return null;
  }

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  static String _m(int v) {
    final s = (v.abs() ~/ 100).toString();
    final b = StringBuffer(v < 0 ? '−' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    final c = v.abs() % 100;
    return '$b${c == 0 ? '' : ',${c.toString().padLeft(2, '0')}'} ₽';
  }
}
