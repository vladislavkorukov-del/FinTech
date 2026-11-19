import '../../domain/monetization.dart';
import 'developer_screen.dart';
import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:intl/intl.dart';

import '../../domain/amount_expression.dart';
import '../../domain/batch_entries.dart';
import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../../domain/service_catalog.dart';
import '../../domain/service_recognizer.dart';
import '../../features/finora_ai/services/finora_ai.dart';
import '../controller.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../widgets/amount_pad.dart';
import '../widgets/common.dart';

/// «Несколько операций»: several expenses and incomes at once — after a
/// shopping trip, from a paper list, from a note. Rows are typed one by one
/// or pasted as a list («кб 500», «такси 350», «зарплата +90 000»); each
/// gets its category the way the form does (the person's short names and
/// choices first). Nothing is saved until «Сохранить все»; then all rows go
/// in one step, on one account and date.
class BatchEntriesScreen extends StatefulWidget {
  const BatchEntriesScreen({super.key, this.initialText});

  /// A list to start from (one operation per line).
  final String? initialText;

  @override
  State<BatchEntriesScreen> createState() => _BatchEntriesScreenState();
}

class _Row {
  _Row(this.draft)
    : amount = TextEditingController(
        text: draft.amountMinor == null
            ? ''
            : AmountPad.format(draft.amountMinor!),
      ),
      payee = TextEditingController(text: draft.payee);
  final BatchDraft draft;
  final TextEditingController amount, payee;
  final key = UniqueKey();
  String? error, categoryError;

  void dispose() {
    amount.dispose();
    payee.dispose();
  }
}

