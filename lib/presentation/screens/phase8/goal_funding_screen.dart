import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/planning/goal_planner.dart';
import '../../../domain/planning/income_planner.dart';
import '../../controller.dart';
import '../../controller_phase8.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';

/// «Цели и приоритеты» — the goals budget shared in a draft: change one
/// goal's contribution and see every goal's date move, then save.
class GoalFundingScreen extends StatefulWidget {
  const GoalFundingScreen({super.key});
  @override
  State<GoalFundingScreen> createState() => _GoalFundingScreenState();
}

class _GoalFundingScreenState extends State<GoalFundingScreen> {
  GoalFunding? _draft;
  final _budget = TextEditingController();
  final _monthly = <String, TextEditingController>{};

  @override
  void dispose() {
    _budget.dispose();
    for (final c in _monthly.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _minor(String s) {
    try {
      return s.trim().isEmpty ? 0 : FinanceEngine.parseMinor(s);
    } catch (_) {
      return 0;
    }
  }

  String _plain(int v) =>
      v == 0 ? '' : decimalMinor(v).replaceAll('.00', '').replaceAll('.', ',');

  GoalFunding _start(FinanceData d) {
    final f = d.extras.goalFunding;
    _budget.text = _plain(f.budgetMinor);
    for (var i = 0; i < d.goals.length; i++) {
      final g = d.goals[i];
      final p = f.planFor(g.id);
      _monthly[g.id] = TextEditingController(text: _plain(p.monthlyMinor));
    }
    return GoalFunding(
      budgetMinor: f.budgetMinor,
      plans: [
        for (var i = 0; i < d.goals.length; i++)
          () {
            final p = f.planFor(d.goals[i].id);
            return f.plans.any((x) => x.goalId == p.goalId)
                ? p
                : p.copyWith(priority: i);
          }(),
      ],
    );
  }

  void _update(GoalFunding f) => setState(() => _draft = f);

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cur = c.currency;
    final draft = _draft ??= _start(c.data);
    final saved = GoalPlanner.plan(c.data);
    final plan = GoalPlanner.plan(c.data, funding: draft);
    final shifts = {
      for (final s in GoalPlanner.compare(saved, plan)) s.goal.id: s,
    };
    final free = IncomePlanner.plan(c.data).availableNowMinor;
    String d(DateTime? x) => x == null
        ? 'не достижима'
        : '${x.day}.${x.month.toString().padLeft(2, '0')}.${x.year}';
    final order = [...c.data.goals]
      ..sort(
        (a, b) => draft
            .planFor(a.id)
            .priority
            .compareTo(draft.planFor(b.id).priority),
      );
    final changed =
        draft.toJson().toString() !=
        c.data.extras.goalFunding.toJson().toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Цели и приоритеты')),
      body: c.data.goals.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                'Целей нет',
                'Добавьте мечту — здесь появится распределение денег между целями.',
                icon: Icons.flag_outlined,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                TextField(
                  key: const ValueKey('goals-budget'),
                  controller: _budget,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Бюджет на цели в месяц, ₽',
                    helperText:
                        'Свободно сейчас по плану дохода: ${money(free, cur)}. Пусто — сумма взносов.',
                  ),
                  onChanged: (v) => _update(
                    GoalFunding(budgetMinor: _minor(v), plans: draft.plans),
                  ),
                ),
                if (plan.deficitMinor > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Не хватает ${money(plan.deficitMinor, cur)} в месяц: последние по приоритету цели получат меньше.',
                      key: const ValueKey('goals-deficit'),
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (draft.budgetMinor > 0 && draft.budgetMinor > free)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Бюджет больше свободных денег: сроки верны, только если придут ожидаемые доходы.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SectionTitle('Цели по приоритету'),
                for (var i = 0; i < order.length; i++)
                  () {
                    final g = order[i];
                    final p = draft.planFor(g.id);
                    final proj = plan.of(g.id)!;
                    final s = shifts[g.id];
                    return Padding(
                      key: ValueKey('goal-plan-${g.id}'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    g.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Выше',
                                  onPressed: i == 0
                                      ? null
                                      : () {
                                          final up = order[i - 1];
                                          final pu = draft
                                              .planFor(up.id)
                                              .priority;
                                          _update(
                                            _with(draft, [
                                              p.copyWith(priority: pu),
                                              draft
                                                  .planFor(up.id)
                                                  .copyWith(
                                                    priority: p.priority == pu
                                                        ? pu + 1
                                                        : p.priority,
                                                  ),
                                            ]),
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Накоплено ${money(proj.savedMinor, cur)} из ${money(g.targetMinor, cur)}',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: ValueKey('goal-monthly-${g.id}'),
                                    controller: _monthly[g.id],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Взнос в месяц, ₽',
                                    ),
                                    onChanged: (v) => _update(
                                      _with(draft, [
                                        p.copyWith(monthlyMinor: _minor(v)),
                                      ]),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  key: ValueKey('goal-protected-${g.id}'),
                                  label: const Text('Защищена'),
                                  selected: p.protected,
                                  onSelected: (v) => _update(
                                    _with(draft, [p.copyWith(protected: v)]),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              proj.done
                                  ? 'Накоплено'
                                  : 'Срок: ${d(proj.date)}'
                                        '${proj.allocatedMinor < proj.plannedMinor ? ' · получает ${money(proj.allocatedMinor, cur)}' : ''}'
                                        '${proj.reason.isNotEmpty && proj.date == null ? ' — ${proj.reason}' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (s?.days != null && s!.days != 0)
                              Text(
                                s.days! < 0
                                    ? 'приблизится на ${-s.days!} дн.'
                                    : 'отложится на ${s.days} дн.',
                                key: ValueKey('goal-shift-${g.id}'),
                                style: TextStyle(
                                  color: s.days! < 0
                                      ? Colors.green.shade700
                                      : scheme.error,
                                ),
                              )
                            else if (changed && s != null)
                              Text(
                                'без изменений',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            if (proj.needMonthlyMinor != null)
                              Text(
                                'К сроку ${d(g.deadline)} нужно ${money(proj.needMonthlyMinor!, cur)} в месяц',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }(),
                Text(
                  'Это план: деньги между счетами не переводятся. Одна сумма не '
                  'засчитывается в две цели.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
      bottomNavigationBar: c.data.goals.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  key: const ValueKey('goals-save'),
                  onPressed: !changed
                      ? null
                      : () async {
                          await c.saveGoalFunding(draft);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Вариант сохранён — он попадёт в историю планов',
                                ),
                              ),
                            );
                          }
                        },
                  child: Text(changed ? 'Сохранить вариант' : 'Сохранено'),
                ),
              ),
            ),
    );
  }

  GoalFunding _with(GoalFunding f, List<GoalPlan> changed) {
    final byId = {for (final p in f.plans) p.goalId: p};
    for (final p in changed) {
      byId[p.goalId] = p;
    }
    return GoalFunding(budgetMinor: f.budgetMinor, plans: byId.values.toList());
  }
}
