import 'dart:convert';

/// The whole Finora base as one CSV file (1.34) — opens in Excel or Google
/// Sheets and comes back into the app unchanged.
///
/// The file is a set of tables one after another:
///
///     Finora CSV,1
///     #accounts
///     id:text,name:text,…,openingMinor:int
///     "a1","Карта",…,"150000"
///     (empty line)
///     #categories
///     …
///
/// Each column says its type (`text`, `int`, `num`, `bool`, `json`); an empty
/// unquoted cell is «nothing», a quoted one is an empty string. Text that a
/// spreadsheet would run as a formula (`=`, `+`, `-`, `@`) is written with a
/// leading apostrophe, which the import removes again. Pictures (receipts,
/// own icons) do not go into CSV — only into the JSON copy.
abstract final class FinoraCsv {
  static const marker = 'Finora CSV';
  static const formatVersion = 1;
  static const tables = [
    'accounts',
    'categories',
    'entries',
    'budgets',
    'goals',
    'recurring',
    'members',
  ];

  // ── Export ─────────────────────────────────────────────────────────────

  /// [data] is `FinanceData.toJson()` (without media paths).
  static String encode(Map<String, Object?> data) {
    final out = StringBuffer('﻿');
    void line(List<String> cells) => out.write('${cells.join(',')}\r\n');
    line(['"$marker"', '"$formatVersion"']);
    for (final name in tables) {
      final rows = [
        for (final row in data[name] as List? ?? const [])
          Map<String, Object?>.from(row as Map),
      ];
      _table(name, rows, line);
    }
    final prefs = Map<String, Object?>.from(
      data['preferences'] as Map? ?? const {},
    );
    _table('preferences', [
      for (final e in prefs.entries)
        {'key': e.key, 'value': jsonEncode(e.value)},
    ], line);
    _table('meta', [
      {'key': 'demo', 'value': jsonEncode(data['demo'] ?? false)},
    ], line);
    return out.toString();
  }

