/// The amount calculator (entry editor): «450 + 120», «1 200 × 3»,
/// «3 000 − 15 %». Money stays in whole minor units: every operand is read
/// as a decimal with up to two places and the result is rounded half away
/// from zero to a kopeck. No `double` takes part.
///
/// Operators: `+ − × ÷` (also `- * /`) and a trailing `%` on a number:
/// «a + b %» adds b percent of a, «a × b %» takes b percent of a, a lone
/// «b %» is b hundredths. × and ÷ bind tighter than + and −.
abstract final class AmountExpression {
  static const operators = {'+', '−', '×', '÷'};

  /// True when [text] holds an operator, i.e. it is a calculation rather
  /// than a plain amount.
  static bool isCalculation(String text) =>
      RegExp(r'[+×÷*/−]|(?<=\d)\s*-').hasMatch(text.trim());

  /// The value of [text] in minor units, or null when it is empty, broken
  /// (two operators in a row, a third decimal place) or divides by zero.
  /// A dangling operator at the end is ignored, so a live result can be
  /// shown while the person types.
  static int? evaluate(String text) {
    final tokens = _tokens(text);
    if (tokens == null || tokens.isEmpty) return null;
    if (tokens.last is String) tokens.removeLast();
    if (tokens.isEmpty || tokens.first is String) return null;
    return _eval(tokens);
  }

  static int? _eval(List<Object> tokens) {
    if (tokens.isEmpty) return null;
    // Percentages first: they refer to the term on their left.
    final terms = <Object>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t is _Number && t.percent) {
        final op = i >= 2 ? tokens[i - 1] as String : null;
        if (op == '+' || op == '−') {
          // a ± b% → a ± a·b/100, where a is everything on the left.
          final base = _eval(tokens.sublist(0, i - 1));
          if (base == null) return null;
          terms.add(_Number(_round(base * t.minor, 10000)));
        } else {
          // a × b% → a·b/100 (b% alone is b/100)
          terms.add(_Number(_round(t.minor, 100)));
        }
      } else {
        terms.add(t);
      }
    }
    // × and ÷.
    final sums = <Object>[];
    for (var i = 0; i < terms.length; i++) {
      final t = terms[i];
      if (t == '×' || t == '÷') {
        final left = sums.removeLast() as _Number;
        final right = terms[++i] as _Number;
        if (t == '×') {
          sums.add(_Number(_round(left.minor * right.minor, 100)));
        } else {
          if (right.minor == 0) return null;
          sums.add(_Number(_round(left.minor * 100, right.minor)));
        }
      } else {
        sums.add(t);
      }
    }
    var total = (sums.first as _Number).minor;
    for (var i = 1; i < sums.length; i += 2) {
      final value = (sums[i + 1] as _Number).minor;
      total = sums[i] == '+' ? total + value : total - value;
    }
    return total;
  }

  /// [text] tidied for display: grouped numbers, spaced operators.
  static String pretty(String text) {
    final tokens = _tokens(text, allowOpen: true);
    if (tokens == null) return text;
    return tokens
        .map((t) => t is _Number ? t.shown : ' $t ')
        .join()
        .replaceAll('  ', ' ')
        .trim();
  }

  /// Rounds n / d half away from zero.
  static int _round(int n, int d) {
    final negative = (n < 0) != (d < 0);
    final q = (n.abs() * 2 + d.abs()) ~/ (d.abs() * 2);
    return negative ? -q : q;
  }

  static List<Object>? _tokens(String text, {bool allowOpen = false}) {
    final s = text
        .replaceAll(RegExp(r'[   ]'), '')
        .replaceAll('*', '×')
        .replaceAll('/', '÷')
        .replaceAll('-', '−')
        .replaceAll('.', ',');
    final out = <Object>[];
    final number = RegExp(r'^(\d+)(?:,(\d{0,2}))?(%)?');
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (operators.contains(ch)) {
        if (out.isEmpty || out.last is String) return null;
        out.add(ch);
        i++;
        continue;
      }
      final m = number.firstMatch(s.substring(i));
      if (m == null) return null;
      if (out.isNotEmpty && out.last is _Number) return null;
      final whole = int.parse(m[1]!);
      final frac = (m[2] ?? '').padRight(2, '0');
      if (whole > 90071992547409) return null;
      out.add(
        _Number(
          whole * 100 + int.parse(frac),
          percent: m[3] != null,
          typed: m[0]!,
        ),
      );
      i += m[0]!.length;
    }
    if (!allowOpen && out.isNotEmpty && out.last is String && out.length == 1) {
      return null;
    }
    return out;
  }
}

class _Number {
  _Number(this.minor, {this.percent = false, this.typed});
  final int minor;
  final bool percent;
  final String? typed;

  String get shown {
    final t = typed ?? '';
    final m = RegExp(r'^(\d+)(,\d*)?(%)?$').firstMatch(t);
    if (m == null) return t;
    final whole = m[1]!;
    final out = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) out.write(' ');
      out.write(whole[i]);
    }
    return '$out${m[2] ?? ''}${m[3] == null ? '' : ' %'}';
  }
}
