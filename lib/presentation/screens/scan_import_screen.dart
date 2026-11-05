import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../../domain/finance_engine.dart';
import '../../domain/scan_document.dart';
import '../../domain/scan_import.dart';
import '../controller.dart';
import '../widgets/common.dart';
import '../widgets/service_badge.dart';

class ScanImportScreen extends StatefulWidget {
  const ScanImportScreen({
    super.key,
    required this.document,
    required this.imagePath,
    this.initialAccountId,
  });
  final ScanDocument document;
  final String imagePath;
  final String? initialAccountId;
  @override
  State<ScanImportScreen> createState() => _ScanImportScreenState();
}

class _ScanImportScreenState extends State<ScanImportScreen> {
  List<ScanImportItem>? _items;
  String? _commonAccount;
  bool _busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items != null) return;
    _items = ScanImport.prepare(
      widget.document,
      FinanceScope.of(context).data,
      preferredAccountId: widget.initialAccountId,
    );
    _commonAccount = widget.initialAccountId;
  }

  Future<void> _edit(int index) async {
    final result = await Navigator.push<ScanImportItem>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ScannedOperationEditor(item: _items![index], index: index),
      ),
    );
    if (result != null && mounted) setState(() => _items![index] = result);
  }

  Future<void> _save() async {
    final c = FinanceScope.of(context);
    final items = List<ScanImportItem>.of(_items!);
    // Validate before asking about likely duplicates, then validate again inside
    // the serialized repository mutation against its latest snapshot.
    try {
      ScanImport.entries(items, c.data, newId: c.id);
      final duplicates = items
          .where((i) => i.selected && ScanImport.isPossibleDuplicate(i, c.data))
          .length;
      if (duplicates > 0 &&
          !await confirm(
            context,
            'Возможные повторы',
            '$duplicates выбранных операций похожи на уже сохранённые. Всё равно добавить?',
          )) {
        return;
      }
      if (!mounted) return;
      setState(() => _busy = true);
      await c.importScanned(items, attachmentPath: widget.imagePath);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = _items!;
    final selected = items.where((i) => i.selected).length;
    final accounts = c.data.accounts.where((a) => !a.archived).toList();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Операции со снимка')),
        body: SafeArea(
          child: ListView.builder(
            key: const ValueKey('scan-batch-list'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: items.length + 3,
            itemBuilder: (context, position) {
              if (position == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Распознано: ${items.length}',
                        key: const ValueKey('scan-batch-review'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Проверьте суммы, даты, категории и счета. Нажмите на операцию, чтобы исправить. Данные появятся в учёте после сохранения.',
                      ),
                      for (final warning in widget.document.warnings)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            warning,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: ValueKey('batch-account-$_commonAccount'),
                        initialValue:
                            accounts.any((a) => a.id == _commonAccount)
                            ? _commonAccount
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Общий счёт',
                        ),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.name} · ${a.currency}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (id) => setState(() {
                                _commonAccount = id;
                                final account = c.account(id!);
                                for (var i = 0; i < items.length; i++) {
                                  if (items[i].draft.currency ==
                                      account?.currency) {
                                    final updated = items[i].copyWith(
                                      accountId: id,
                                    );
                                    items[i] = updated.copyWith(
                                      selected: !ScanImport.isPossibleDuplicate(
                                        updated,
                                        c.data,
                                      ),
                                    );
                                  }
                                }
                              }),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Применяется к операциям в валюте этого счёта.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    for (var i = 0; i < items.length; i++) {
                                      items[i] = items[i].copyWith(
                                        selected:
                                            !ScanImport.isPossibleDuplicate(
                                              items[i],
                                              c.data,
                                            ),
                                      );
                                    }
                                  }),
                            child: const Text('Выбрать без повторов'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    for (var i = 0; i < items.length; i++) {
                                      items[i] = items[i].copyWith(
                                        selected: false,
                                      );
                                    }
                                  }),
                            child: const Text('Снять выбор'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }
              if (position == items.length + 1) {
                return ExpansionTile(
                  title: const Text('Распознанный текст'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        widget.document.drafts
                            .map((d) => d.rawText)
                            .join('\n\n'),
                      ),
                    ),
                  ],
                );
              }
              if (position == items.length + 2) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton.icon(
                    key: const ValueKey('save-scan-batch'),
                    onPressed: _busy || selected == 0 ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      _busy ? 'Сохранение…' : 'Сохранить выбранные: $selected',
                    ),
                  ),
                );
              }
              final index = position - 1;
              final item = items[index];
              final d = item.draft;
              final duplicate = ScanImport.isPossibleDuplicate(item, c.data);
              final account = c.account(item.accountId ?? '');
              final category = c.category(d.categoryId);
              final kindName = switch (d.kind) {
                EntryKind.income => 'Доход',
                EntryKind.expense => 'Расход',
                EntryKind.transfer => 'Перевод',
                null => 'Нужен тип операции',
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  onTap: _busy ? null : () => _edit(index),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        key: ValueKey('scan-select-$index'),
                        value: item.selected,
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => items[index] = item.copyWith(
                                  selected: value ?? false,
                                ),
                              ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ServiceBadge(name: d.payee, size: 30),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    d.payee?.isNotEmpty == true
                                        ? d.payee!
                                        : 'Операция ${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              d.amountMinor == null
                                  ? 'Укажите сумму'
                                  : '${d.kind == EntryKind.income
                                        ? '+'
                                        : d.kind == EntryKind.expense
                                        ? '−'
                                        : ''}${money(d.amountMinor!, d.currency ?? '?')}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: d.kind == EntryKind.expense
                                    ? FinanceColors.of(context).expense
                                    : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$kindName · ${d.date == null ? "Нужна дата" : displayDate(d.date!)}',
                            ),
                            Text(
                              '${category?.name ?? (d.kind == EntryKind.transfer ? "Между счетами" : "Нужна категория")} · ${account?.name ?? "Нужен счёт"}',
                            ),
                            if (duplicate)
                              Text(
                                'Возможный повтор — проверьте перед выбором',
                                style: TextStyle(color: scheme.error),
                              ),
                            for (final warning in d.warnings)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  warning,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: ValueKey('scan-edit-$index'),
                        tooltip: 'Редактировать операцию',
                        onPressed: _busy ? null : () => _edit(index),
                        icon: const Icon(Icons.edit_outlined, size: 19),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ScannedOperationEditor extends StatefulWidget {
  const _ScannedOperationEditor({required this.item, required this.index});
  final ScanImportItem item;
  final int index;
  @override
  State<_ScannedOperationEditor> createState() =>
      _ScannedOperationEditorState();
}

