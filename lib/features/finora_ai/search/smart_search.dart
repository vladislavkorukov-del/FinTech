import '../../../domain/models.dart';
import '../../../presentation/widgets/common.dart' show money;
import '../conversation/conversation_context.dart' show ConversationContext;

/// A search asked in words (Phase 7): «найди траты в Пятёрочке больше 1000
/// за октябрь», «покажи покупки дороже 5000 в прошлом месяце», «самые
/// крупные расходы за неделю», «доходы от 50 000».
class SmartQuery {
  const SmartQuery({
    this.kind,
    this.text = '',
    this.categoryId,
    this.minMinor,
    this.maxMinor,
    this.start,
    this.end,
    this.periodLabel = '',
    this.biggestFirst = false,
  });
  final EntryKind? kind;

  /// Words to look for in the payee or note («пятерочк»).
  final String text;
  final String? categoryId;
  final int? minMinor, maxMinor;

  /// [start] inclusive, [end] exclusive; null — all time.
  final DateTime? start, end;
  final String periodLabel;
  final bool biggestFirst;

  /// Something narrower than «all operations of a period» was asked —
  /// a sum, a place or the biggest ones (the plain list stays the voice
  /// command's job).
  bool get specific =>
      text.isNotEmpty || minMinor != null || maxMinor != null || biggestFirst;
}

class SmartResult {
  const SmartResult(this.query, this.entries, this.totalMinor);
  final SmartQuery query;
  final List<FinanceEntry> entries;
  final int totalMinor;
}

abstract final class SmartSearch {
  static final _trigger = RegExp(
    r'^(найди|найти|поищи|покажи|показать|выведи|какие|сколько было|где)(\s|$)|'
    r'(самые|самая|самых) (крупн|больш|дорог)',
    caseSensitive: false,
  );

  static const _months = {
    'январ': 1,
    'феврал': 2,
    'март': 3,
    'апрел': 4,
    'ма[йя]': 5,
    'июн': 6,
    'июл': 7,
    'август': 8,
    'сентябр': 9,
    'октябр': 10,
    'ноябр': 11,
    'декабр': 12,
  };

  /// [text] as a search, or null when it is not one.
  static SmartQuery? parse(String text, FinanceData data, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    var t = text.toLowerCase().replaceAll('ё', 'е').trim();
    t = t.replaceAll(RegExp(r'[?!.]+$'), '');
    if (!_trigger.hasMatch(t)) return null;

    EntryKind? kind;
    if (RegExp(r'доход|поступлен|зарплат').hasMatch(t)) {
      kind = EntryKind.income;
    } else if (RegExp(r'расход|трат|покупк|платеж|оплат').hasMatch(t)) {
      kind = EntryKind.expense;
    }
    int? amount(String m) {
      final raw = m.replaceAll(RegExp(r'\s'), '');
      final k = RegExp(r'(\d+(?:[.,]\d+)?)(тыс|к)?').firstMatch(raw);
      if (k == null) return null;
      final v = double.tryParse(k.group(1)!.replaceAll(',', '.'));
      if (v == null) return null;
      return (v * (k.group(2) != null ? 1000 : 1) * 100).round();
    }

    int? min, max;
    final num = r'(\d[\d\s]*(?:[.,]\d+)?\s*(?:тыс|к)?)';
    final more = RegExp(
      '(больше|дороже|свыше|более|от|выше)\\s+$num',
    ).firstMatch(t);
    if (more != null) {
      min = amount(more.group(2)!);
      t = t.replaceRange(more.start, more.end, ' ');
    }
    final less = RegExp('(меньше|дешевле|менее|до|ниже)\\s+$num').firstMatch(t);
    if (less != null) {
      max = amount(less.group(2)!);
      t = t.replaceRange(less.start, less.end, ' ');
    }
    t = t.replaceAll(RegExp(r'(рубл\S*|руб|₽)'), ' ');

    // The period.
    DateTime? start, end;
    var label = '';
    final day = DateTime(clock.year, clock.month, clock.day);
    if (RegExp(r'сегодня').hasMatch(t)) {
      (start, end, label) = (day, day.add(const Duration(days: 1)), 'сегодня');
    } else if (RegExp(r'вчера').hasMatch(t)) {
      (start, end, label) = (
        day.subtract(const Duration(days: 1)),
        day,
        'вчера',
      );
    } else if (RegExp(r'прошл\S* недел').hasMatch(t)) {
      final ws = data.preferences.weekStart;
      final s = day.subtract(Duration(days: (day.weekday - ws) % 7 + 7));
      (start, end, label) = (
        s,
        s.add(const Duration(days: 7)),
        'на прошлой неделе',
      );
    } else if (RegExp(r'недел').hasMatch(t)) {
      final ws = data.preferences.weekStart;
      final s = day.subtract(Duration(days: (day.weekday - ws) % 7));
      (start, end, label) = (
        s,
        s.add(const Duration(days: 7)),
        'на этой неделе',
      );
    } else if (RegExp(r'прошл\S* месяц').hasMatch(t)) {
      final s = DateTime(clock.year, clock.month - 1);
      (start, end, label) = (
        s,
        DateTime(clock.year, clock.month),
        'в прошлом месяце',
      );
    } else if (RegExp(r'(этом|этот|текущ\S*) месяц').hasMatch(t)) {
      final s = DateTime(clock.year, clock.month);
      (start, end, label) = (
        s,
        DateTime(clock.year, clock.month + 1),
        'в этом месяце',
      );
    } else if (RegExp(r'(этом|этот|за) год').hasMatch(t)) {
      (start, end, label) = (
        DateTime(clock.year),
        DateTime(clock.year + 1),
        'в этом году',
      );
    } else {
      for (final m in _months.entries) {
        if (RegExp('(в|за) ${m.key}').hasMatch(t)) {
          final year = m.value > clock.month ? clock.year - 1 : clock.year;
          start = DateTime(year, m.value);
          end = DateTime(year, m.value + 1);
          label =
              'за ${_monthName(m.value)}${year == clock.year ? '' : ' $year'}';
          t = t.replaceAll(RegExp('(в|за) ${m.key}\\S*'), ' ');
          break;
        }
      }
    }
    final biggest = RegExp(
      r'(самые|самая|самых) (крупн|больш|дорог)',
    ).hasMatch(t);

    // A category named in the words.
    final categoryId = ConversationContext.categoryIn(t, data);

    // Place words: what is left after the service words.
    final stop = RegExp(
      r'^(найди|найти|поищи|покажи|показать|выведи|какие|сколько|было|где|все|мои|'
      r'траты|трат|расходы|расход|доходы|доход|покупки|покупка|платежи|операции|'
      r'самые|самая|самых|крупные|крупных|большие|дорогие|в|во|на|за|по|у|из|'
      r'этой|этом|этот|прошлой|прошлом|неделе|неделю|месяце|месяц|году|год|'
      r'сегодня|вчера|я|мне|и|с|тыс|к|потратил\S*|сумм\S*)$',
    );
    final words = t
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where(
          (w) =>
              w.isNotEmpty && !stop.hasMatch(w) && !RegExp(r'^\d').hasMatch(w),
        )
        .toList();
    // Category words are not a place.
    final category = data.categories
        .where((c) => c.id == categoryId)
        .firstOrNull;
    final catStem = category == null
        ? ''
        : category.name.toLowerCase().replaceAll('ё', 'е');
    final place = words
        .where(
          (w) =>
              catStem.isEmpty ||
              !catStem.contains(w.substring(0, w.length < 5 ? w.length : 5)),
        )
        .map((w) => w.length > 6 ? w.substring(0, w.length - 2) : w)
        .join(' ');
    final q = SmartQuery(
      kind:
          kind ??
          (min != null || max != null || place.isNotEmpty || biggest
              ? EntryKind.expense
              : null),
      text: place,
      categoryId: categoryId,
      minMinor: min,
      maxMinor: max,
      start: start,
      end: end,
      periodLabel: label,
      biggestFirst: biggest,
    );
    return q.specific || categoryId != null ? q : null;
  }

