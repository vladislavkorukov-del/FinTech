import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/planning/bill_split.dart';
import '../../controller.dart';
import '../../controller_phase8.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/grouped_list.dart' show confirmWithFinora;

/// «Я заплатил за всех»: split a saved expense, then record who paid back.
class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key, required this.entryId});
  final String entryId;
  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  final _names = [TextEditingController(), TextEditingController()];
  final _parts = <TextEditingController>[];
  final _own = TextEditingController();
  String _method = 'equal';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._names, ..._parts, _own]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _minor(String s) {
    try {
      return s.trim().isEmpty ? null : FinanceEngine.parseMinor(s);
    } catch (_) {
      return null;
    }
  }

  /// The parts by the chosen method: (own, others), or an error.
  (int, List<int>)? _computed(FinanceEntry e) {
    final n = _names.length;
    try {
      switch (_method) {
        case 'equal':
          return BillSplits.equal(e.amountMinor, n);
        case 'shares':
          final w = [
            int.tryParse(_own.text) ?? 1,
            for (var i = 0; i < n; i++) int.tryParse(_parts[i].text) ?? 1,
          ];
          return BillSplits.byShares(e.amountMinor, w);
        default:
          final parts = [
            for (var i = 0; i < n; i++) _minor(_parts[i].text) ?? 0,
          ];
          final own = e.amountMinor - parts.fold<int>(0, (a, b) => a + b);
          BillSplits.checkAmounts(e.amountMinor, own, parts);
          return (own, parts);
      }
    } on FormatException {
      return null;
    }
  }

  void _sync() {
    while (_parts.length < _names.length) {
      _parts.add(TextEditingController());
    }
    while (_parts.length > _names.length) {
      _parts.removeLast().dispose();
    }
  }

  Future<void> _create(FinanceController c, FinanceEntry e) async {
    final parts = _computed(e);
    if (parts == null) {
      showError(
        context,
        const FormatException('Проверьте доли: сумма должна совпасть'),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await c.splitEntry(
        e,
        own: parts.$1,
        names: [for (final n in _names) n.text],
        parts: parts.$2,
        method: _method,
      );
    } catch (err) {
      if (mounted) showError(context, err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repay(FinanceController c, ShareStatus s) async {
    final amount = TextEditingController(
      text: s.leftMinor > 0
          ? decimalMinor(s.leftMinor).replaceAll('.', ',')
          : '',
    );
    var account = c.data.accounts.where((a) => !a.archived).first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('${s.share.name} вернул(а)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('split-repay-amount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Сумма'),
              ),
              DropdownButtonFormField<String>(
                initialValue: account,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'На какой счёт'),
                items: [
                  for (final a in c.data.accounts.where((a) => !a.archived))
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => set(() => account = v ?? account),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const ValueKey('split-repay-save'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Записать'),
            ),
          ],
        ),
      ),
    );
    final value = _minor(amount.text);
    if (ok != true || value == null || !mounted) return;
    try {
      await c.repaySplit(s.share, amount: value, accountId: account);
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final entry = c.data.entries
        .where((e) => e.id == widget.entryId)
        .firstOrNull;
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Операция не найдена')),
      );
    }
    final split = c.data.extras.splits
        .where((s) => s.entryId == entry.id)
        .firstOrNull;
    final cur = entry.currency;
    Widget line(String a, int v, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(a)),
          Text(
            money(v, cur),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    if (split != null) {
      final s = BillSplits.status(c.data, split)!;
      return Scaffold(
        appBar: AppBar(title: const Text('Разделённый счёт')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            SurfaceCard(
              key: const ValueKey('split-summary'),
              child: Column(
                children: [
                  line('Ушло со счёта', s.outflowMinor),
                  line('Мой личный расход', s.personalMinor, bold: true),
                  line('Первоначально к возврату', s.initiallyOwedMinor),
                  line('Уже вернули', s.returnedMinor),
                  line(
                    'Осталось вернуть',
                    s.stillOwedMinor,
                    bold: true,
                    color: scheme.primary,
                  ),
                  if (s.overpaidMinor > 0)
                    line(
                      'Переплата (вернуть или учесть)',
                      s.overpaidMinor,
                      color: scheme.error,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Возврат долга поднимает остаток счёта, но не считается доходом.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SectionTitle('Участники'),
            for (final x in s.shares)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              x.share.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            '${money(x.leftMinor, cur)} из ${money(x.share.shareMinor, cur)}',
                          ),
                        ],
                      ),
                      for (final r in x.repayments)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${r.date.day}.${r.date.month.toString().padLeft(2, '0')} · вернул(а) ${money(r.amountMinor, cur)} · ${c.account(r.accountId)?.name ?? ''}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Отменить возврат',
                              icon: const Icon(Icons.undo_rounded, size: 18),
                              onPressed: () async {
                                if (await confirmWithFinora(
                                  context,
                                  title: 'Отменить возврат?',
                                  message:
                                      'Операция возврата ${money(r.amountMinor, cur)} будет удалена.',
                                  action: 'Отменить возврат',
                                  destructive: true,
                                )) {
                                  await c.cancelRepayment(r.id);
                                }
                              },
                            ),
                          ],
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: ValueKey('split-repay-${x.share.ruleId}'),
                          onPressed: () => _repay(c, x),
                          icon: const Icon(
                            Icons.call_received_rounded,
                            size: 18,
                          ),
                          label: const Text('Вернул(а)'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    _sync();
    final preview = _computed(entry);
    return Scaffold(
      appBar: AppBar(title: const Text('Я заплатил за всех')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SurfaceCard(
            child: Text(
              '${entry.payee.isEmpty ? 'Операция' : entry.payee}: ${money(entry.amountMinor, cur)}. '
              'Укажите, кто ещё участвовал, — Финора запишет их доли в «Мне должны».',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: const ValueKey('split-method'),
            segments: const [
              ButtonSegment(value: 'equal', label: Text('Поровну')),
              ButtonSegment(value: 'amount', label: Text('Суммами')),
              ButtonSegment(value: 'shares', label: Text('Долями')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          if (_method == 'shares')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: _own,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Моя доля (частей)',
                  hintText: '1',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < _names.length; i++)
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: ValueKey('split-name-$i'),
                    controller: _names[i],
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: 'Участник ${i + 1}'),
                  ),
                ),
                if (_method != 'equal') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: ValueKey('split-part-$i'),
                      controller: _parts[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _method == 'amount' ? 'Сумма' : 'Частей',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
                IconButton(
                  onPressed: _names.length <= 1
                      ? null
                      : () => setState(() => _names.removeAt(i).dispose()),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
              ],
            ),
          TextButton.icon(
            key: const ValueKey('split-add-person'),
            onPressed: () =>
                setState(() => _names.add(TextEditingController())),
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('Ещё участник'),
          ),
          const SizedBox(height: 8),
          if (preview != null)
            SurfaceCard(
              key: const ValueKey('split-preview'),
              child: Column(
                children: [
                  line('Мой личный расход', preview.$1, bold: true),
                  line('Должны вернуть', preview.$2.fold(0, (a, b) => a + b)),
                ],
              ),
            )
          else
            Text(
              'Доли не сходятся с суммой операции.',
              style: TextStyle(color: scheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('split-save'),
            onPressed: _busy || preview == null
                ? null
                : () => _create(c, entry),
            child: const Text('Разделить'),
          ),
        ],
      ),
    );
  }
}
