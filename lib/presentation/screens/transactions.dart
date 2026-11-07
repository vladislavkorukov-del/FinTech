import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/finance_engine.dart';
import '../controller.dart';
import '../widgets/amount_format.dart';
import '../widgets/common.dart';
import '../widgets/entry_tile.dart';
import 'entry_editor.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    this.categoryId,
    this.initialRange,
    this.accountId,
    this.goalId,
    this.initialKind,
    this.title,
  });
  final String? categoryId, accountId, goalId;

  /// Heading for a list opened by voice («Расходы · июнь 2026», 1.23).
  final String? title;
  final DateTimeRange? initialRange;
  final EntryKind? initialKind;
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _search = TextEditingController(),
      _min = TextEditingController(),
      _max = TextEditingController();
  String? _category, _account, _tag;
  EntryKind? _kind;
  DateTimeRange? _range;
  @override
  void initState() {
    super.initState();
    _category = widget.categoryId;
    _account = widget.accountId;
    _kind = widget.initialKind;
    _range = widget.initialRange;
  }

  @override
  void dispose() {
    _search.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  bool get filtered =>
      _category != null ||
      _account != null ||
      _tag != null ||
      _kind != null ||
      _range != null ||
      _min.text.isNotEmpty ||
      _max.text.isNotEmpty;
  Future<void> _filters() async {
    final c = FinanceScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(ctx).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Фильтры',
                          style: Theme.of(ctx).textTheme.headlineSmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          update(() {
                            _category = null;
                            _account = null;
                            _tag = null;
                            _kind = null;
                            _range = null;
                            _min.clear();
                            _max.clear();
                          });
                        },
                        child: const Text('Сбросить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<EntryKind?>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: 'Тип'),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('Все операции'),
                      ),
                      DropdownMenuItem(
                        value: EntryKind.expense,
                        child: Text('Расходы'),
                      ),
                      DropdownMenuItem(
                        value: EntryKind.income,
                        child: Text('Доходы'),
                      ),
                      DropdownMenuItem(
                        value: EntryKind.transfer,
                        child: Text('Переводы'),
                      ),
                    ],
                    onChanged: (v) => update(() => _kind = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Категория'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Все категории'),
                      ),
                      ...c.data.categories.map(
                        (a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ),
                    ],
                    onChanged: (v) => update(() => _category = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _account,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Счёт'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Все счета'),
                      ),
                      ...c.data.accounts.map(
                        (a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ),
                    ],
                    onChanged: (v) => update(() => _account = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _tag,
                    decoration: const InputDecoration(labelText: 'Тег'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Все теги'),
                      ),
                      ...c.data.entries
                          .expand((e) => e.tags)
                          .toSet()
                          .map(
                            (a) => DropdownMenuItem(value: a, child: Text(a)),
                          ),
                    ],
                    onChanged: (v) => update(() => _tag = v),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final r = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200, 12, 31),
                        initialDateRange: _range,
                      );
                      if (r != null) {
                        update(() => _range = r);
                      }
                    },
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      _range == null
                          ? 'За всё время'
                          : '${DateFormat('dd.MM.yy').format(_range!.start)} — ${DateFormat('dd.MM.yy').format(_range!.end)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Сумма в валюте операции; для сравнения разных валют выберите счёт.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _min,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [AmountGroupingFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'От суммы',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _max,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [AmountGroupingFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'До суммы',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      try {
                        final min = _min.text.isEmpty
                            ? null
                            : FinanceEngine.parseMinor(_min.text);
                        final max = _max.text.isEmpty
                            ? null
                            : FinanceEngine.parseMinor(_max.text);
                        if ((min ?? 0) < 0 ||
                            (max ?? 0) < 0 ||
                            min != null && max != null && min > max) {
                          throw const FormatException(
                            'Проверьте диапазон сумм',
                          );
                        }
                        Navigator.pop(ctx);
                      } catch (e) {
                        showError(ctx, e);
                      }
                    },
                    child: const Text('Показать операции'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final query = _search.text.toLowerCase().trim();
    int? safeParse(String s) {
      try {
        return s.isEmpty ? null : FinanceEngine.parseMinor(s);
      } catch (_) {
        return null;
      }
    }

    final min = safeParse(_min.text), max = safeParse(_max.text);
    final entries = c.data.entries.where((e) {
      return (widget.goalId == null || e.toGoalId == widget.goalId) &&
          (_kind == null || e.kind == _kind) &&
          (_category == null || e.categoryId == _category) &&
          (_account == null ||
              e.accountId == _account ||
              e.toAccountId == _account) &&
          (_tag == null || e.tags.contains(_tag)) &&
          (_range == null ||
              !e.date.isBefore(_range!.start) &&
                  e.date.isBefore(
                    DateTime(
                      _range!.end.year,
                      _range!.end.month,
                      _range!.end.day + 1,
                    ),
                  )) &&
          (min == null || e.amountMinor >= min) &&
          (max == null || e.amountMinor <= max) &&
          (query.isEmpty ||
              [
                e.payee,
                e.note,
                ...e.tags,
                c.category(e.categoryId)?.name ?? '',
                c.account(e.accountId)?.name ?? '',
                c.destinationName(e),
              ].join(' ').toLowerCase().contains(query));
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
    // 1.36: the list is never squeezed by the keyboard (on some phones its
    // height stayed after it closed and cut the list in half); it scrolls
    // under it instead, with room at the end while it is open.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          widget.goalId != null
              ? 'Мечта: ${c.goal(widget.goalId)?.name ?? 'Накопления'}'
              : widget.title ?? 'Операции',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Добавить операцию',
            onPressed: () => showEntryEditor(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Магазин, категория, комментарий',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: filtered,
                  child: IconButton(
                    tooltip: 'Фильтры',
                    onPressed: _filters,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    key: const ValueKey('transactions-count'),
                    _kind == null
                        ? '${entries.length} операций'
                        : '${entries.length} операций · ${money(entries.where((e) => e.currency == c.currency).fold(0, (sum, e) => sum + e.amountMinor), c.currency)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (filtered)
                  TextButton(
                    onPressed: () => setState(() {
                      _category = null;
                      _account = null;
                      _tag = null;
                      _kind = null;
                      _range = null;
                      _min.clear();
                      _max.clear();
                    }),
                    child: const Text('Сбросить фильтры'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const SingleChildScrollView(
                    child: EmptyState(
                      'Здесь пока тихо',
                      'Измените фильтры или добавьте первую операцию.',
                      icon: Icons.search_off_rounded,
                    ),
                  )
                : ListView.builder(
                    key: const ValueKey('transactions-list'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + keyboard),
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      final heading =
                          i == 0 ||
                          DateUtils.dateOnly(e.date) !=
                              DateUtils.dateOnly(entries[i - 1].date);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (heading)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 18,
                                bottom: 8,
                              ),
                              child: Text(
                                DateFormat('d MMMM, EEEE', 'ru').format(e.date),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          EntryTile(e),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
