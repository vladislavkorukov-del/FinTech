import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// An import adapter for Excel files (.xlsx) from banks and other finance
/// apps (Phase 7). An .xlsx is a ZIP of XML parts; this reads the first
/// worksheet and its shared strings with the platform's own inflater and
/// turns the cells into CSV text, which then goes through the existing
/// [ForeignCsv] import (column mapping, categories, duplicates). No new
/// package; nothing leaves the phone.
///
/// Supported: text (shared and inline strings), numbers, booleans. Dates
/// stored as Excel serial numbers are converted to dd.MM.yyyy when the
/// column header looks like a date. Formulas give their cached value.
abstract final class XlsxReader {
  /// Whether [bytes] look like a ZIP (an .xlsx starts with «PK»).
  static bool looksLikeXlsx(Uint8List bytes) =>
      bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  /// The first worksheet as CSV (`;`-separated, quoted where needed).
  static String toCsv(Uint8List bytes) {
    final rows = readRows(bytes);
    String cell(String v) {
      if (v.contains(';') || v.contains('"') || v.contains('\n')) {
        return '"${v.replaceAll('"', '""')}"';
      }
      return v;
    }

    return rows.map((r) => r.map(cell).join(';')).join('\n');
  }

  /// The first worksheet's rows (trailing empty rows dropped).
  static List<List<String>> readRows(Uint8List bytes) {
    final files = _unzip(bytes);
    final shared = <String>[];
    final sharedXml = files['xl/sharedStrings.xml'];
    if (sharedXml != null) {
      for (final si in RegExp(
        r'<si>(.*?)</si>',
        dotAll: true,
      ).allMatches(sharedXml)) {
        shared.add(_text(si.group(1)!));
      }
    }
    final sheetName =
        files.keys
            .where((k) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(k))
            .toList()
          ..sort((a, b) => _num(a).compareTo(_num(b)));
    if (sheetName.isEmpty) {
      throw const FormatException('В файле Excel нет листов с данными.');
    }
    final sheet = files[sheetName.first]!;
    final rows = <List<String>>[];
    for (final row in RegExp(
      r'<row\b[^>]*>(.*?)</row>',
      dotAll: true,
    ).allMatches(sheet)) {
      final cells = <int, String>{};
      for (final c in RegExp(
        r'<c\b([^>]*?)(?:/>|>(.*?)</c>)',
        dotAll: true,
      ).allMatches(row.group(1)!)) {
        final attrs = c.group(1)!;
        final body = c.group(2) ?? '';
        final ref = RegExp(r'r="([A-Z]+)\d+"').firstMatch(attrs)?.group(1);
        final type = RegExp(r't="(\w+)"').firstMatch(attrs)?.group(1);
        final index = ref == null ? cells.length : _column(ref);
        final raw = RegExp(
          r'<v>(.*?)</v>',
          dotAll: true,
        ).firstMatch(body)?.group(1);
        String value;
        switch (type) {
          case 's':
            final i = int.tryParse(raw ?? '');
            value = i != null && i < shared.length ? shared[i] : '';
          case 'inlineStr':
            value = _text(body);
          case 'b':
            value = raw == '1' ? 'TRUE' : 'FALSE';
          default:
            value = _unescape(raw ?? '');
        }
        cells[index] = value.trim();
      }
      if (cells.isEmpty) {
        rows.add(const []);
        continue;
      }
      final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
      rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
    }
    while (rows.isNotEmpty && rows.last.every((v) => v.isEmpty)) {
      rows.removeLast();
    }
    if (rows.isEmpty) {
      throw const FormatException('Лист Excel пуст.');
    }
    return _datesInColumns(rows);
  }

  /// Excel serial dates under a «дата/date» header become dd.MM.yyyy.
  static List<List<String>> _datesInColumns(List<List<String>> rows) {
    final header = rows.first.map((h) => h.toLowerCase()).toList();
    final dateCols = [
      for (var i = 0; i < header.length; i++)
        if (RegExp(r'дата|date|время|time').hasMatch(header[i])) i,
    ];
    if (dateCols.isEmpty) return rows;
    final base = DateTime.utc(1899, 12, 30);
    return [
      rows.first,
      for (final r in rows.skip(1))
        [
          for (var i = 0; i < r.length; i++)
            if (dateCols.contains(i) &&
                RegExp(r'^\d{4,6}(\.\d+)?$').hasMatch(r[i]))
              () {
                final serial = double.parse(r[i]);
                final d = base.add(
                  Duration(milliseconds: (serial * 86400000).round()),
                );
                final day =
                    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
                final hasTime = serial % 1 != 0;
                return hasTime
                    ? '$day ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
                    : day;
              }()
            else
              r[i],
        ],
    ];
  }

  static int _num(String name) =>
      int.tryParse(RegExp(r'(\d+)').firstMatch(name)?.group(1) ?? '') ?? 0;

  /// «A» → 0, «Z» → 25, «AA» → 26.
  static int _column(String letters) {
    var n = 0;
    for (final ch in letters.codeUnits) {
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }

  static String _text(String xml) => _unescape(
    RegExp(
      r'<t\b[^>]*>(.*?)</t>',
      dotAll: true,
    ).allMatches(xml).map((m) => m.group(1)!).join(),
  );

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(
        RegExp(r'&#(x?)([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(
          int.parse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16),
        ),
      )
      .replaceAll('&amp;', '&');

  /// The XML parts of the ZIP, from its central directory.
  static Map<String, String> _unzip(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    // End of central directory: signature 0x06054b50, searched from the end.
    var eocd = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('Это не файл Excel (.xlsx).');
    final count = data.getUint16(eocd + 10, Endian.little);
    var p = data.getUint32(eocd + 16, Endian.little);
    final out = <String, String>{};
    for (var n = 0; n < count; n++) {
      if (data.getUint32(p, Endian.little) != 0x02014b50) break;
      final method = data.getUint16(p + 10, Endian.little);
      final compressed = data.getUint32(p + 20, Endian.little);
      final nameLen = data.getUint16(p + 28, Endian.little);
      final extraLen = data.getUint16(p + 30, Endian.little);
      final commentLen = data.getUint16(p + 32, Endian.little);
      final local = data.getUint32(p + 42, Endian.little);
      final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen));
      p += 46 + nameLen + extraLen + commentLen;
      final wanted =
          name == 'xl/sharedStrings.xml' ||
          RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(name);
      if (!wanted) continue;
      final lName = data.getUint16(local + 26, Endian.little);
      final lExtra = data.getUint16(local + 28, Endian.little);
      final start = local + 30 + lName + lExtra;
      final raw = bytes.sublist(start, start + compressed);
      final List<int> plain = switch (method) {
        0 => raw,
        8 => ZLibDecoder(raw: true).convert(raw),
        _ => throw const FormatException(
          'Файл Excel сжат неподдерживаемым способом.',
        ),
      };
      out[name] = utf8.decode(plain, allowMalformed: true);
    }
    return out;
  }
}