  static void _table(
    String name,
    List<Map<String, Object?>> rows,
    void Function(List<String>) line,
  ) {
    final columns = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (!columns.contains(key)) columns.add(key);
      }
    }
    final types = {for (final c in columns) c: _typeOf(rows.map((r) => r[c]))};
    line(['"#$name"']);
    if (columns.isNotEmpty) {
      line([for (final c in columns) _quote('$c:${types[c]}')]);
      for (final row in rows) {
        line([for (final c in columns) _cell(row[c], types[c]!)]);
      }
    }
    line([]);
  }

  static String _typeOf(Iterable<Object?> values) {
    String? type;
    for (final v in values) {
      if (v == null) continue;
      final t = switch (v) {
        String() => 'text',
        int() => 'int',
        double() => 'num',
        bool() => 'bool',
        _ => 'json',
      };
      if (type == null) {
        type = t;
      } else if (type != t) {
        type = (type == 'int' && t == 'num') || (type == 'num' && t == 'int')
            ? 'num'
            : 'json';
      }
    }
    return type ?? 'text';
  }

  static String _cell(Object? value, String type) {
    if (value == null) return '';
    final text = switch (type) {
      'text' => _guard(value as String),
      'json' => jsonEncode(value),
      _ => value.toString(),
    };
    return _quote(text);
  }

  /// Spreadsheets must show these as text, not run them.
  static String _guard(String text) =>
      RegExp(r"^(\s*[=+@\-]|')").hasMatch(text) ? "'$text" : text;

  static String _quote(String text) => '"${text.replaceAll('"', '""')}"';

  // ── Import ─────────────────────────────────────────────────────────────

  /// A JSON backup envelope (`schemaVersion`, `data`) built from [content]
  /// for the usual validated import. Throws [FormatException] for anything
  /// that is not a Finora base table.
  static Map<String, Object?> decode(String content, {required int schema}) {
    final rows = _parse(
      content.startsWith('﻿') ? content.substring(1) : content,
    );
    if (rows.isEmpty || rows.first.isEmpty || rows.first.first.text != marker) {
      throw const FormatException(
        'Это не таблица базы Finora. Нужен файл «Вся база (CSV)».',
      );
    }
    if (rows.first.length > 1 &&
        (int.tryParse(rows.first[1].text) ?? 0) > formatVersion) {
      throw const FormatException('Файл из более новой версии Finora');
    }
    final sections = <String, List<Map<String, Object?>>>{};
    String? section;
    List<(String, String)>? columns;
    for (final row in rows.skip(1)) {
      if (row.isEmpty ||
          (row.length == 1 && row.first.text.isEmpty && !row.first.quoted)) {
        continue;
      }
      final first = row.first.text;
      if (row.length == 1 && first.startsWith('#')) {
        section = first.substring(1);
        sections.putIfAbsent(section, () => []);
        columns = null;
        continue;
      }
      if (section == null) {
        throw const FormatException('Повреждённая таблица: нет раздела');
      }
      if (columns == null) {
        columns = [
          for (final cell in row)
            switch (cell.text.lastIndexOf(':')) {
              -1 => (cell.text, 'text'),
              final i => (
                cell.text.substring(0, i),
                cell.text.substring(i + 1),
              ),
            },
        ];
        continue;
      }
      final record = <String, Object?>{};
      for (var i = 0; i < columns.length; i++) {
        final (name, type) = columns[i];
        final cell = i < row.length ? row[i] : const _Cell('', false);
        record[name] = _value(cell, type, section, name);
      }
      sections[section]!.add(record);
    }
    for (final name in tables) {
      if (!sections.containsKey(name)) {
        throw FormatException('В таблице нет раздела «$name»');
      }
    }
    Map<String, Object?> pairs(String name) => {
      for (final r in sections[name] ?? const <Map<String, Object?>>[])
        if (r['key'] is String) r['key'] as String: _json(r['value'], name),
    };
    final prefs = pairs('preferences');
    final meta = pairs('meta');
    return {
      'schemaVersion': schema,
      'data': {
        for (final name in tables) name: sections[name],
        'preferences': prefs,
        'demo': meta['demo'] is bool ? meta['demo'] : false,
      },
    };
  }

  static Object? _json(Object? raw, String section) {
    if (raw is! String) return raw;
    try {
      return jsonDecode(raw);
    } on FormatException {
      throw FormatException('Повреждённое значение в разделе «$section»');
    }
  }

  static Object? _value(_Cell cell, String type, String section, String name) {
    final text = cell.text;
    if (text.isEmpty && !cell.quoted) return null;
    Never bad() => throw FormatException(
      'Неверное значение «$text» в разделе «$section», столбец «$name»',
    );
    switch (type) {
      case 'text':
        return text.startsWith("'") ? text.substring(1) : text;
      case 'int':
        return int.tryParse(text.trim()) ?? bad();
      case 'num':
        return num.tryParse(text.trim().replaceAll(',', '.')) ?? bad();
      case 'bool':
        return switch (text.trim().toLowerCase()) {
          'true' || '1' || 'да' => true,
          'false' || '0' || 'нет' => false,
          _ => bad(),
        };
      case 'json':
        try {
          return jsonDecode(text);
        } on FormatException {
          bad();
        }
      default:
        throw FormatException('Неизвестный тип столбца «$name:$type»');
    }
  }

  /// RFC 4180 rows; remembers which cells were quoted.
  static List<List<_Cell>> _parse(String text) {
    final rows = <List<_Cell>>[];
    var row = <_Cell>[];
    final cell = StringBuffer();
    var quoted = false, inQuotes = false, any = false;
    void endCell() {
      row.add(_Cell(cell.toString(), quoted));
      cell.clear();
      quoted = false;
    }

    void endRow() {
      if (any) {
        endCell();
        rows.add(row);
      } else {
        rows.add(const []);
      }
      row = <_Cell>[];
      any = false;
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
        continue;
      }
      switch (ch) {
        case '"':
          inQuotes = true;
          quoted = true;
          any = true;
        case ',' || ';':
          // A semicolon too: Excel in Russian saves tables with it.
          any = true;
          endCell();
        case '\r':
          break;
        case '\n':
          endRow();
        default:
          any = true;
          cell.write(ch);
      }
    }
    if (inQuotes) {
      throw const FormatException('Повреждённая таблица: незакрытые кавычки');
    }
    if (any) endRow();
    return rows;
  }
}

class _Cell {
  const _Cell(this.text, this.quoted);
  final String text;
  final bool quoted;
}
