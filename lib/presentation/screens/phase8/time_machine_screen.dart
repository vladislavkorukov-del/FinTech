import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/models.dart';
import '../../../domain/planning/time_machine.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';

/// «Машина времени»: how the finances and plans looked on a past day and
/// what changed since. Looking back changes nothing.
class TimeMachineScreen extends StatefulWidget {
  const TimeMachineScreen({super.key});
  @override
  State<TimeMachineScreen> createState() => _TimeMachineScreenState();
}

class _TimeMachineScreenState extends State<TimeMachineScreen> {
  DateTime _date = DateTime.now().subtract(const Duration(days: 30));
  List<HistoryEvent>? _history;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final c = FinanceScope.of(context);
    await c.ensureSnapshot();
    final h = await c.repository.history();
    if (mounted) setState(() => _history = h);
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cur = c.currency;
    final history = _history;
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
    String dd(Object? iso) => iso == null ? '—' : d(DateTime.parse('$iso'));
    final view = history == null
        ? null
        : TimeMachine.view(c.data, history, _date);
    Widget pair(String label, String then, String now) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(width: 96, child: Text(then, textAlign: TextAlign.right)),
          SizedBox(
            width: 96,
            child: Text(
              now,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Машина времени')),
      body: view == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('time-machine-date'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.history_rounded),
                  label: Text('На дату ${d(_date)}'),
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  key: const ValueKey('time-machine-source'),
                  child: Text(
                    view.saved
                        ? 'Сохранённое состояние от ${d(view.then.at)}: так приложение видело финансы и планы.'
                        : 'Восстановлено по операциям: сохранённой истории на эту дату нет. Цели и правила — по текущим настройкам.',
                    style: TextStyle(
                      color: view.saved ? scheme.onSurface : scheme.error,
                    ),
                  ),
                ),
                const SectionTitle('Тогда и сейчас'),
                SurfaceCard(
                  child: Column(
                    children: [
                      pair('', d(_date), 'сейчас'),
                      pair(
                        'На счетах',
                        money(view.then.totalMinor, cur),
                        money(view.now.totalMinor, cur),
                      ),
                      pair(
                        'Свободно',
                        money(view.then.freeMinor, cur),
                        money(view.now.freeMinor, cur),
                      ),
                      pair(
                        'Обязательных платежей',
                        '${view.then.obligations.length}',
                        '${view.now.obligations.length}',
                      ),
                      pair(
                        'Ожидаемых доходов',
                        '${view.then.incomes.length}',
                        '${view.now.incomes.length}',
                      ),
                    ],
                  ),
                ),
                if (view.then.goals.isNotEmpty ||
                    view.now.goals.isNotEmpty) ...[
                  const SectionTitle('Цели'),
                  SurfaceCard(
                    child: Column(
                      children: [
                        for (final g in view.now.goals)
                          () {
                            final was = view.then.goals
                                .where((x) => x['id'] == g['id'])
                                .firstOrNull;
                            return pair(
                              '${g['name']}',
                              was == null ? '—' : dd(was['date']),
                              dd(g['date']),
                            );
                          }(),
                      ],
                    ),
                  ),
                ],
                const SectionTitle('Что изменилось'),
                SurfaceCard(
                  key: const ValueKey('time-machine-changes'),
                  child: view.changes.isEmpty
                      ? const Text('Существенных изменений нет.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final x in view.changes)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Text('• $x'),
                              ),
                          ],
                        ),
                ),
                if (view.lateEntries.isNotEmpty) ...[
                  const SectionTitle('Внесено или исправлено позже'),
                  SurfaceCard(
                    child: Column(
                      children: [
                        for (final e in view.lateEntries.take(30))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(e.payee.isEmpty ? 'Операция' : e.payee),
                            subtitle: Text(
                              'от ${d(e.date)}, внесена ${d(e.recordedAt!)}',
                            ),
                            trailing: Text(money(e.amountMinor, e.currency)),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Состояние сохраняется раз в день и после смены плана целей или сверки. '
                  'Просмотр прошлого ничего не меняет.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
    );
  }
}