  static SmartResult run(SmartQuery q, FinanceData data) {
    final words = q.text.split(' ').where((w) => w.isNotEmpty).toList();
    bool matches(FinanceEntry e) {
      if (e.status == 'cancelled') return false;
      if (q.kind != null && e.kind != q.kind) return false;
      if (q.kind == null && e.kind == EntryKind.transfer) return false;
      if (q.categoryId != null && e.categoryId != q.categoryId) return false;
      if (q.minMinor != null && e.amountMinor < q.minMinor!) return false;
      if (q.maxMinor != null && e.amountMinor > q.maxMinor!) return false;
      if (q.start != null && e.date.isBefore(q.start!)) return false;
      if (q.end != null && !e.date.isBefore(q.end!)) return false;
      if (words.isNotEmpty) {
        final hay = '${e.payee} ${e.note}'.toLowerCase().replaceAll('ё', 'е');
        if (!words.every(hay.contains)) return false;
      }
      return true;
    }

    final found = data.entries.where(matches).toList()
      ..sort(
        (a, b) => q.biggestFirst
            ? b.amountMinor.compareTo(a.amountMinor)
            : b.date.compareTo(a.date),
      );
    final base = data.preferences.baseCurrency;
    final total = found
        .where((e) => e.currency == base)
        .fold<int>(0, (s, e) => s + e.amountMinor);
    return SmartResult(q, found, total);
  }

  /// The search's answer in words, with up to five operations.
  static String answer(SmartResult r, FinanceData data) {
    final q = r.query;
    final base = data.preferences.baseCurrency;
    final what = [
      q.kind == EntryKind.income ? 'доходы' : 'расходы',
      if (q.categoryId != null)
        '«${data.categories.where((c) => c.id == q.categoryId).firstOrNull?.name ?? ''}»',
      if (q.text.isNotEmpty) 'по «${q.text}»',
      if (q.minMinor != null) 'от ${money(q.minMinor!, base)}',
      if (q.maxMinor != null) 'до ${money(q.maxMinor!, base)}',
      if (q.periodLabel.isNotEmpty) q.periodLabel,
    ].join(' ');
    if (r.entries.isEmpty) {
      return 'Ничего не нашла: $what.';
    }
    final lines = <String>[
      'Нашла ${r.entries.length} — $what, всего ${money(r.totalMinor, base)}.',
    ];
    for (final e in r.entries.take(5)) {
      final d =
          '${e.date.day.toString().padLeft(2, '0')}.${e.date.month.toString().padLeft(2, '0')}';
      final name = e.payee.isNotEmpty
          ? e.payee
          : data.categories
                    .where((c) => c.id == e.categoryId)
                    .firstOrNull
                    ?.name ??
                'Операция';
      lines.add('• $d $name — ${money(e.amountMinor, e.currency)}');
    }
    if (r.entries.length > 5) lines.add('…и ещё ${r.entries.length - 5}.');
    return lines.join('\n');
  }

  static String _monthName(int m) => const [
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ][m - 1];
}
