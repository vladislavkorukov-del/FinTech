import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/foreign_csv.dart';
import '../../domain/models.dart';
import '../controller.dart';
import '../haptics.dart';
import '../widgets/common.dart';

/// Operations from another app's or a bank's CSV (Finora 1.35): the columns
/// are recognised, the person checks them, chooses where the accounts go,
/// and the operations are added to the base. Nothing is replaced.
class ForeignImportScreen extends StatefulWidget {
  const ForeignImportScreen({
    super.key,
    required this.text,
    this.fileName = '',
  });

  /// The file, already decoded ([ForeignCsv.decode]).
  final String text;
  final String fileName;

  @override
  State<ForeignImportScreen> createState() => _ForeignImportScreenState();
}

class _ForeignImportScreenState extends State<ForeignImportScreen> {
  late final ForeignTable table = ForeignCsv.read(widget.text);
  late final List<CsvRole> roles = [...table.roles];
  var unsignedAs = EntryKind.expense;
  var createCategories = true;
  var skipDuplicates = true;
  final accountMap = <String, String?>{};
  String? defaultAccountId;
  late ForeignParse parse;
  List<String> _accountNames = const [];
  bool _mapped = false, _busy = false, _showColumns = false, _counted = false;

  @override
  void initState() {
    super.initState();
    _showColumns = !roles.contains(CsvRole.date);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_counted) return;
    _counted = true;
    _accountNames = [
      for (final a in FinanceScope.of(context).data.accounts) a.name,
    ];
    _recount();
  }

  void _recount() {
    parse = ForeignCsv.rows(
      table,
      roles,
      unsignedAs: unsignedAs,
      accountNames: _accountNames,
    );
  }

  /// File account names to existing accounts with the same name.
  void _mapAccounts(FinanceData data) {
    String low(String s) => s.trim().toLowerCase().replaceAll('ё', 'е');
    for (final name in parse.accounts) {
      if (name.isEmpty || accountMap.containsKey(name)) continue;
      accountMap[name] = data.accounts
          .where((a) => !a.archived && low(a.name) == low(name))
          .firstOrNull
          ?.id;
    }
    if (!_mapped) {
      defaultAccountId = data.accounts
          .where((a) => !a.archived)
          .firstOrNull
          ?.id;
      _mapped = true;
    }
  }

  static int _iconFor(String name) {
    for (final word in name.toLowerCase().split(RegExp(r'[\s,/.-]+'))) {
      if (word.length < 3) continue;
      final found = searchFinanceIcons(word);
      if (found.isNotEmpty) return found.first.index;
    }
    return 26;
  }

  Future<void> _import() async {
    final c = FinanceScope.of(context);
    setState(() => _busy = true);
    late ForeignReport report;
    try {
      await c.mutate((d) {
        final (next, r) = ForeignCsv.apply(
          d,
          parse.rows,
          ForeignOptions(
            unsignedAs: unsignedAs,
            accountMap: accountMap,
            defaultAccountId: defaultAccountId,
            createCategories: createCategories,
            skipDuplicates: skipDuplicates,
          ),
          newId: c.id,
          iconFor: _iconFor,
          colors: categoryColors,
        );
        report = r;
        return next;
      });
      await Haptics.success();
      if (!mounted) return;
      final parts = [
        'Добавлено операций: ${report.added}',
        if (report.duplicates > 0) 'повторов пропущено: ${report.duplicates}',
        if (report.newAccounts.isNotEmpty)
          'новых счетов: ${report.newAccounts.length}',
        if (report.newCategories.isNotEmpty)
          'новых категорий: ${report.newCategories.length}',
      ];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(parts.join(', '))));
      Navigator.of(context).pop(report.added);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    _mapAccounts(c.data);
    final theme = Theme.of(context);
    final accounts = c.data.accounts.where((a) => !a.archived).toList();
    final names = parse.accounts.where((n) => n.isNotEmpty).toList();
    final hasEmpty = parse.rows.any(
      (r) =>
          r.account.isEmpty ||
          (r.kind == EntryKind.transfer && r.toAccount.isEmpty),
    );
    final total = parse.rows.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт из CSV')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            SurfaceCard(
              key: const ValueKey('foreign-summary'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(table.format, style: theme.textTheme.titleLarge),
                  if (widget.fileName.isNotEmpty)
                    Text(
                      widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Расходов: ${parse.count(EntryKind.expense)} · '
                    'доходов: ${parse.count(EntryKind.income)} · '
                    'переводов: ${parse.count(EntryKind.transfer)}',
                    key: const ValueKey('foreign-counts'),
                  ),
                  if (parse.merged > 0)
                    Text(
                      'Переводов между своими счетами найдено: '
                      '${parse.merged} — они не попадут в расходы и доходы',
                      key: const ValueKey('foreign-merged'),
                    ),
                  for (final s in parse.skipped.entries)
                    Text(
                      'Пропущено — ${s.key.toLowerCase()}: ${s.value}',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const ValueKey('foreign-columns'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Столбцы'),
              subtitle: Text(
                roles.where((r) => r != CsvRole.skip).isEmpty
                    ? 'Укажите, где дата и сумма'
                    : [
                        for (var i = 0; i < roles.length; i++)
                          if (roles[i] != CsvRole.skip)
                            '${table.headers[i]} → ${csvRoleNames[roles[i]]}',
                      ].join(', '),
                maxLines: _showColumns ? 20 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                _showColumns
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              onTap: () => setState(() => _showColumns = !_showColumns),
            ),
            if (_showColumns)
              for (var i = 0; i < table.headers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              table.headers[i].isEmpty
                                  ? 'Столбец ${i + 1}'
                                  : table.headers[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              table.rows.isEmpty ? '' : table.rows.first[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<CsvRole>(
                        key: ValueKey('foreign-role-$i'),
                        value: roles[i],
                        onChanged: (v) => setState(() {
                          if (v == null) return;
                          // One column per role.
                          if (v != CsvRole.skip) {
                            for (var j = 0; j < roles.length; j++) {
                              if (roles[j] == v) roles[j] = CsvRole.skip;
                            }
                          }
                          roles[i] = v;
                          _recount();
                        }),
                        items: [
                          for (final r in CsvRole.values)
                            DropdownMenuItem(
                              value: r,
                              child: Text(csvRoleNames[r]!),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            if (!parse.signed) ...[
              const SizedBox(height: 8),
              const Text('Суммы без знака и без типа — это:'),
              const SizedBox(height: 6),
              SegmentedButton<EntryKind>(
                key: const ValueKey('foreign-unsigned'),
                segments: const [
                  ButtonSegment(
                    value: EntryKind.expense,
                    label: Text('Расходы'),
                  ),
                  ButtonSegment(value: EntryKind.income, label: Text('Доходы')),
                ],
                selected: {unsignedAs},
                onSelectionChanged: (v) => setState(() {
                  unsignedAs = v.first;
                  _recount();
                }),
              ),
            ],
            if (names.isNotEmpty || hasEmpty) ...[
              const SizedBox(height: 16),
              Text('Счета', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Счёт с таким же названием выбирается сам; остальные будут '
                'созданы с нулевым начальным остатком.',
                style: theme.textTheme.bodySmall,
              ),
              for (final name in names.take(40))
                _accountRow(
                  name,
                  accountMap[name],
                  accounts,
                  'Создать «$name»',
                  (v) => setState(() => accountMap[name] = v),
                ),
              if (hasEmpty)
                _accountRow(
                  'Операции без счёта',
                  defaultAccountId,
                  accounts,
                  'Создать «Импорт»',
                  (v) => setState(() => defaultAccountId = v),
                ),
            ],
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const ValueKey('foreign-create-categories'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Создавать недостающие категории'),
              subtitle: const Text(
                'Иначе Финора подберёт похожую или «Другое»',
              ),
              value: createCategories,
              onChanged: (v) => setState(() => createCategories = v),
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('foreign-skip-duplicates'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Пропускать повторы'),
              subtitle: const Text(
                'Та же сумма, тип, счёт и день, что уже есть в базе',
              ),
              value: skipDuplicates,
              onChanged: (v) => setState(() => skipDuplicates = v),
            ),
            if (total > 0) ...[
              const SizedBox(height: 12),
              Text(
                total > 50 ? 'Первые 50 из $total' : 'Операции',
                style: theme.textTheme.titleMedium,
              ),
              for (final r in parse.rows.take(50)) _preview(context, r),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const ValueKey('foreign-import'),
            onPressed: total == 0 || _busy ? null : _import,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done_rounded),
            label: Text(
              total == 0 ? 'Нечего добавить' : 'Добавить операции: $total',
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountRow(
    String title,
    String? value,
    List<Account> accounts,
    String create,
    ValueChanged<String?> onChanged,
  ) => Row(
    children: [
      Expanded(
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: accounts.any((a) => a.id == value) ? value : null,
          onChanged: onChanged,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(create, overflow: TextOverflow.ellipsis),
            ),
            for (final a in accounts)
              DropdownMenuItem<String?>(
                value: a.id,
                child: Text(
                  '${a.name} · ${a.currency}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _preview(BuildContext context, ForeignRow r) {
    final scheme = Theme.of(context).colorScheme;
    final base = FinanceScope.of(context).data.preferences.baseCurrency;
    final (icon, color, sign) = switch (r.kind) {
      EntryKind.expense => (Icons.north_east_rounded, scheme.error, '−'),
      EntryKind.income => (Icons.south_west_rounded, Colors.green, '+'),
      EntryKind.transfer => (Icons.swap_horiz_rounded, scheme.primary, ''),
    };
    final title = [
      r.payee,
      r.category,
      r.note,
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '—');
    final where = r.kind == EntryKind.transfer
        ? '${r.account} → ${r.toAccount}'
        : [r.account, r.category].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${DateFormat('dd.MM.yyyy').format(r.date)}'
        '${where.isEmpty ? '' : ' · $where'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '$sign${money(r.amountMinor, r.currency ?? base)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
