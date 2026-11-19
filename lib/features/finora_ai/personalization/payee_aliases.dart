import '../classification/merchant_intelligence.dart';
import '../memory/personal_memory.dart';

/// The person's own short names for places: «кб» is «Красное&Белое»,
/// «пят» is «Пятёрочка». Finora learns them two ways:
///
/// - taught in the chat: «кб — это Красное и Белое», «запомни: кб значит
///   Красное&Белое» ([parseTeaching]);
/// - from a correction: the voice or the chat filled the form with «Кб»
///   and the person changed it to «Красное&Белое» before saving
///   ([looksLikeShortFor] keeps a typo fix or a different shop from being
///   learned as a short name).
///
/// A known short name is then written in full wherever an operation is
/// drafted — the voice form, the chat, the editor — and the place's usual
/// category follows from the full name.
abstract final class PayeeAliases {
  /// The memory key of a short name: lower case, letters and digits only.
  static String key(String short) => short
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  /// The full name for [payee] if the person taught one, else null.
  static String? resolve(PersonalMemory memory, String payee) {
    final k = key(payee);
    if (k.isEmpty) return null;
    return memory.aliases[k];
  }

  /// Remembers that [short] means [full]. Returns the stored full name
  /// (a known brand is written its own way: «красное и белое» →
  /// «Красное&Белое»), or null when there is nothing to learn.
  static String? learn(PersonalMemory memory, String short, String full) {
    final k = key(short);
    final name = tidy(full);
    if (k.isEmpty || name.isEmpty || k == key(name) || k.length > 24) {
      return null;
    }
    memory.aliases.remove(k);
    memory.aliases[k] = name;
    while (memory.aliases.length > PersonalMemory.maxAliases) {
      memory.aliases.remove(memory.aliases.keys.first);
    }
    return name;
  }

  static bool forget(PersonalMemory memory, String short) =>
      memory.aliases.remove(key(short)) != null;

  /// The brand's own spelling for a known place, else the name with a
  /// capital letter.
  static String tidy(String full) {
    final text = full.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return '';
    final brand = MerchantIntelligence.brandName(text);
    if (brand != null) return brand;
    return text[0].toUpperCase() + text.substring(1);
  }

  static const _small = {'и', 'в', 'на', 'у', 'по', 'the', 'and', 'of'};

  /// Whether [short] plausibly abbreviates [full]: its first letters
  /// («кб» ← «Красное и Белое»), the start of it («пят» ← «Пятёрочка»),
  /// or a short form that keeps the full name's letters in order
  /// («крб» ← «Красное&Белое»). A different shop («Магнит» → «Пятёрочка»)
  /// or a fixed typo («Пятерчка» → «Пятёрочка», no shorter) is not.
  static bool looksLikeShortFor(String short, String full) {
    final s = key(short);
    final f = key(full);
    if (s.isEmpty || f.isEmpty || s == f || s.length >= f.length) {
      return false;
    }
    if (s.length > 6 && s.length * 2 > f.length) return false;
    final words = full
        .toLowerCase()
        .replaceAll('ё', 'е')
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.map((w) => w[0]).join();
    final bigInitials = words
        .where((w) => !_small.contains(w))
        .map((w) => w[0])
        .join();
    if (s == initials || s == bigInitials) return true;
    if (s.length >= 3 && f.startsWith(s)) return true;
    // Letters of the full name in order, starting with its first letter.
    if (s[0] != f[0] || s.length < 2) return false;
    var i = 0;
    for (final ch in f.split('')) {
      if (i < s.length && ch == s[i]) i++;
    }
    return i == s.length && s.length <= 5;
  }

  static final _teach = RegExp(
    r'^(?:запомни[,:]?\s*(?:что\s+)?|учти[,:]?\s*(?:что\s+)?)?'
    r'[«"]?(?<short>[\p{L}\p{N}][\p{L}\p{N}.\-]{0,15}?)[»"]?\s*'
    r'(?:[—–-]\s*)?(?:это|значит|означает|=|—|–|-)\s+'
    r'[«"]?(?<full>[^«»"?!]{2,60}?)[»"]?[.!]?$',
    caseSensitive: false,
    unicode: true,
  );

  /// «кб — это Красное и Белое», «запомни: кб значит Красное&Белое»,
  /// «КБ = Красное и белое» → (short, full). Null for anything else; a
  /// question («кб это что?») is not a teaching.
  static (String, String)? parseTeaching(String text) {
    final t = text.trim();
    if (t.contains('?') || t.length > 90) return null;
    final m = _teach.firstMatch(t);
    if (m == null) return null;
    final short = m.namedGroup('short')!.trim();
    final full = m.namedGroup('full')!.trim();
    // «это» sentences about money are not names: «расход это 500».
    if (RegExp(r'\d').hasMatch(full)) return null;
    final shortKey = key(short);
    if (shortKey.isEmpty || shortKey.length > 8) return null;
    if (_commandWords.contains(shortKey)) return null;
    if (key(full) == shortKey) return null;
    // Teaching needs «запомни» or a short name that looks like one.
    final explicit = RegExp(
      r'^(запомни|учти)',
      caseSensitive: false,
    ).hasMatch(t);
    if (!explicit && !looksLikeShortFor(short, full)) return null;
    return (short, full);
  }

  static const _commandWords = {
    'расход',
    'доход',
    'перевод',
    'что',
    'кто',
    'как',
    'где',
    'бюджет',
    'долг',
    'план',
    'итог',
    'баланс',
    'это',
  };
}
