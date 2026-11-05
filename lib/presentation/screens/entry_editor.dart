import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/finance_engine.dart';
import '../controller.dart';
import '../widgets/common.dart';
import '../widgets/amount_pad.dart';
import 'management.dart';

Future<void> showEntryEditor(
  BuildContext context, {
  FinanceEntry? entry,
  EntryKind kind = EntryKind.expense,
  String? goalId,
}) async {
  final c = FinanceScope.of(context);
  final editingHistory =
      entry != null && c.data.entries.any((e) => e.id == entry.id);
  if (!editingHistory && c.data.accounts.where((a) => !a.archived).isEmpty) {
    if (await confirm(
          context,
          'Добавьте счёт',
          'Для операции нужен хотя бы один активный счёт. Открыть счета?',
        ) &&
        context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
      );
    }
    return;
  }
  if (context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => EntryEditor(entry: entry, kind: kind, goalId: goalId),
      ),
    );
  }
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, this.entry, required this.kind, this.goalId});
  final FinanceEntry? entry;
  final EntryKind kind;
  final String? goalId;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount, _destination, _payee, _note, _tags;
  late EntryKind _kind;
  String? _account, _to, _goal, _category, _subcategory, _attachment;
  bool _goalDestination = false;
  String _member = 'me', _status = 'posted', _recurrence = 'none';
  late DateTime _date;
  double? _lat, _lon;
  bool _advanced = false, _busy = false, _customPad = true;
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _kind = e?.kind ?? widget.kind;
    _amount = TextEditingController(
      text: e == null ? '' : decimalMinor(e.amountMinor),
    );
    _destination = TextEditingController(
      text: e?.destinationMinor == null
          ? ''
          : decimalMinor(e!.destinationMinor!),
    );
    _payee = TextEditingController(text: e?.payee ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _date = e?.date.toLocal() ?? DateTime.now();
    _account = e?.accountId;
    _to = e?.toAccountId;
    _goal = e?.toGoalId ?? widget.goalId;
    _goalDestination = _goal != null;
    _category = e?.categoryId;
    _subcategory = e?.subcategory;
    _attachment = e?.attachmentPath;
    _lat = e?.latitude;
    _lon = e?.longitude;
    _member = e?.memberId ?? 'me';
    _status = e?.status ?? 'posted';
    _recurrence = e?.recurrence ?? 'none';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = FinanceScope.of(context);
    if (!c.data.members.any((m) => m.id == _member) &&
        c.data.members.isNotEmpty) {
      _member = c.data.members.first.id;
    }
    if (_account == null) {
      final recent = [...c.data.entries]
        ..sort((a, b) => b.date.compareTo(a.date));
      _account =
          recent
              .map((e) => e.accountId)
              .where(
                (id) => c.data.accounts.any((a) => a.id == id && !a.archived),
              )
              .firstOrNull ??
          c.data.accounts.where((a) => !a.archived).first.id;
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _destination, _payee, _note, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _receipt() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (picked == null) {
        return;
      }
      final root = await getApplicationSupportDirectory();
      final folder = await Directory(
        '${root.path}/receipts',
      ).create(recursive: true);
      final file = await File(
        picked.path,
      ).copy('${folder.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
      if (mounted) {
        setState(() => _attachment = file.path);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  Future<void> _location() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const FormatException('Включите геолокацию на устройстве.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const FormatException('Доступ к геолокации не предоставлен.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() {
          _lat = p.latitude;
          _lon = p.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    final c = FinanceScope.of(context);
    setState(() => _busy = true);
    try {
      final a = c.account(_account!)!;
      final targetCurrency = _goalDestination
          ? c.goal(_goal)?.currency
          : c.account(_to ?? '')?.currency;
      final value = FinanceEngine.parseMinor(_amount.text);
      final entry = FinanceEntry(
        id: widget.entry?.id ?? c.id(),
        kind: _kind,
        amountMinor: value,
        currency: a.currency,
        accountId: a.id,
        toAccountId: _kind == EntryKind.transfer && !_goalDestination
            ? _to
            : null,
        toGoalId: _kind == EntryKind.transfer && _goalDestination
            ? _goal
            : null,
        destinationMinor: _kind == EntryKind.transfer
            ? (targetCurrency == a.currency
                  ? value
                  : FinanceEngine.parseMinor(_destination.text))
            : null,
        categoryId: _kind == EntryKind.transfer ? null : _category,
        subcategory: _kind == EntryKind.transfer ? null : _subcategory,
        date: _date,
        payee: _payee.text.trim(),
        note: _note.text.trim(),
        tags: _tags.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(),
        memberId: _member,
        status: _status,
        recurrence: _recurrence,
        attachmentPath: _attachment,
        latitude: _lat,
        longitude: _lon,
        serviceId: _kind == EntryKind.transfer ? null : widget.entry?.serviceId,
        serviceIconPath: _kind == EntryKind.transfer
            ? null
            : widget.entry?.serviceIconPath,
      );
      await c.mutate((data) {
        FinanceEngine.validateEntry(entry, data);
        final original = data.entries
            .where((e) => e.id == entry.id)
            .firstOrNull;
        final category = data.categories
            .where((cat) => cat.id == entry.categoryId)
            .firstOrNull;
        if (category?.archived == true &&
            original?.categoryId != category!.id) {
          throw const FormatException(
            'Категория в архиве. Выберите активную категорию.',
          );
        }
        final rules = [...data.recurring];
        if (widget.entry == null &&
            _recurrence != 'none' &&
            _kind != EntryKind.transfer) {
          final rule = RecurringRule(
            id: c.id(),
            name: entry.payee.isEmpty
                ? (c.category(entry.categoryId)?.name ?? 'Регулярная операция')
                : entry.payee,
            accountId: a.id,
            currency: a.currency,
            categoryId: entry.categoryId,
            kind: _kind,
            amountMinor: value,
            frequency: _recurrence,
            nextDate: _date,
            automatic: true,
            paymentType:
                c
                        .category(entry.categoryId)
                        ?.name
                        .toLowerCase()
                        .contains('подпис') ==
                    true
                ? 'subscription'
                : 'mandatory',
          );
          rules.add(
            rule.copyWith(nextDate: FinanceEngine.nextOccurrence(rule)),
          );
        }
        return data.copyWith(
          entries: [...data.entries.where((e) => e.id != entry.id), entry],
          recurring: rules,
          preferences: c.rememberCategory(data, entry),
        );
      });
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final original = c.data.entries
        .where((e) => e.id == widget.entry?.id)
        .firstOrNull;
    final editingHistory = original != null;
    final active = c.data.accounts
        .where((a) => !a.archived || a.id == _account || a.id == _to)
        .toList();
    final a = c.account(_account ?? '');
    final targetCurrency = _goalDestination
        ? c.goal(_goal)?.currency
        : c.account(_to ?? '')?.currency;
    final categories =
        c.data.categories
            .where(
              (cat) =>
                  cat.kind == _kind &&
                  (!cat.archived ||
                      (editingHistory &&
                          cat.id == original.categoryId &&
                          cat.id == _category)),
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final sub = c.category(_category)?.subcategories ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(editingHistory ? 'Редактирование' : 'Новая операция'),
        actions: [
          if (widget.entry != null)
            IconButton(
              tooltip: 'Дублировать',
              onPressed: () => showEntryEditor(
                context,
                entry: widget.entry!.copyWith(id: c.id(), date: DateTime.now()),
              ),
              icon: const Icon(Icons.copy_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              SegmentedButton<EntryKind>(
                segments: const [
                  ButtonSegment(
                    value: EntryKind.expense,
                    label: Text('Расход'),
                  ),
                  ButtonSegment(value: EntryKind.income, label: Text('Доход')),
                  ButtonSegment(
                    value: EntryKind.transfer,
                    label: Text('Перевод'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _category = null;
                  _subcategory = null;
                  _recurrence = 'none';
                }),
              ),
              const SizedBox(height: 28),
              Text(
                'СУММА · ${a?.currency ?? 'RUB'}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              TextFormField(
                controller: _amount,
                readOnly: _customPad,
                showCursor: true,
                autofocus: false,
                style: Theme.of(context).textTheme.displayLarge,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  hintText: '0',
                  filled: false,
                  suffixIcon: IconButton(
                    tooltip: _customPad
                        ? 'Системная клавиатура'
                        : 'Цифровая панель',
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => _customPad = !_customPad);
                    },
                    icon: Icon(
                      _customPad
                          ? Icons.keyboard_outlined
                          : Icons.dialpad_rounded,
                    ),
                  ),
                ),
                validator: (s) {
                  try {
                    if (FinanceEngine.parseMinor(s ?? '') <= 0) {
                      return 'Укажите сумму больше нуля';
                    }
                    return null;
                  } catch (_) {
                    return 'Введите сумму, не более двух знаков после запятой';
                  }
                },
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                alignment: Alignment.topCenter,
                child: _customPad
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: AmountPad(controller: _amount),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _account,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _kind == EntryKind.transfer ? 'Со счёта' : 'Счёт',
                ),
                items: active
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} · ${a.currency}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _account = v;
                  if (_to == v) {
                    _to = null;
                  }
                }),
              ),
              if (_kind == EntryKind.transfer) ...[
                const SizedBox(height: 18),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('На счёт'),
                      icon: Icon(Icons.wallet_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('В мечту'),
                      icon: Icon(Icons.auto_awesome_outlined),
                    ),
                  ],
                  selected: {_goalDestination},
                  onSelectionChanged: (v) => setState(() {
                    _goalDestination = v.first;
                    _destination.clear();
                  }),
                ),
                const SizedBox(height: 16),
                if (_goalDestination) ...[
                  if (c.data.goals.isEmpty)
                    SurfaceCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const GoalsScreen(),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_rounded),
                          SizedBox(width: 12),
                          Expanded(child: Text('Создать первую мечту')),
                        ],
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('goal-$_goal'),
                    initialValue: c.goal(_goal) != null ? _goal : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Мечта',
                      prefixIcon: Icon(Icons.auto_awesome_outlined),
                    ),
                    items: c.data.goals
                        .map(
                          (g) => DropdownMenuItem(
                            value: g.id,
                            child: Text(
                              '${g.name} · ${g.currency}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _goal = v;
                      _destination.clear();
                    }),
                    validator: (v) => v == null ? 'Выберите мечту' : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Деньги будут переведены со счёта в резерв мечты. Это перевод между вашими средствами, а не расход.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  DropdownButtonFormField<String>(
                    key: ValueKey('account-$_to'),
                    initialValue: _to,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'На счёт'),
                    items: active
                        .where((target) => target.id != _account)
                        .map(
                          (target) => DropdownMenuItem(
                            value: target.id,
                            child: Text(
                              '${target.name} · ${target.currency}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _to = v;
                      _destination.clear();
                    }),
                    validator: (v) =>
                        v == null ? 'Выберите счёт получателя' : null,
                  ),
                if (targetCurrency != null &&
                    targetCurrency != a?.currency) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _destination,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Сумма зачисления · $targetCurrency',
                    ),
                    validator: (s) {
                      try {
                        return FinanceEngine.parseMinor(s ?? '') > 0
                            ? null
                            : 'Введите положительную сумму';
                      } catch (_) {
                        return 'Некорректная сумма';
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Укажите фактическую сумму зачисления в валюте получателя.',
                  ),
                ],
              ] else ...[
                if (widget.entry == null)
                  Builder(
                    builder: (context) {
                      final lastId = _kind == EntryKind.expense
                          ? c.data.preferences.lastExpenseCategoryId
                          : c.data.preferences.lastIncomeCategoryId;
                      final last = c.category(lastId);
                      if (last == null || last.archived || last.kind != _kind) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ActionChip(
                            key: const ValueKey('last-category'),
                            avatar: Icon(categoryIcon(last.icon), size: 18),
                            label: Text('Последняя: ${last.name}'),
                            onPressed: () => setState(() {
                              _category = last.id;
                              _subcategory = null;
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                const SectionTitle('Категория'),
                if (categories.isEmpty)
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const CategoriesScreen(),
                      ),
                    ),
                    child: const Text('Создать категорию'),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories
                      .map(
                        (cat) => ChoiceChip(
                          label: Text(cat.name),
                          avatar: Icon(
                            categoryIcon(cat.icon),
                            size: 17,
                            color: Color(cat.color),
                          ),
                          selected: _category == cat.id,
                          onSelected: (_) => setState(() {
                            _category = cat.id;
                            _subcategory = null;
                          }),
                        ),
                      )
                      .toList(),
                ),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: DropdownButtonFormField<String>(
                      initialValue: sub.contains(_subcategory)
                          ? _subcategory
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Подкатегория',
                      ),
                      items: sub
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _subcategory = v),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _payee,
                decoration: const InputDecoration(
                  labelText: 'Получатель / магазин',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 12),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${displayDate(_date)} · ${DateFormat('HH:mm').format(_date)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2200, 12, 31),
                        );
                        if (date == null || !context.mounted) {
                          return;
                        }
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_date),
                        );
                        if (mounted) {
                          setState(
                            () => _date = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time?.hour ?? _date.hour,
                              time?.minute ?? _date.minute,
                            ),
                          );
                        }
                      },
                      child: const Text('Изменить'),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _advanced = !_advanced),
                icon: Icon(_advanced ? Icons.expand_less : Icons.expand_more),
                label: const Text('Дополнительные поля'),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                alignment: Alignment.topCenter,
                child: _advanced
                    ? Column(
                        children: [
                          TextFormField(
                            controller: _note,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Комментарий',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _tags,
                            decoration: const InputDecoration(
                              labelText: 'Теги через запятую',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Статус',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'posted',
                                child: Text('Проведена'),
                              ),
                              DropdownMenuItem(
                                value: 'pending',
                                child: Text('Ожидает'),
                              ),
                              DropdownMenuItem(
                                value: 'cancelled',
                                child: Text('Отменена'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _status = v!),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue:
                                c.data.members.any((m) => m.id == _member)
                                ? _member
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Участник',
                            ),
                            items: c.data.members
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m.id,
                                    child: Text(m.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _member = v!),
                          ),
                          const SizedBox(height: 12),
                          if (_kind != EntryKind.transfer &&
                              widget.entry == null)
                            DropdownButtonFormField<String>(
                              initialValue: _recurrence,
                              decoration: const InputDecoration(
                                labelText: 'Автоматически повторять',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'none',
                                  child: Text('Не повторять'),
                                ),
                                DropdownMenuItem(
                                  value: 'daily',
                                  child: Text('Ежедневно'),
                                ),
                                DropdownMenuItem(
                                  value: 'weekly',
                                  child: Text('Еженедельно'),
                                ),
                                DropdownMenuItem(
                                  value: 'monthly',
                                  child: Text('Ежемесячно'),
                                ),
                                DropdownMenuItem(
                                  value: 'yearly',
                                  child: Text('Ежегодно'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _recurrence = v!),
                            ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _receipt,
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: Text(
                                  _attachment == null
                                      ? 'Добавить чек'
                                      : 'Заменить чек',
                                ),
                              ),
                              if (_attachment != null)
                                IconButton(
                                  tooltip: 'Удалить чек',
                                  onPressed: () =>
                                      setState(() => _attachment = null),
                                  icon: const Icon(Icons.close),
                                ),
                              OutlinedButton.icon(
                                onPressed: _location,
                                icon: const Icon(Icons.location_on_outlined),
                                label: Text(
                                  _lat == null
                                      ? 'Геолокация'
                                      : 'Место добавлено',
                                ),
                              ),
                              if (_lat != null)
                                IconButton(
                                  tooltip: 'Удалить геолокацию',
                                  onPressed: () => setState(() {
                                    _lat = null;
                                    _lon = null;
                                  }),
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                          ),
                          if (_attachment != null &&
                              File(_attachment!).existsSync())
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(
                                  File(_attachment!),
                                  height: 140,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          if (_lat != null)
                            Text(
                              '${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Сохранить операцию'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
