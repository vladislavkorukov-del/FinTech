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

  int _sum(EntryKind kind) => _rows
      .where((r) => r.draft.kind == kind)
      .map(_amountOf)
      .whereType<int>()
      .where((v) => v > 0)
      .fold(0, (a, b) => a + b);

  Future<void> _pickDate() async {
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
  }

  Future<void> _pickCategory(FinanceController c, _Row r) async {
    final categories = c.data.categories
        .where((k) => !k.archived && k.kind == r.draft.kind)
        .toList();
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                tr('Категория'),
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            for (final k in categories)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: CircleAvatar(
                  backgroundColor: Color(k.color).withValues(alpha: .16),
                  child: Icon(
                    categoryIcon(k.icon),
                    size: 19,
                    color: Color(k.color),
                  ),
                ),
                title: Text(k.name),
                trailing: k.id == r.draft.categoryId
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(sheet).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(sheet, k.id),
              ),
          ],
        ),
      ),
    );
    if (id != null) {
      setState(() {
        r.draft.categoryId = id;
        r.categoryError = null;
      });
    }
  }

  Widget _content(BuildContext context) {
    final c = FinanceScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accounts = c.data.accounts.where((a) => !a.archived).toList();
    final account = c.account(_account ?? '');
    final currency = account?.currency ?? c.currency;
    final filled = _rows.where((r) => !_blank(r)).length;
    final spent = _sum(EntryKind.expense), earned = _sum(EntryKind.income);
    Widget pill({
      required Key key,
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    }) => Material(
      color: scheme.onSurface.withValues(alpha: .06),
      shape: const StadiumBorder(),
      child: InkWell(
        key: key,
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Несколько операций'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          // The summary: what the list adds up to, on which account and day.
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: .16),
                  scheme.primary.withValues(alpha: .04),
                ],
              ),
              border: Border.all(color: scheme.primary.withValues(alpha: .18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filled == 0 ? tr('Новый список') : '$filled ${_ops(filled)}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(_total, currency),
                    key: const ValueKey('batch-total'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.6,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (spent > 0 || earned > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (spent > 0) 'расходы ${money(spent, currency)}',
                        if (earned > 0) 'доходы ${money(earned, currency)}',
                      ].join(' · '),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PopupMenuButton<String>(
                      key: const ValueKey('batch-account'),
                      tooltip: tr('Счёт'),
                      onSelected: (v) => setState(() => _account = v),
                      itemBuilder: (_) => [
                        for (final a in accounts)
                          PopupMenuItem(value: a.id, child: Text(a.name)),
                      ],
                      child: IgnorePointer(
                        child: pill(
                          key: const ValueKey('batch-account-pill'),
                          icon: Icons.account_balance_wallet_outlined,
                          label: account?.name ?? tr('Счёт'),
                          onTap: () {},
                        ),
                      ),
                    ),
                    pill(
                      key: const ValueKey('batch-date'),
                      icon: Icons.event_outlined,
                      label: DateFormat(
                        'd MMMM',
                        AppLanguage.intl,
                      ).format(_date),
                      onTap: _pickDate,
                    ),
                    pill(
                      key: const ValueKey('batch-paste'),
                      icon: Icons.content_paste_rounded,
                      label: tr('Вставить списком'),
                      onTap: _busy ? null : _paste,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _rows.length; i++) _row(c, i, currency, scheme),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            key: const ValueKey('batch-add-row'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              side: BorderSide(color: scheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => setState(() => _rows.add(_Row(BatchDraft()))),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Ещё операция')),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              'Сумму можно посчитать прямо в строке: 450+120. Список можно '
              'вставить из заметки — «кб 500», «такси 350», «зарплата +90 000».',
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
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
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

  static String _ops(int n) {
    final t = n % 100;
    if (t >= 11 && t <= 14) return 'операций';
    return switch (n % 10) {
      1 => 'операция',
      2 || 3 || 4 => 'операции',
      _ => 'операций',
    };
  }

  Widget _row(FinanceController c, int i, String currency, ColorScheme scheme) {
    final r = _rows[i];
    final income = r.draft.kind == EntryKind.income;
    final category = c.data.categories
        .where((k) => k.id == r.draft.categoryId && k.kind == r.draft.kind)
        .firstOrNull;
    final tone = income ? Colors.green.shade600 : scheme.onSurface;
    final catColor = category == null
        ? scheme.onSurfaceVariant
        : Color(category.color);
    return Padding(
      key: r.key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: r.error != null || r.categoryError != null
                ? scheme.error.withValues(alpha: .6)
                : scheme.outlineVariant.withValues(alpha: .35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The category: its symbol; a tap chooses another.
                InkWell(
                  key: ValueKey('batch-category-$i-${r.draft.categoryId}'),
                  customBorder: const CircleBorder(),
                  onTap: () => _pickCategory(c, r),
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: catColor.withValues(alpha: .14),
                    child: Icon(
                      category == null
                          ? Icons.category_outlined
                          : categoryIcon(category.icon),
                      size: 20,
                      color: catColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: ValueKey('batch-payee-$i'),
                        controller: r.payee,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: income ? 'Откуда' : 'Где или на что',
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) => _guessCategory(c, r),
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () => _pickCategory(c, r),
                        child: Text(
                          r.categoryError ??
                              category?.name ??
                              tr('Выбрать категорию'),
                          style: TextStyle(
                            fontSize: 13,
                            color: r.categoryError != null
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: ValueKey('batch-amount-$i'),
                    controller: r.amount,
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.text,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: tone,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      suffixText: currency == 'RUB' ? ' ₽' : ' $currency',
                    ),
                    onChanged: (_) => setState(() => r.error = null),
                  ),
                ),
              ],
            ),
            if (r.error != null)
              Padding(
                padding: const EdgeInsets.only(left: 54, top: 4),
                child: Text(
                  'Укажите сумму',
                  style: TextStyle(color: scheme.error, fontSize: 12.5),
                ),
              ),
            Row(
              children: [
                const SizedBox(width: 50),
                ChoiceChip(
                  key: ValueKey('batch-kind-$i'),
                  label: Text(income ? 'Доход' : 'Расход'),
                  avatar: Icon(
                    income
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    size: 15,
                  ),
                  selected: income,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() {
                    r.draft.kind = income
                        ? EntryKind.expense
                        : EntryKind.income;
                    r.draft.categoryId = null;
                    _guessCategory(c, r);
                  }),
                ),
                const Spacer(),
                IconButton(
                  key: ValueKey('batch-remove-$i'),
                  tooltip: 'Убрать строку',
                  onPressed: () => setState(() {
                    _rows.removeAt(i).dispose();
                    if (_rows.isEmpty) _rows.add(_Row(BatchDraft()));
                  }),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