class _BatchEntriesScreenState extends State<BatchEntriesScreen> {
  final _rows = <_Row>[];
  String? _account;
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = FinanceScope.of(context);
    _account ??= c.data.accounts.where((a) => !a.archived).firstOrNull?.id;
    if (_rows.isEmpty) {
      final text = widget.initialText;
      if (text != null && text.trim().isNotEmpty) {
        _rows.addAll(_parse(c, text).map(_Row.new));
      }
      if (_rows.isEmpty) {
        _rows.addAll([_Row(BatchDraft()), _Row(BatchDraft())]);
      }
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  List<BatchDraft> _parse(FinanceController c, String text) {
    final ai = FinoraAi.instance;
    return BatchEntries.parse(
      text,
      categories: c.data.categories.where((k) => !k.archived).toList(),
      history: c.data.entries,
      resolvePayee: (p) => ai.resolvePayee(c.data, p),
      rememberedCategory: (p, kind) => ai.rememberedCategory(c.data, p, kind),
    );
  }

  /// The category for a typed place: the person's memory, then Finora's
  /// classifier when she is sure.
  void _guessCategory(FinanceController c, _Row row) {
    final text = row.payee.text.trim();
    if (text.length < 2) return;
    final ai = FinoraAi.instance;
    final remembered = ai.rememberedCategory(c.data, text, row.draft.kind);
    String? category = remembered;
    if (category == null && c.data.preferences.ai.enabled) {
      final result = ai.classify(c.data, merchant: text, kind: row.draft.kind);
      final best = result.best;
      if (best != null && best.confidence >= .6) category = best.categoryId;
    }
    if (category != null) setState(() => row.draft.categoryId = category);
  }

  Future<void> _paste() async {
    final field = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вставить списком'),
        content: TextField(
          key: const ValueKey('batch-paste-field'),
          controller: field,
          autofocus: true,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText:
                'Одна операция в строке:\nкб 500\nтакси 350\n'
                'обед 450+120\nзарплата +90 000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('batch-paste-add'),
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    field.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final c = FinanceScope.of(context);
    final drafts = _parse(c, text);
    setState(() {
      // Empty rows give way to the list.
      _rows.removeWhere((r) {
        final empty =
            r.amount.text.trim().isEmpty && r.payee.text.trim().isEmpty;
        if (empty) r.dispose();
        return empty;
      });
      _rows.addAll(drafts.map(_Row.new));
    });
  }

  int? _amountOf(_Row r) {
    final text = r.amount.text.trim();
    if (text.isEmpty) return null;
    if (AmountExpression.isCalculation(text)) {
      return AmountExpression.evaluate(text);
    }
    try {
      return FinanceEngine.parseMinor(text);
    } catch (_) {
      return null;
    }
  }

  int get _total {
    var total = 0;
    for (final r in _rows) {
      final v = _amountOf(r);
      if (v == null || v <= 0) continue;
      total += r.draft.kind == EntryKind.income ? v : -v;
    }
    return total;
  }

  bool _blank(_Row r) =>
      r.amount.text.trim().isEmpty && r.payee.text.trim().isEmpty;

  Future<void> _saveAll() async {
    final c = FinanceScope.of(context);
    final account = c.account(_account ?? '');
    if (account == null) {
      showError(context, const FormatException('Выберите счёт.'));
      return;
    }
    final rows = _rows.where((r) => !_blank(r)).toList();
    var bad = false;
    for (final r in rows) {
      final v = _amountOf(r);
      r.error = v == null || v <= 0 ? 'Сумма?' : null;
      r.categoryError = c.category(r.draft.categoryId)?.kind == r.draft.kind
          ? null
          : 'Выберите категорию';
      bad |= r.error != null || r.categoryError != null;
    }
    if (rows.isEmpty) {
      showError(
        context,
        const FormatException('Добавьте хотя бы одну операцию.'),
      );
      return;
    }
    if (bad) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    final ai = FinoraAi.instance;
    final entries = [
      for (final r in rows)
        () {
          final payee = ai.resolvePayee(c.data, r.payee.text.trim());
          final known = payee.isEmpty
              ? null
              : ServiceRecognizer.find(payee) ?? ServiceCatalog.byName(payee);
          return FinanceEntry(
            id: c.id(),
            kind: r.draft.kind,
            amountMinor: _amountOf(r)!,
            currency: account.currency,
            accountId: account.id,
            categoryId: r.draft.categoryId,
            date: _date,
            payee: payee,
            serviceId: known == null || ServiceCatalog.banks.contains(known)
                ? null
                : known.id,
            memberId: c.data.members.any((m) => m.id == 'me')
                ? 'me'
                : (c.data.members.firstOrNull?.id ?? 'me'),
          );
        }(),
    ];
    try {
      await c.saveEntries(entries);
      if (!mounted) return;
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Сохранено операций: ${entries.length} · '
            '${money(_total, account.currency)}',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FeatureGate(
    featureId: PaidFeature.batchEntries,
    child: Builder(builder: _content),
  );

  Widget _content(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final accounts = c.data.accounts.where((a) => !a.archived).toList();
    final currency = c.account(_account ?? '')?.currency ?? c.currency;
    final filled = _rows.where((r) => !_blank(r)).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Несколько операций')),
        actions: [
          TextButton.icon(
            key: const ValueKey('batch-paste'),
            onPressed: _busy ? null : _paste,
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: Text(tr('Списком')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('batch-account'),
                  initialValue: _account,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Счёт')),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _account = v),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: const ValueKey('batch-date'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 366)),
                  );
                  if (picked != null) {
                    setState(
                      () => _date = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        _date.hour,
                        _date.minute,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  DateFormat('d MMM', AppLanguage.intl).format(_date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _rows.length; i++) _row(c, i, currency, scheme),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('batch-add-row'),
              onPressed: () => setState(() => _rows.add(_Row(BatchDraft()))),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Ещё строка')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Сумму можно посчитать прямо в строке: 450+120. '
              'Сокращения, которым вы научили Финору, станут полными названиями.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey('batch-save'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _busy || filled == 0 ? null : _saveAll,
            child: Text(
              filled == 0
                  ? tr('Сохранить все')
                  : 'Сохранить $filled · ${money(_total, currency)}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(FinanceController c, int i, String currency, ColorScheme scheme) {
    final r = _rows[i];
    final income = r.draft.kind == EntryKind.income;
    final categories = c.data.categories
        .where((k) => !k.archived && k.kind == r.draft.kind)
        .toList();
    final tone = income ? Colors.green.shade600 : scheme.onSurface;
    return Padding(
      key: r.key,
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: ValueKey('batch-kind-$i'),
                    tooltip: income ? 'Доход' : 'Расход',
                    onPressed: () => setState(() {
                      r.draft.kind = income
                          ? EntryKind.expense
                          : EntryKind.income;
                      r.draft.categoryId = null;
                      _guessCategory(c, r);
                    }),
                    icon: Icon(
                      income
                          ? Icons.add_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      color: tone,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: TextField(
                      key: ValueKey('batch-payee-$i'),
                      controller: r.payee,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: income ? 'Откуда' : 'Где / на что',
                        isDense: true,
                      ),
                      onChanged: (_) => _guessCategory(c, r),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      key: ValueKey('batch-amount-$i'),
                      controller: r.amount,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.text,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: tone,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        isDense: true,
                        errorText: r.error,
                        suffixText: currency == 'RUB' ? '₽' : currency,
                      ),
                      onChanged: (_) => setState(() => r.error = null),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('batch-remove-$i'),
                    tooltip: 'Убрать строку',
                    onPressed: () => setState(() {
                      _rows.removeAt(i).dispose();
                      if (_rows.isEmpty) _rows.add(_Row(BatchDraft()));
                    }),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 48, top: 4),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('batch-category-$i-${r.draft.categoryId}'),
                  initialValue:
                      categories.any((k) => k.id == r.draft.categoryId)
                      ? r.draft.categoryId
                      : null,
                  isExpanded: true,
                  isDense: true,
                  decoration: InputDecoration(
                    hintText: tr('Категория'),
                    isDense: true,
                    border: InputBorder.none,
                    errorText: r.categoryError,
                  ),
                  items: [
                    for (final k in categories)
                      DropdownMenuItem(
                        value: k.id,
                        child: Row(
                          children: [
                            Icon(
                              categoryIcon(k.icon),
                              size: 16,
                              color: Color(k.color),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                k.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    r.draft.categoryId = v;
                    r.categoryError = null;
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
