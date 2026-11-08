import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/entry_tile.dart';
import '../tutorial.dart';
import 'world_components.dart';

class WorldReviewScreen extends StatefulWidget {
  const WorldReviewScreen({super.key});

  @override
  State<WorldReviewScreen> createState() => _WorldReviewScreenState();
}

class _WorldReviewScreenState extends State<WorldReviewScreen> {
  String _period = 'week';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final now = c.achievementClock();
    final key = _period == 'week'
        ? WorldCatalog.weekKey(now)
        : WorldCatalog.monthKey(now);
    final start = DateTime.parse(_period == 'week' ? key : '$key-01');
    final end = _period == 'week'
        ? DateTime(start.year, start.month, start.day + 7)
        : DateTime(start.year, start.month + 1);
    final entries = c.data.entries
        .where(
          (entry) =>
              entry.status == 'posted' &&
              entry.kind != EntryKind.transfer &&
              !entry.date.isBefore(start) &&
              entry.date.isBefore(end),
        )
        .toList();
    final currencies = {c.currency, ...entries.map((e) => e.currency)}.toList();
    final confirmed = c.data.world.rewards.containsKey('review:$_period:$key');
    final amount = WorldCatalog
        .rewards[_period == 'week' ? 'review_week' : 'review_month']!;
    return WorldPage(
      title: 'Финансовый обзор',
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final period in const ['week', 'month'])
              ChoiceChip(
                key: ValueKey('world-review-$period'),
                label: Text(
                  period == 'week' ? 'Прошлая неделя' : 'Прошлый месяц',
                ),
                selected: _period == period,
                onSelected: (_) => setState(() => _period = period),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            '${displayDate(start)} — ${displayDate(end.subtract(const Duration(days: 1)))}',
          ),
        ),
        for (final currency in currencies)
          Builder(
            builder: (context) {
              final totals = FinanceEngine.totals(
                c.data.entries,
                start,
                end,
                currency,
              );
              return WorldPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currency,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final kind in const [
                      EntryKind.income,
                      EntryKind.expense,
                    ])
                      Builder(
                        builder: (context) {
                          final total = kind == EntryKind.income
                              ? totals.income
                              : totals.expense;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              kind == EntryKind.income ? 'Доходы' : 'Расходы',
                            ),
                            subtitle: Text(money(total, currency)),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => worldOpen(
                              context,
                              WorldReviewSourceScreen(
                                start: start,
                                end: end,
                                currency: currency,
                                kind: kind,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        Text(
          '${entries.length} учтённых операций. Переводы между своими счетами исключены.',
        ),
        const SizedBox(height: 16),
        if (c.data.demo)
          const Text(
            'Это демонстрационные данные. Награда за обзор доступна для вашего учёта.',
          )
        else ...[
          FilledButton.tonalIcon(
            key: const ValueKey('world-review-confirm'),
            onPressed: confirmed || _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    await worldAttempt(
                      context,
                      () => c.confirmWorldReview(_period),
                    );
                    if (mounted) setState(() => _saving = false);
                  },
            icon: Icon(
              confirmed
                  ? Icons.check_circle_outline
                  : Icons.fact_check_outlined,
            ),
            label: Text(confirmed ? 'Обзор подтверждён' : 'Подтвердить обзор'),
          ),
          const SizedBox(height: 6),
          Text(
            confirmed
                ? 'Награда за этот период уже сохранена.'
                : '${amount.xp} опыта и ${amount.sparks} искр. Один раз за период.',
          ),
        ],
      ],
    );
  }
}

/// Exact drill-down for the displayed figure, including posted status and
/// currency. EntryTile opens the existing, unchanged transaction editor.
class WorldReviewSourceScreen extends StatelessWidget {
  const WorldReviewSourceScreen({
    super.key,
    required this.start,
    required this.end,
    required this.currency,
    required this.kind,
  });
  final DateTime start, end;
  final String currency;
  final EntryKind kind;

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final entries =
        c.data.entries
            .where(
              (entry) =>
                  entry.status == 'posted' &&
                  entry.currency == currency &&
                  entry.kind == kind &&
                  !entry.date.isBefore(start) &&
                  entry.date.isBefore(end),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return WorldPage(
      key: const ValueKey('world-review-source'),
      title: '${kind == EntryKind.income ? 'Доходы' : 'Расходы'} · $currency',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${displayDate(start)} — ${displayDate(end.subtract(const Duration(days: 1)))}',
          ),
        ),
        if (entries.isEmpty)
          const EmptyState(
            'Нет операций',
            'За этот период нет учтённых операций выбранного типа и валюты.',
          ),
        for (final entry in entries)
          EntryTile(
            entry,
            key: ValueKey('world-source-${entry.id}'),
            swipe: false,
          ),
      ],
    );
  }
}

class WorldSettingsScreen extends StatelessWidget {
  const WorldSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final state = c.data.world;
    return WorldPage(
      title: 'Настройки мира',
      children: [
        WorldPanel(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                key: const ValueKey('world-reduce-motion'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Спокойный режим'),
                subtitle: const Text('Меньше движения и праздничных эффектов'),
                value: state.reducedMotion,
                onChanged: (value) => worldAttempt(
                  context,
                  () => c.worldSettings(reducedMotion: value),
                ),
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('world-remarks'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Реплики Финоры'),
                subtitle: const Text('Короткие подсказки только внутри мира'),
                value: state.remarks,
                onChanged: (value) => worldAttempt(
                  context,
                  () => c.worldSettings(remarks: value),
                ),
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('world-hide-private'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Скрывать личные сведения'),
                subtitle: const Text('Названия целей и суммы в альбоме'),
                value: state.hidePrivate,
                onChanged: (value) => worldAttempt(
                  context,
                  () => c.worldSettings(hidePrivate: value),
                ),
              ),
            ],
          ),
        ),
        const Text(
          'Системная настройка уменьшения движения действует независимо от спокойного режима.',
        ),
        const WorldHeading('Как получать искры'),
        const WorldPanel(
          child: Text(
            'Искры выдаются за первую цель, первую настройку обязательного платежа, '
            'завершение разбора операций без категории, обучение и подтверждённые обзоры. '
            'Награды за достижение целей ограничены первыми тремя целями, '
            'за игры — первым прохождением каждого уровня. '
            'Повторное открытие экрана и отдельные траты не приносят искры.',
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('world-tutorial'),
          onPressed: () => worldOpen(context, const TutorialScreen()),
          icon: const Icon(Icons.school_outlined),
          label: const Text('Открыть обучение'),
        ),
      ],
    );
  }
}