class _ScannedOperationEditorState extends State<_ScannedOperationEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount,
      _merchant,
      _comment,
      _received,
      _currency;
  EntryKind? _kind;
  String? _account, _category, _to;
  DateTime? _date;
  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final d = item.draft;
    _amount = TextEditingController(
      text: d.amountMinor == null ? '' : decimalMinor(d.amountMinor!),
    );
    _merchant = TextEditingController(text: d.payee ?? '');
    _comment = TextEditingController(text: d.comment);
    _received = TextEditingController(
      text: item.destinationMinor == null
          ? ''
          : decimalMinor(item.destinationMinor!),
    );
    _currency = TextEditingController(text: d.currency ?? '');
    _kind = d.kind;
    _category = d.categoryId;
    _date = d.date;
    _account = item.accountId;
    _to = item.toAccountId;
  }

  @override
  void dispose() {
    for (final c in [_amount, _merchant, _comment, _received, _currency]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date != null && mounted) {
      setState(
        () => _date = DateTime(
          date.year,
          date.month,
          date.day,
          _date?.hour ?? 0,
          _date?.minute ?? 0,
        ),
      );
    }
  }

  Future<void> _chooseTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date ?? DateTime.now()),
    );
    if (time != null && mounted) {
      setState(() {
        final d = _date ?? DateTime.now();
        _date = DateTime(d.year, d.month, d.day, time.hour, time.minute);
      });
    }
  }

  void _done() {
    if (!_form.currentState!.validate()) return;
    try {
      final amount = FinanceEngine.parseMinor(_amount.text);
      if (amount <= 0) {
        throw const FormatException('Сумма должна быть больше нуля.');
      }
      final item = widget.item.copyWith(
        draft: widget.item.draft.copyWith(
          amountMinor: amount,
          payee: _merchant.text.trim(),
          currency: _currency.text.trim().toUpperCase(),
          categoryId: _kind == EntryKind.transfer ? null : _category,
          kind: _kind,
          date: _date,
          comment: _comment.text.trim(),
        ),
        accountId: _account,
        toAccountId: _kind == EntryKind.transfer ? _to : null,
        destinationMinor:
            _kind != EntryKind.transfer || _received.text.trim().isEmpty
            ? null
            : FinanceEngine.parseMinor(_received.text),
      );
      ScanImport.entries(
        [item.copyWith(selected: true)],
        FinanceScope.of(context).data,
        newId: () => 'draft',
      );
      Navigator.pop(context, item);
    } catch (error) {
      showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final accounts = c.data.accounts.where((a) => !a.archived).toList();
    final cats = c.data.categories
        .where((a) => !a.archived && a.kind == _kind)
        .toList();
    final account = c.account(_account ?? '');
    final to = c.account(_to ?? '');
    return Scaffold(
      appBar: AppBar(title: Text('Операция ${widget.index + 1}')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
            children: [
              DropdownButtonFormField<EntryKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Тип операции'),
                items: const [
                  DropdownMenuItem(
                    value: EntryKind.expense,
                    child: Text('Расход'),
                  ),
                  DropdownMenuItem(
                    value: EntryKind.income,
                    child: Text('Доход'),
                  ),
                  DropdownMenuItem(
                    value: EntryKind.transfer,
                    child: Text('Перевод между счетами'),
                  ),
                ],
                onChanged: (kind) => setState(() {
                  _kind = kind;
                  _category = null;
                }),
                validator: (value) => value == null ? 'Выберите тип' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('scan-row-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Сумма'),
                validator: (value) {
                  try {
                    return FinanceEngine.parseMinor(value ?? '') > 0
                        ? null
                        : 'Введите сумму';
                  } catch (_) {
                    return 'Введите сумму с двумя знаками после запятой';
                  }
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _currency,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Валюта (RUB, USD…)',
                ),
                validator: (v) =>
                    RegExp(
                      r'^[A-Z]{3}$',
                    ).hasMatch((v ?? '').toUpperCase().trim())
                    ? null
                    : 'Укажите код валюты',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: accounts.any((a) => a.id == _account)
                    ? _account
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Счёт списания / поступления',
                ),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} · ${a.currency}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _account = id;
                }),
                validator: (v) => v == null ? 'Выберите счёт' : null,
              ),
              if (account != null &&
                  account.currency != _currency.text.trim().toUpperCase())
                TextButton(
                  onPressed: () =>
                      setState(() => _currency.text = account.currency),
                  child: Text(
                    'Исправить распознанную валюту на ${account.currency}',
                  ),
                ),
              const SizedBox(height: 14),
              if (_kind != EntryKind.transfer)
                DropdownButtonFormField<String>(
                  key: ValueKey('scan-row-category-$_kind-$_category'),
                  initialValue: cats.any((a) => a.id == _category)
                      ? _category
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Категория'),
                  items: [
                    for (final cat in cats)
                      DropdownMenuItem(
                        value: cat.id,
                        child: Text(cat.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() => _category = id),
                  validator: (v) => v == null ? 'Выберите категорию' : null,
                ),
              if (_kind == EntryKind.transfer) ...[
                DropdownButtonFormField<String>(
                  initialValue:
                      accounts.any((a) => a.id == _to && a.id != _account)
                      ? _to
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Счёт зачисления',
                  ),
                  items: [
                    for (final a in accounts.where((a) => a.id != _account))
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.name} · ${a.currency}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _to = id),
                  validator: (v) =>
                      v == null ? 'Выберите счёт зачисления' : null,
                ),
                if (to != null && account?.currency != to.currency) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _received,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Будет зачислено, ${to.currency}',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: _merchant,
                decoration: const InputDecoration(
                  labelText: 'Магазин / получатель',
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _chooseDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      _date == null ? 'Выбрать дату' : displayDate(_date!),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _chooseTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _date == null
                          ? 'Время'
                          : TimeOfDay.fromDateTime(_date!).format(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _comment,
                decoration: const InputDecoration(labelText: 'Комментарий'),
                maxLines: 3,
              ),
              ExpansionTile(
                title: const Text('Текст на снимке'),
                children: [SelectableText(widget.item.draft.rawText)],
              ),
              const SizedBox(height: 18),
              FilledButton(
                key: const ValueKey('apply-scan-row'),
                onPressed: _done,
                child: const Text('Применить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
