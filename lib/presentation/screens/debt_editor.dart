import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:intl/intl.dart';

import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../controller.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../widgets/common.dart';

/// What kind of debt is being added.
enum DebtKind {
  /// A loan or a credit card with interest.
  loan('Кредит', 'С процентами: банк, кредитка, ипотека'),

  /// An instalment plan or any debt without interest, paid monthly.
  instalment('Рассрочка', 'Без процентов, по графику'),

  /// Borrowed from a person.
  personal('Долг человеку', 'Занял у знакомого'),

  /// Someone owes the person.
  receivable('Мне должны', 'Дал в долг');

  const DebtKind(this.title, this.hint);
  final String title, hint;
}

/// Adds a debt as a payment with a whole sum (the existing payment plans
/// count what is paid and what is left; a loan with a rate gets the bank's
/// schedule). Nothing is paid by this: payments are confirmed by the person.
Future<void> showDebtEditor(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _DebtEditor(),
);

class _DebtEditor extends StatefulWidget {
  const _DebtEditor();
  @override
  State<_DebtEditor> createState() => _DebtEditorState();
}

class _DebtEditorState extends State<_DebtEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _total = TextEditingController();
  final _rate = TextEditingController();
  final _payment = TextEditingController();
  DebtKind _kind = DebtKind.loan;
  String? _account, _category;
  DateTime _next = DateTime.now().add(const Duration(days: 30));
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _total, _rate, _payment]) {
      c.dispose();
    }
    super.dispose();
  }

  EntryKind get _entryKind =>
      _kind == DebtKind.receivable ? EntryKind.income : EntryKind.expense;

  /// A category that fits debts: «Кредиты», «Долги»…, else the first one.
  String? _defaultCategory(FinanceController c) {
    final list = c.data.categories
        .where((k) => !k.archived && k.kind == _entryKind)
        .toList();
    final fit = RegExp(
      r'кредит|долг|займ|ипотек|рассроч|возврат',
      caseSensitive: false,
    );
    return (list.where((k) => fit.hasMatch(k.name)).firstOrNull ??
            list.firstOrNull)
        ?.id;
  }

  int? _minor(String text, {bool required = true}) {
    if (text.trim().isEmpty) return required ? null : 0;
    try {
      return FinanceEngine.parseMinor(text);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final c = FinanceScope.of(context);
    final account = c.account(_account ?? '');
    if (account == null) return;
    final total = _minor(_total.text)!;
    final payment = _minor(_payment.text)!;
    final rate = _kind == DebtKind.loan
        ? double.tryParse(_rate.text.replaceAll(',', '.').trim())
        : null;
    final withRate = rate != null && rate > 0;
    final rule = RecurringRule(
      id: c.id(),
      name: _name.text.trim(),
      accountId: account.id,
      currency: account.currency,
      categoryId: _category,
      kind: _entryKind,
      amountMinor: payment,
      frequency: 'monthly',
      nextDate: _next,
      paymentType: 'mandatory',
      // With a rate: the debt left today, the bank's schedule follows.
      totalMinor: withRate ? null : total,
      interestRate: withRate ? rate : null,
      principalMinor: withRate ? total : null,
      principalDate: withRate ? DateTime.now() : null,
      reminderEnabled: _entryKind == EntryKind.expense,
    );
    setState(() => _busy = true);
    try {
      await c.saveRecurring(rule);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final accounts = c.data.accounts.where((a) => !a.archived).toList();
    _account ??= accounts.firstOrNull?.id;
    final categories = c.data.categories
        .where((k) => !k.archived && k.kind == _entryKind)
        .toList();
    if (!categories.any((k) => k.id == _category)) {
      _category = _defaultCategory(c);
    }
    String? money(String? s) => _minor(s ?? '') == null || _minor(s ?? '')! <= 0
        ? 'Укажите сумму больше нуля'
        : null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Новый долг'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in DebtKind.values)
                    ChoiceChip(
                      key: ValueKey('debt-kind-${k.name}'),
                      label: Text(k.title),
                      selected: _kind == k,
                      onSelected: (_) => setState(() {
                        _kind = k;
                        _category = null;
                      }),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _kind.hint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('debt-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: switch (_kind) {
                    DebtKind.personal => 'Кому должен',
                    DebtKind.receivable => 'Кто должен',
                    _ => 'Название (банк, магазин)',
                  },
                ),
                validator: (s) =>
                    (s ?? '').trim().isEmpty ? 'Введите название' : null,
              ),
              TextFormField(
                key: const ValueKey('debt-total'),
                controller: _total,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _kind == DebtKind.loan
                      ? 'Сколько осталось долга'
                      : 'Сумма долга',
                ),
                validator: money,
              ),
              if (_kind == DebtKind.loan)
                TextFormField(
                  key: const ValueKey('debt-rate'),
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Ставка, % годовых',
                  ),
                  validator: (s) {
                    final v = double.tryParse(
                      (s ?? '').replaceAll(',', '.').trim(),
                    );
                    return v == null || v < 0 || v > 200
                        ? 'Ставка от 0 до 200 %'
                        : null;
                  },
                ),
              TextFormField(
                key: const ValueKey('debt-payment'),
                controller: _payment,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: switch (_kind) {
                    DebtKind.loan => 'Платёж в месяц (минимальный)',
                    DebtKind.receivable => 'Сколько возвращают в месяц',
                    _ => 'Сколько отдавать в месяц',
                  },
                ),
                validator: money,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('debt-account'),
                initialValue: _account,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Счёт')),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _account = v),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('debt-category-${_kind.name}'),
                initialValue: _category,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Категория')),
                items: [
                  for (final k in categories)
                    DropdownMenuItem(value: k.id, child: Text(k.name)),
                ],
                validator: (v) => v == null ? 'Выберите категорию' : null,
                onChanged: (v) => setState(() => _category = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Следующий платёж'),
                subtitle: Text(
                  DateFormat('d MMMM yyyy', AppLanguage.intl).format(_next),
                ),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _next,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (d != null) setState(() => _next = d);
                },
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('debt-save'),
                onPressed: _busy || accounts.isEmpty ? null : _save,
                child: const Text('Добавить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
