import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/finance_engine.dart';
import '../domain/models.dart';
import 'demo_data.dart';

/// The persistence boundary. Every ledger replacement is validated and committed
/// atomically; account balances remain derived from posted ledger entries.
class FinanceRepository {
  FinanceRepository._(this._db, this._factory, this._path, this._clock);
  final Database _db;
  final DatabaseFactory _factory;
  final String _path;
  final DateTime Function() _clock;
  static const schemaVersion = 1;
  static const maxBackupBytes = 50 * 1024 * 1024;

  static Future<FinanceRepository> open({
    DatabaseFactory? factory,
    String? path,
    DateTime Function()? clock,
  }) async {
    final selectedFactory = factory ?? databaseFactory;
    final dbPath =
        path ??
        p.join((await getApplicationSupportDirectory()).path, 'finora.db');
    final db = await selectedFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, _) async {
          for (final sql in _schema) {
            await db.execute(sql);
          }
        },
      ),
    );
    final repository = FinanceRepository._(
      db,
      selectedFactory,
      dbPath,
      clock ?? DateTime.now,
    );
    if ((await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['initialized'],
    )).isEmpty) {
      await repository.save(createDemoData(repository._clock()));
    }
    return repository;
  }

  Future<FinanceData> load() => _read(_db);

  Future<void> save(FinanceData data) async {
    validateData(data);
    await _db.transaction((txn) => _write(txn, data));
  }

  Future<void> close() => _db.close();

  /// Remove seeded records only. Personal records created while exploring the
  /// demo survive; referenced sample accounts remain with zero opening balance.
  /// The initialized flag prevents reseeding after reopening.
  Future<void> clearDemo() async {
    final old = await load();
    if (!old.demo) {
      throw const FormatException('Демонстрационные данные уже очищены');
    }
    final seed = createDemoData(_clock());
    final entryIds = seed.entries.map((e) => e.id).toSet();
    final accountIds = seed.accounts.map((a) => a.id).toSet();
    final ruleIds = seed.recurring.map((r) => r.id).toSet();
    final goalIds = seed.goals.map((g) => g.id).toSet();
    final budgetIds = seed.budgets.map((b) => b.id).toSet();
    final entries = old.entries.where((e) => !entryIds.contains(e.id)).toList();
    final rules = old.recurring.where((r) => !ruleIds.contains(r.id)).toList();
    final needed = <String>{
      ...entries.map((e) => e.accountId),
      ...entries.map((e) => e.toAccountId).whereType<String>(),
      ...rules.map((r) => r.accountId),
    };
    await save(
      old.copyWith(
        accounts: [
          for (final a in old.accounts)
            if (!accountIds.contains(a.id))
              a
            else if (needed.contains(a.id))
              a.copyWith(openingMinor: 0),
        ],
        entries: entries,
        recurring: rules,
        budgets: old.budgets.where((b) => !budgetIds.contains(b.id)).toList(),
        goals: old.goals.where((g) => !goalIds.contains(g.id)).toList(),
        demo: false,
      ),
    );
  }

  Future<String> exportJson() async {
    final data = await load();
    final attachments = <String, String>{};
    var totalBytes = 0;
    for (final entry in data.entries) {
      if (entry.attachmentPath == null) {
        continue;
      }
      final file = File(entry.attachmentPath!);
      if (!await file.exists()) {
        throw FormatException(
          'Чек для операции ${entry.id} недоступен. Удалите ссылку на чек перед экспортом.',
        );
      }
      final length = await file.length();
      totalBytes += length;
      if (length > 10 * 1024 * 1024 || totalBytes > 30 * 1024 * 1024) {
        throw const FormatException(
          'Чеки превышают лимит резервной копии (10 МБ на файл, 30 МБ всего)',
        );
      }
      attachments[entry.id] = base64Encode(await file.readAsBytes());
    }
    // Device-local paths are never part of a portable backup. The media map is
    // keyed by entry ID; imported archives cannot choose filesystem filenames.
    final portable = data.copyWith(
      entries: [
        for (final entry in data.entries) entry.copyWith(attachmentPath: null),
      ],
    );
    final result = const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': schemaVersion,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'data': portable.toJson(),
      'attachments': attachments,
    });
    if (utf8.encode(result).length > maxBackupBytes) {
      throw const FormatException('Резервная копия превышает 50 МБ');
    }
    return result;
  }

  Future<void> importJson(String content) async {
    var data = decodeBackup(content);
    final envelope = jsonDecode(content) as Map<String, dynamic>;
    final incoming = envelope['attachments'];
    if (incoming != null && incoming is! Map<String, dynamic>) {
      throw const FormatException('Повреждённый раздел чеков');
    }
    final media = incoming as Map<String, dynamic>? ?? {};
    final entryIds = data.entries.map((e) => e.id).toSet();
    final decoded = <String, List<int>>{};
    var totalBytes = 0;
    for (final item in media.entries) {
      if (!entryIds.contains(item.key) || item.value is! String) {
        throw const FormatException('Чек относится к неизвестной операции');
      }
      final bytes = base64Decode(item.value as String);
      totalBytes += bytes.length;
      if (bytes.isEmpty ||
          bytes.length > 10 * 1024 * 1024 ||
          totalBytes > 30 * 1024 * 1024) {
        throw const FormatException('Некорректный размер чека');
      }
      decoded[item.key] = bytes;
    }
    Directory? staged;
    try {
      if (decoded.isNotEmpty) {
        final root = Directory(p.join(p.dirname(_path), 'receipts'));
        await root.create(recursive: true);
        staged = await root.createTemp('import-');
        final paths = <String, String>{};
        var index = 0;
        for (final item in decoded.entries) {
          final file = File(p.join(staged.path, 'receipt-${index++}.bin'));
          await file.writeAsBytes(item.value, flush: true);
          paths[item.key] = file.path;
        }
        data = data.copyWith(
          entries: [
            for (final entry in data.entries)
              entry.copyWith(attachmentPath: paths[entry.id]),
          ],
        );
      }
      await save(data);
    } on Object {
      if (staged != null && await staged.exists()) {
        await staged.delete(recursive: true);
      }
      rethrow;
    }
  }

  static FinanceData decodeBackup(String content) {
    if (utf8.encode(content).length > maxBackupBytes) {
      throw const FormatException('Резервная копия превышает 50 МБ');
    }
    try {
      final envelope = jsonDecode(content);
      if (envelope is! Map<String, dynamic> ||
          envelope['schemaVersion'] != schemaVersion ||
          envelope['data'] is! Map<String, dynamic>) {
        throw const FormatException('Неподдерживаемый формат резервной копии');
      }
      final map = envelope['data'] as Map<String, dynamic>;
      for (final key in [
        'accounts',
        'categories',
        'entries',
        'budgets',
        'goals',
        'recurring',
        'members',
      ]) {
        if (map[key] is! List) {
          throw FormatException('Отсутствует раздел $key');
        }
      }
      if (map['preferences'] is! Map || map['demo'] is! bool) {
        throw const FormatException('Отсутствуют настройки резервной копии');
      }
      final raw = FinanceData.fromJson(map);
      // Ignore every supplied path, including absolute paths, traversal paths,
      // symlinks and URLs. Only separately decoded embedded files are restored.
      final result = raw.copyWith(
        entries: [
          for (final entry in raw.entries) entry.copyWith(attachmentPath: null),
        ],
      );
      validateData(result);
      return result;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Повреждённые данные резервной копии');
    }
  }

  Future<String> exportCsv() async {
    final data = await load();
    final accounts = {for (final a in data.accounts) a.id: a.name};
    final categories = {for (final c in data.categories) c.id: c.name};
    String cell(Object? value) {
      var text = value?.toString() ?? '';
      // Spreadsheet programs must treat arbitrary payee/note/tag values as text.
      if (RegExp(r'^[\s]*[=+@\-]').hasMatch(text)) {
        text = "'$text";
      }
      return '"${text.replaceAll('"', '""')}"';
    }

    final rows = <List<Object?>>[
      [
        'id',
        'type',
        'amount_minor',
        'currency',
        'account',
        'destination_account',
        'destination_minor',
        'category',
        'subcategory',
        'date',
        'payee',
        'note',
        'tags',
        'member',
        'status',
      ],
      for (final e in data.entries)
        [
          e.id,
          e.kind.name,
          e.amountMinor,
          e.currency,
          accounts[e.accountId],
          accounts[e.toAccountId],
          e.destinationMinor,
          categories[e.categoryId],
          e.subcategory,
          e.date.toIso8601String(),
          e.payee,
          e.note,
          e.tags.join(' | '),
          e.memberId,
          e.status,
        ],
    ];
    return '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';
  }

  /// A read transaction captures one consistent ledger version. A separate
  /// SQLite database is fully committed and closed before publication, so the
  /// snapshot includes committed WAL contents without copying live WAL files.
  /// This supports older Android SQLite releases that lack VACUUM INTO.
  Future<String> backupDatabase(String destinationPath) async {
    if (p.equals(p.absolute(_path), p.absolute(destinationPath))) {
      throw const FormatException('Выберите отдельный файл резервной копии');
    }
    final destination = File(destinationPath);
    if (await destination.exists()) {
      throw const FormatException('Файл уже существует');
    }
    final snapshot = await _db.transaction((txn) => _read(txn));
    validateData(snapshot);
    await destination.parent.create(recursive: true);
    final staging = await destination.parent.createTemp('finora-backup-');
    Database? backup;
    var published = false;
    try {
      final stagedPath = p.join(staging.path, 'snapshot.db');
      backup = await _factory.openDatabase(
        stagedPath,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          singleInstance: false,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, _) async {
            for (final sql in _schema) {
              await db.execute(sql);
            }
          },
        ),
      );
      await backup.transaction((txn) => _write(txn, snapshot));
      await backup.close();
      backup = null;
      if (await File(stagedPath).length() > maxBackupBytes) {
        throw const FormatException('Резервная копия превышает 50 МБ');
      }
      // Exclusive creation keeps another export/user file from being replaced.
      await destination.create(exclusive: true);
      published = true;
      await File(stagedPath).copy(destinationPath);
      return destinationPath;
    } on Object {
      if (published && await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    } finally {
      await backup?.close();
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  /// Restores validated logical data from an isolated read-only database. The
  /// live database remains open and is modified in one transaction only.
  Future<void> restoreDatabase(String sourcePath) async {
    if (!await File(sourcePath).exists()) {
      throw const FormatException('Файл не найден');
    }
    if (p.equals(p.absolute(_path), p.absolute(sourcePath))) {
      throw const FormatException('Нельзя восстановить открытый файл базы');
    }
    Database? backup;
    late FinanceData data;
    try {
      backup = await _factory.openDatabase(
        sourcePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version = await backup.getVersion();
      if (version != schemaVersion) {
        throw const FormatException('Неподдерживаемая версия базы');
      }
      final check = await backup.rawQuery('PRAGMA integrity_check');
      if (check.length != 1 || check.first.values.first != 'ok') {
        throw const FormatException('Повреждённая база данных');
      }
      data = await _read(backup);
      // A foreign SQLite file is untrusted input too. Retain receipt references
      // only when they resolve inside this installation's private media root.
      final root = Directory(p.join(p.dirname(_path), 'receipts'));
      final safe = <FinanceEntry>[];
      final resolvedRoot = await root.exists()
          ? await root.resolveSymbolicLinks()
          : null;
      for (final entry in data.entries) {
        String? retained;
        final path = entry.attachmentPath;
        if (path != null && resolvedRoot != null) {
          try {
            final file = File(path);
            final resolved = await file.resolveSymbolicLinks();
            if (p.isWithin(resolvedRoot, resolved) && await file.exists()) {
              retained = resolved;
            }
          } on FileSystemException {
            /* Missing external media is not restored. */
          }
        }
        safe.add(entry.copyWith(attachmentPath: retained));
      }
      data = data.copyWith(entries: safe);
      validateData(data);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Не удалось прочитать резервную копию базы');
    } finally {
      await backup?.close();
    }
    await save(data);
  }

  static void validateData(FinanceData data) {
    void ids(Iterable<String> values) {
      final seen = <String>{};
      for (final value in values) {
        if (value.trim().isEmpty || value.length > 200 || !seen.add(value)) {
          throw const FormatException('Пустой или повторяющийся идентификатор');
        }
      }
    }

    void currency(String value) {
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
        throw const FormatException('Некорректная валюта');
      }
    }

    void amount(int value, {bool signed = false, bool positive = false}) {
      if (value.abs() > FinanceEngine.maxMinor ||
          (!signed && value < 0) ||
          (positive && value <= 0)) {
        throw const FormatException('Недопустимая денежная сумма');
      }
    }

    void date(DateTime value) {
      if (value.year < 1900 || value.year > 2200) {
        throw const FormatException('Дата должна быть между 1900 и 2200 годом');
      }
    }

    void name(String value) {
      if (value.trim().isEmpty || value.length > 500) {
        throw const FormatException('Укажите название до 500 символов');
      }
    }

    ids(data.accounts.map((a) => a.id));
    ids(data.categories.map((c) => c.id));
    ids(data.entries.map((e) => e.id));
    ids(data.budgets.map((b) => b.id));
    ids(data.goals.map((g) => g.id));
    ids(data.recurring.map((r) => r.id));
    ids(data.members.map((m) => m.id));
    final categoryMap = {for (final c in data.categories) c.id: c};
    final accountMap = {for (final a in data.accounts) a.id: a};
    final memberIds = data.members.map((m) => m.id).toSet();
    if (memberIds.isEmpty) {
      throw const FormatException(
        'В профиле должен быть хотя бы один участник',
      );
    }
    for (final m in data.members) {
      name(m.name);
    }
    for (final a in data.accounts) {
      name(a.name);
      currency(a.currency);
      amount(a.openingMinor, signed: true);
      amount(a.creditLimitMinor);
      if (a.lastFour.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(a.lastFour)) {
        throw const FormatException('Укажите последние четыре цифры карты');
      }
      amount(FinanceEngine.balance(a, data.entries), signed: true);
    }
    for (final c in data.categories) {
      name(c.name);
      ids(c.subcategories);
      if (c.kind == EntryKind.transfer) {
        throw const FormatException('Категория перевода недопустима');
      }
    }
    for (final e in data.entries) {
      FinanceEngine.validateEntry(e, data);
      if (!memberIds.contains(e.memberId)) {
        throw const FormatException('Участник операции не найден');
      }
      date(e.date);
      if (e.note.length > 10000 ||
          e.payee.length > 500 ||
          e.tags.length > 100 ||
          e.tags.any((t) => t.trim().isEmpty || t.length > 200)) {
        throw const FormatException(
          'Слишком длинный комментарий, получатель или тег',
        );
      }
    }
    for (final code in data.accounts.map((a) => a.currency).toSet()) {
      FinanceEngine.totalBalance(data.accounts, data.entries, code);
      FinanceEngine.totals(
        data.entries,
        DateTime.utc(1899),
        DateTime.utc(2202),
        code,
      );
    }
    for (final b in data.budgets) {
      name(b.name);
      currency(b.currency);
      amount(b.limitMinor, positive: true);
      if (b.categoryId != null &&
          categoryMap[b.categoryId]?.kind != EntryKind.expense) {
        throw const FormatException('Категория бюджета не найдена');
      }
    }
    for (final g in data.goals) {
      name(g.name);
      currency(g.currency);
      amount(g.targetMinor, positive: true);
      amount(g.savedMinor);
      if (g.deadline != null) {
        date(g.deadline!);
      }
    }
    for (final r in data.recurring) {
      name(r.name);
      currency(r.currency);
      amount(r.amountMinor, positive: true);
      date(r.nextDate);
      if (r.kind == EntryKind.transfer ||
          accountMap[r.accountId]?.currency != r.currency ||
          categoryMap[r.categoryId]?.kind != r.kind) {
        throw const FormatException(
          'Некорректный счёт или категория регулярной операции',
        );
      }
      if (r.anchorDay < 1 || r.anchorDay > 31) {
        throw const FormatException('Некорректный день регулярного платежа');
      }
      FinanceEngine.nextOccurrence(r);
    }
    final prefs = data.preferences;
    currency(prefs.baseCurrency);
    if (!['light', 'dark', 'system'].contains(prefs.theme) ||
        !['lime', 'gold', 'lavender', 'blue'].contains(prefs.accent) ||
        !['space_comma', 'comma_dot'].contains(prefs.numberFormat) ||
        ![
          'dd.MM.yyyy',
          'yyyy-MM-dd',
          'dd/MM/yyyy',
        ].contains(prefs.dateFormat) ||
        prefs.weekStart < 1 ||
        prefs.weekStart > 7 ||
        prefs.monthStart < 1 ||
        prefs.monthStart > 28 ||
        prefs.lockMinutes < 0 ||
        prefs.lockMinutes > 1440) {
      throw const FormatException('Некорректные настройки приложения');
    }
  }

  static Future<FinanceData> _read(DatabaseExecutor db) async {
    Map<String, dynamic> decoded(
      Map<String, Object?> row,
      Iterable<String> bools,
    ) {
      final result = Map<String, dynamic>.from(row);
      for (final field in bools) {
        result[field] = result[field] == 1;
      }
      return result;
    }

    final settings = {
      for (final row in await db.query('settings'))
        row['key'] as String: row['value'] as String,
    };
    final subcategories = await db.query('subcategories', orderBy: 'position');
    final tags = await db.rawQuery(
      'SELECT et.entryId, t.name FROM entry_tags et JOIN tags t ON t.id = et.tagId ORDER BY et.position',
    );
    final attachmentPaths = {
      for (final a in await db.query('attachments')) a['entryId']: a['path'],
    };
    final accounts = (await db.query('accounts'))
        .map((r) => Account.fromJson(decoded(r, ['excluded', 'archived'])))
        .toList();
    final categories = (await db.query('categories', orderBy: '"order"'))
        .map(
          (r) => Category.fromJson({
            ...r,
            'subcategories': subcategories
                .where((s) => s['categoryId'] == r['id'])
                .map((s) => s['name'])
                .toList(),
          }),
        )
        .toList();
    return FinanceData(
      accounts: accounts,
      categories: categories,
      entries: (await db.query('entries', orderBy: 'date DESC, id'))
          .map(
            (r) => FinanceEntry.fromJson({
              ...r,
              'tags': tags
                  .where((t) => t['entryId'] == r['id'])
                  .map((t) => t['name'])
                  .toList(),
              'attachmentPath': attachmentPaths[r['id']],
            }),
          )
          .toList(),
      budgets: (await db.query(
        'budgets',
      )).map((r) => Budget.fromJson(Map<String, dynamic>.from(r))).toList(),
      goals: (await db.query(
        'goals',
      )).map((r) => Goal.fromJson(Map<String, dynamic>.from(r))).toList(),
      recurring: (await db.query('recurring'))
          .map(
            (r) => RecurringRule.fromJson(decoded(r, ['automatic', 'enabled'])),
          )
          .toList(),
      members: (await db.query(
        'members',
      )).map((r) => Member.fromJson(Map<String, dynamic>.from(r))).toList(),
      preferences: AppPreferences.fromJson(
        jsonDecode(settings['preferences'] ?? '{}') as Map<String, dynamic>,
      ),
      demo: settings['demo'] == 'true',
    );
  }

  static Future<void> _write(DatabaseExecutor db, FinanceData data) async {
    for (final table in [
      'entry_tags',
      'attachments',
      'entries',
      'recurring',
      'budgets',
      'subcategories',
      'categories',
      'goals',
      'accounts',
      'members',
      'tags',
      'currencies',
      'settings',
    ]) {
      await db.delete(table);
    }
    final currencies = <String>{
      'RUB',
      'USD',
      'EUR',
      'CNY',
      'TRY',
      'GEL',
      data.preferences.baseCurrency,
      ...data.accounts.map((a) => a.currency),
      ...data.budgets.map((b) => b.currency),
      ...data.goals.map((g) => g.currency),
    };
    for (final c in currencies) {
      await db.insert('currencies', {'code': c, 'minorDigits': 2});
    }
    Map<String, Object?> scalar(Map<String, Object?> input) => input.map(
      (key, value) => MapEntry(key, value is bool ? (value ? 1 : 0) : value),
    );
    for (final a in data.accounts) {
      await db.insert('accounts', scalar(a.toJson()));
    }
    for (final m in data.members) {
      await db.insert('members', m.toJson());
    }
    for (final c in data.categories) {
      final row = c.toJson()..remove('subcategories');
      await db.insert('categories', row);
      for (var i = 0; i < c.subcategories.length; i++) {
        await db.insert('subcategories', {
          'categoryId': c.id,
          'name': c.subcategories[i],
          'position': i,
        });
      }
    }
    final tagIds = <String, int>{};
    for (final e in data.entries) {
      final row = e.toJson()
        ..remove('tags')
        ..remove('attachmentPath');
      await db.insert('entries', row);
      var position = 0;
      for (final tag in e.tags.toSet()) {
        final id = tagIds[tag] ?? await db.insert('tags', {'name': tag});
        tagIds[tag] = id;
        await db.insert('entry_tags', {
          'entryId': e.id,
          'tagId': id,
          'position': position++,
        });
      }
      if (e.attachmentPath != null) {
        await db.insert('attachments', {
          'entryId': e.id,
          'path': e.attachmentPath,
        });
      }
    }
    for (final b in data.budgets) {
      await db.insert('budgets', b.toJson());
    }
    for (final g in data.goals) {
      await db.insert('goals', g.toJson());
    }
    for (final r in data.recurring) {
      await db.insert('recurring', scalar(r.toJson()));
    }
    await db.insert('settings', {'key': 'initialized', 'value': 'true'});
    await db.insert('settings', {'key': 'demo', 'value': data.demo.toString()});
    await db.insert('settings', {
      'key': 'preferences',
      'value': jsonEncode(data.preferences.toJson()),
    });
  }

  static const _schema = [
    'CREATE TABLE currencies(code TEXT PRIMARY KEY, minorDigits INTEGER NOT NULL)',
    'CREATE TABLE members(id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    'CREATE TABLE accounts(id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), bank TEXT NOT NULL, lastFour TEXT NOT NULL, openingMinor INTEGER NOT NULL, creditLimitMinor INTEGER NOT NULL, excluded INTEGER NOT NULL, archived INTEGER NOT NULL, color INTEGER NOT NULL, icon INTEGER NOT NULL)',
    'CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, color INTEGER NOT NULL, background INTEGER NOT NULL, icon INTEGER NOT NULL, "order" INTEGER NOT NULL)',
    'CREATE TABLE subcategories(categoryId TEXT NOT NULL REFERENCES categories(id), name TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY(categoryId,name))',
    'CREATE TABLE entries(id TEXT PRIMARY KEY, kind TEXT NOT NULL, amountMinor INTEGER NOT NULL CHECK(amountMinor > 0), currency TEXT NOT NULL REFERENCES currencies(code), accountId TEXT NOT NULL REFERENCES accounts(id), toAccountId TEXT REFERENCES accounts(id), categoryId TEXT REFERENCES categories(id), subcategory TEXT, destinationMinor INTEGER, date TEXT NOT NULL, note TEXT NOT NULL, payee TEXT NOT NULL, status TEXT NOT NULL, recurrence TEXT NOT NULL, memberId TEXT NOT NULL REFERENCES members(id), latitude REAL, longitude REAL)',
    'CREATE INDEX entries_date ON entries(date)',
    'CREATE INDEX entries_account ON entries(accountId)',
    'CREATE INDEX entries_category ON entries(categoryId)',
    'CREATE TABLE tags(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)',
    'CREATE TABLE entry_tags(entryId TEXT NOT NULL REFERENCES entries(id), tagId INTEGER NOT NULL REFERENCES tags(id), position INTEGER NOT NULL, PRIMARY KEY(entryId,tagId))',
    'CREATE TABLE attachments(entryId TEXT PRIMARY KEY REFERENCES entries(id), path TEXT NOT NULL)',
    'CREATE TABLE budgets(id TEXT PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), categoryId TEXT REFERENCES categories(id), limitMinor INTEGER NOT NULL CHECK(limitMinor > 0))',
    'CREATE TABLE goals(id TEXT PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), targetMinor INTEGER NOT NULL CHECK(targetMinor > 0), savedMinor INTEGER NOT NULL CHECK(savedMinor >= 0), color INTEGER NOT NULL, icon INTEGER NOT NULL, deadline TEXT)',
    'CREATE TABLE recurring(id TEXT PRIMARY KEY, name TEXT NOT NULL, accountId TEXT NOT NULL REFERENCES accounts(id), currency TEXT NOT NULL REFERENCES currencies(code), categoryId TEXT REFERENCES categories(id), kind TEXT NOT NULL, amountMinor INTEGER NOT NULL CHECK(amountMinor > 0), interval INTEGER NOT NULL, anchorDay INTEGER NOT NULL, frequency TEXT NOT NULL, nextDate TEXT NOT NULL, automatic INTEGER NOT NULL, enabled INTEGER NOT NULL)',
    'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  ];
}
