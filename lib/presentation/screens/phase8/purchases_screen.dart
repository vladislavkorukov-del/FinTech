import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/planning/purchase_math.dart';
import '../../controller.dart';
import '../../controller_phase8.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/grouped_list.dart' show confirmWithFinora;

int _minorOf(String s) {
  try {
    return s.trim().isEmpty ? 0 : FinanceEngine.parseMinor(s);
  } catch (_) {
    return 0;
  }
}

/// Opens a new purchase card; from an expense when [entry] is given (its
/// price and date are taken from it, so nothing is counted twice), or a
/// weighing before buying when [planned].
Future<void> showPurchaseEditor(
  BuildContext context, {
  Purchase? purchase,
  FinanceEntry? entry,
  bool planned = false,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) =>
        _PurchaseEditor(purchase: purchase, entry: entry, planned: planned),
  ),
);

/// «Покупки»: what things cost to own and what they gave.
class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final list = [...c.data.extras.purchases]
      ..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();
    final due = list
        .where(
          (p) =>
              p.remindAt != null &&
              !p.remindAt!.isAfter(now) &&
              p.satisfaction == null,
        )
        .toList();
    final stats = PurchaseMath.byMotive(list);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Покупки'),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('purchases-add'),
            icon: const Icon(Icons.add_rounded),
            onSelected: (v) =>
                showPurchaseEditor(context, planned: v == 'planned'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'bought', child: Text('Купленная вещь')),
              PopupMenuItem(
                value: 'planned',
                child: Text('Оценить до покупки'),
              ),
            ],
          ),
        ],
      ),
      body: list.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                'Карточек покупок нет',
                'Добавьте вещь — Финора посчитает стоимость владения и цену одного использования. '
                    'Из расхода: откройте операцию → «Карточка покупки».',
                icon: Icons.inventory_2_outlined,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final p in due)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurfaceCard(
                      onTap: () => showPurchaseEditor(context, purchase: p),
                      child: Text(
                        'Пора оценить «${p.name}»: довольны ли вы покупкой?',
                      ),
                    ),
                  ),
                for (final p in list)
                  () {
                    final cost = PurchaseMath.cost(p, c.data);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        key: ValueKey('purchase-${p.id}'),
                        onTap: () => showPurchaseEditor(context, purchase: p),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    p.planned
                                        ? 'Оценка до покупки · ${money(p.priceMinor, p.currency)}'
                                        : cost.perUseMinor == null
                                        ? 'Использований пока нет · владение ${money(cost.netMinor, p.currency)}'
                                        : '${money(cost.perUseMinor!, p.currency)} за использование · ${cost.uses} раз',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!p.planned)
                              IconButton.filledTonal(
                                key: ValueKey('purchase-use-${p.id}'),
                                tooltip: 'Отметить использование',
                                onPressed: () => c.addPurchaseEvent(
                                  p.id,
                                  PurchaseEvent(
                                    id: c.id(),
                                    kind: 'use',
                                    at: DateTime.now(),
                                    count: 1,
                                  ),
                                ),
                                icon: const Icon(Icons.plus_one_rounded),
                              ),
                          ],
                        ),
                      ),
                    );
                  }(),
                if (stats.isNotEmpty) ...[
                  const SectionTitle('Ваши оценки по мотивам'),
                  SurfaceCard(
                    child: Column(
                      children: [
                        for (final e in stats.entries)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(PurchaseMath.motives[e.key] ?? e.key),
                            subtitle: Text(
                              '${e.value.count} покуп. · купил бы снова: ${e.value.again}'
                              '${e.value.satisfaction == null ? '' : ' · довольны в среднем на ${e.value.satisfaction!.toStringAsFixed(1)} из 5'}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _PurchaseEditor extends StatefulWidget {
  const _PurchaseEditor({this.purchase, this.entry, this.planned = false});
  final Purchase? purchase;
  final FinanceEntry? entry;
  final bool planned;
  @override
  State<_PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<_PurchaseEditor> {
  late final _name = TextEditingController(
    text: widget.purchase?.name ?? widget.entry?.payee ?? '',
  );
  late final _price = TextEditingController(
    text: widget.purchase != null
        ? decimalMinor(widget.purchase!.priceMinor).replaceAll('.', ',')
        : widget.entry != null
        ? decimalMinor(widget.entry!.amountMinor).replaceAll('.', ',')
        : '',
  );
  late final _uses = TextEditingController(
    text: widget.purchase?.expectedUsesPerMonth?.toString() ?? '',
  );
  late final _months = TextEditingController(
    text: widget.purchase?.expectedMonths?.toString() ?? '',
  );
  late final _note = TextEditingController(text: widget.purchase?.note ?? '');
  late String _motive = widget.purchase?.motive ?? 'necessity';
  late int? _rating = widget.purchase?.satisfaction;
  late bool? _again = widget.purchase?.again;
  late DateTime? _remind = widget.purchase?.remindAt;

  @override
  void dispose() {
    for (final c in [_name, _price, _uses, _months, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Purchase _build(FinanceController c) {
    final base = widget.purchase;
    final entry = widget.entry;
    return Purchase(
      id: base?.id ?? c.id(),
      name: _name.text.trim(),
      date: base?.date ?? entry?.date ?? DateTime.now(),
      priceMinor: _minorOf(_price.text),
      currency: base?.currency ?? entry?.currency ?? c.currency,
      categoryId: base?.categoryId ?? entry?.categoryId,
      entryId: base?.entryId ?? entry?.id,
      motive: _motive,
      expectedUsesPerMonth: int.tryParse(_uses.text.trim()),
      expectedMonths: int.tryParse(_months.text.trim()),
      events: base?.events ?? const [],
      satisfaction: _rating,
      again: _again,
      note: _note.text.trim(),
      planned: base?.planned ?? widget.planned,
      remindAt: _remind,
    );
  }

  Future<void> _event(FinanceController c, Purchase p, String kind) async {
    final amount = TextEditingController();
    String? entryId;
    final recent =
        (c.data.entries.where((e) => e.kind == EntryKind.expense).toList()
              ..sort((a, b) => b.date.compareTo(a.date)))
            .take(30)
            .toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(
            PurchaseMath.costKinds[kind] ??
                (kind == 'sale' ? 'Продажа' : 'Возврат денег'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind != 'sale' && kind != 'refund')
                DropdownButtonFormField<String?>(
                  initialValue: entryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Связать с расходом',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Без операции — ввести сумму'),
                    ),
                    for (final e in recent)
                      DropdownMenuItem(
                        value: e.id,
                        child: Text(
                          '${e.payee.isEmpty ? 'Расход' : e.payee} · ${money(e.amountMinor, e.currency)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => set(() => entryId = v),
                ),
              if (entryId == null)
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Сумма'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    final value = _minorOf(amount.text);
    if (ok != true || (entryId == null && value <= 0)) return;
    await c.addPurchaseEvent(
      p.id,
      PurchaseEvent(
        id: c.id(),
        kind: kind,
        at: DateTime.now(),
        amountMinor: value,
        entryId: entryId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final saved = widget.purchase == null
        ? null
        : c.data.extras.purchases
              .where((p) => p.id == widget.purchase!.id)
              .firstOrNull;
    final cost = saved == null ? null : PurchaseMath.cost(saved, c.data);
    final cur = saved?.currency ?? c.currency;
    final draft = _build(c);
    Widget line(String a, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(a)),
          Text(
            v,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    final expectedPerUse =
        cost?.perExpectedUseMinor(draft) ??
        PurchaseCost(
          priceMinor: draft.priceMinor,
          upkeepMinor: 0,
          recoveredMinor: 0,
          uses: 0,
          expectedUses: null,
          months: 1,
        ).perExpectedUseMinor(draft);
    return Scaffold(
      appBar: AppBar(
        title: Text(draft.planned ? 'Оценка покупки' : 'Карточка покупки'),
        actions: [
          if (saved != null)
            IconButton(
              tooltip: 'Удалить карточку',
              onPressed: () async {
                if (await confirmWithFinora(
                  context,
                  title: 'Удалить карточку?',
                  message: 'Операции не изменятся.',
                  action: 'Удалить',
                  destructive: true,
                )) {
                  await c.deletePurchase(saved.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          TextField(
            key: const ValueKey('purchase-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Что купили'),
          ),
          TextField(
            key: const ValueKey('purchase-price'),
            controller: _price,
            enabled: draft.entryId == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Цена',
              helperText: draft.entryId != null
                  ? 'Из операции — не учитывается повторно'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _motive,
            decoration: const InputDecoration(labelText: 'Зачем купили'),
            items: [
              for (final e in PurchaseMath.motives.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _motive = v ?? _motive),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('purchase-uses'),
                  controller: _uses,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Раз в месяц (ожидание)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('purchase-months'),
                  controller: _months,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Месяцев владеть',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (expectedPerUse != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'По ожиданиям: ${money(expectedPerUse, cur)} за одно использование (цена ÷ ${int.parse(_uses.text) * int.parse(_months.text)} раз).',
                key: const ValueKey('purchase-expected'),
              ),
            ),
          if (cost != null && saved != null && !saved.planned) ...[
            const SectionTitle('Стоимость владения'),
            SurfaceCard(
              key: const ValueKey('purchase-cost'),
              child: Column(
                children: [
                  line('Цена', money(cost.priceMinor, cur)),
                  line(
                    'Обслуживание, ремонт, расходники',
                    money(cost.upkeepMinor, cur),
                  ),
                  line(
                    'Возврат или продажа',
                    '−${money(cost.recoveredMinor, cur)}',
                  ),
                  const Divider(),
                  line('Итого владение', money(cost.netMinor, cur), bold: true),
                  line(
                    'Использований (вы отмечали)',
                    '${cost.uses}${cost.expectedUses == null ? '' : ' из ожидаемых ${cost.expectedUses}'}',
                  ),
                  line(
                    'За одно использование',
                    cost.perUseMinor == null
                        ? 'использований нет'
                        : money(cost.perUseMinor!, cur),
                    bold: true,
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: const Text('+ использование'),
                  onPressed: () => c.addPurchaseEvent(
                    saved.id,
                    PurchaseEvent(
                      id: c.id(),
                      kind: 'use',
                      at: DateTime.now(),
                      count: 1,
                    ),
                  ),
                ),
                for (final k in ['service', 'repair', 'supplies'])
                  ActionChip(
                    label: Text(
                      '+ ${PurchaseMath.costKinds[k]!.toLowerCase()}',
                    ),
                    onPressed: () => _event(c, saved, k),
                  ),
                ActionChip(
                  label: const Text('+ возврат денег'),
                  onPressed: () => _event(c, saved, 'refund'),
                ),
                ActionChip(
                  label: const Text('+ продажа'),
                  onPressed: () => _event(c, saved, 'sale'),
                ),
              ],
            ),
          ],
          const SectionTitle('Оценка'),
          Row(
            children: [
              const Text('Довольны:'),
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: ValueKey('purchase-star-$i'),
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    (_rating ?? 0) >= i
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
          Row(
            children: [
              const Text('Купили бы снова?'),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Да'),
                selected: _again == true,
                onSelected: (_) => setState(() => _again = true),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Нет'),
                selected: _again == false,
                onSelected: (_) => setState(() => _again = false),
              ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_none_rounded),
            title: Text(
              _remind == null
                  ? 'Напомнить оценить (необязательно)'
                  : 'Напомнить ${_remind!.day}.${_remind!.month.toString().padLeft(2, '0')}.${_remind!.year}',
            ),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              setState(() => _remind = d);
            },
          ),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Заметка'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey('purchase-save'),
            onPressed: () async {
              final p = _build(c);
              if (p.name.isEmpty || p.priceMinor <= 0) {
                showError(
                  context,
                  const FormatException('Укажите название и цену'),
                );
                return;
              }
              await c.savePurchase(p);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ),
      ),
    );
  }
}
