import 'package:flutter/services.dart';

/// 1.36: sums are typed with their thousands apart — «1 234 567,89».
/// The gap is a narrow no-break space (U+202F), which
/// [FinanceEngine.parseMinor] ignores.
const amountGap = ' ';

/// [raw] with its whole part grouped by three digits.
String groupAmount(String raw) {
  final text = raw.replaceAll(RegExp('[   ]'), '');
  final m = RegExp(r'^([+-]?)(\d*)([.,]\d*)?(.*)$').firstMatch(text);
  if (m == null || m[4]!.isNotEmpty) return text;
  final whole = m[2]!;
  final out = StringBuffer(m[1]!);
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(amountGap);
    out.write(whole[i]);
  }
  out.write(m[3] ?? '');
  return out.toString();
}

/// Groups as the person types; the cursor stays after the same digit.
class AmountGroupingFormatter extends TextInputFormatter {
  const AmountGroupingFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final grouped = groupAmount(newValue.text);
    if (grouped == newValue.text) return newValue;
    // Count what is not a gap before the cursor, and find it again.
    final cursor = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    var keep = 0;
    for (var i = 0; i < cursor; i++) {
      if (!_gap(newValue.text[i])) keep++;
    }
    var at = 0;
    while (at < grouped.length && keep > 0) {
      if (!_gap(grouped[at])) keep--;
      at++;
    }
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: at),
    );
  }

  static bool _gap(String c) => c == ' ' || c == ' ' || c == amountGap;
}
