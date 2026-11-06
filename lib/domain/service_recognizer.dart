import 'service_catalog.dart';
import 'store_catalog.dart';

/// Finds a subscription or store by how its name sounds (Finora 1.26):
/// «чат гпт» and «ЧатГПТ» are ChatGPT, «нетфликс» is Netflix, «ютуб премиум»
/// is YouTube Premium, «вуш» is Whoosh — said by voice or typed in Cyrillic.
///
/// Both the phrase and every name are turned into a rough sound key (Latin
/// letters, Cyrillic transliterated, English spellings simplified), then
/// compared word window by word window. Short names must be the whole
/// phrase, longer ones may be off by a letter or two.
abstract final class ServiceRecognizer {
  /// Aliases that name a parent brand or an everyday word rather than the
  /// service itself («сбер» is a bank, «вид» is a Russian word).
  static const _weak = <String>{
    'сбер',
    'сбербанк',
    'мтс',
    'вк',
    'вконтакте',
    'озон',
    'apple',
    'sony',
    'office',
    'офис',
    'макс',
    'нитро',
    'премиум',
    'норд',
    'гост',
    'вид',
    'кода',
    'сингс',
    'лум',
    'старт',
    'бокс',
    'медиум',
    'неон',
    'кипер',
    'курсор',
    'ростелеком',
    'нвидиа',
    'nvidia',
    'гитхаб',
    'github',
    'microsoft365',
    'ms365',
    'electronic arts',
    'спорт',
    'аниме',
    'авторы',
    'видео',
    'сайты',
    'стримы',
    'подкасты',
    'медитация',
    'аудиокниги',
    'резервная копия',
    'видеосвязь',
    'пароли',
    'заметки',
    'задачи',
    'дизайн',
    'языки',
    'разработка',
    'музыка',
    'кино',
    'облако',
    'vpn',
  };

  /// Russian words that sound like a service name («бокс» = Box): said in
  /// Cyrillic they mean the word, typed in Latin they mean the service.
  static final Set<String> _ordinary = {
    for (final w in const [
      'бокс',
      'старт',
      'вид',
      'кода',
      'лум',
      'неон',
      'медиум',
      'курсор',
      'кипер',
      'гост',
      'миро',
      'кит',
      'рендер',
      'экспо',
      'сентри',
      'оранж',
      'буфер',
      'вещи',
    ])
      key(w),
  };

  static final List<(SubscriptionService, String)> _keys = () {
    final out = <(SubscriptionService, String)>[];
    final seen = <String>{};
    for (final service in [
      ...ServiceCatalog.entries,
      ...StoreCatalog.entries,
    ]) {
      for (final name in [service.name, ...service.aliases]) {
        final lower = name.toLowerCase().replaceAll('ё', 'е').trim();
        if (_weak.contains(lower)) continue;
        final k = key(name);
        if (k.length < 3 || !seen.add('${service.id}|$k')) continue;
        out.add((service, k));
      }
    }
    return out;
  }();

  static const _cyrillic = <String, String>{
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'д': 'd',
    'е': 'e',
    'ё': 'e',
    'ж': 'zh',
    'з': 'z',
    'и': 'i',
    'й': 'i',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ф': 'f',
    'х': 'h',
    'ц': 'ts',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'sh',
    'ъ': '',
    'ы': 'i',
    'ь': '',
    'э': 'e',
    'ю': 'iu',
    'я': 'ia',
  };

  /// A rough sound key: «ChatGPT» and «чат гпт» → «chatgpt», «Netflix» and
  /// «нетфликс» → «netfliks».
  static String key(String value) {
    var s = value.toLowerCase();
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(_cyrillic[ch] ?? ch);
    }
    s = b.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
    s = s
        .replaceAll('ph', 'f')
        .replaceAll('wh', 'v')
        .replaceAll('ck', 'k')
        .replaceAll('qu', 'kv')
        .replaceAll('q', 'k')
        .replaceAll('x', 'ks')
        .replaceAll('w', 'v')
        .replaceAll('tch', 'ch')
        .replaceAll('ch', '#')
        .replaceAll(RegExp(r'c(?=[eiy])'), 's')
        .replaceAll('c', 'k')
        .replaceAll('#', 'ch')
        .replaceAll('kh', 'h')
        .replaceAll('j', 'dzh')
        .replaceAll('y', 'i')
        .replaceAll('ee', 'i')
        .replaceAll('ea', 'i')
        .replaceAll('oo', 'u')
        .replaceAll('ou', 'u')
        .replaceAll('iu', 'u');
    // Doubled letters: one.
    s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
    // A silent final «e» («youtube», «claude»).
    if (s.length > 4 && s.endsWith('e')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// The service or store [text] names, or null. The longest, closest name
  /// wins; two different services equally close give null.
  static SubscriptionService? find(String? text) {
    if (text == null) return null;
    final words = text
        .toLowerCase()
        .replaceAll('ё', 'е')
        .split(RegExp(r'[^\p{L}\p{N}+]+', unicode: true))
        .where((w) => w.isNotEmpty && !RegExp(r'^\d+$').hasMatch(w))
        .toList();
    if (words.isEmpty) return null;
    final latin = RegExp('[a-z]').hasMatch(words.join());
    final whole = key(words.join());
    final windows = <String>{};
    for (var n = 1; n <= 4 && n <= words.length; n++) {
      for (var i = 0; i + n <= words.length; i++) {
        windows.add(key(words.sublist(i, i + n).join()));
      }
    }
    SubscriptionService? best;
    var score = 0;
    var tie = false;
    void offer(SubscriptionService s, int value) {
      if (value > score) {
        best = s;
        score = value;
        tie = false;
      } else if (value == score && best?.id != s.id) {
        tie = true;
      }
    }

    for (final (service, k) in _keys) {
      if (!latin && _ordinary.contains(k)) continue;
      if (k.length < 5) {
        if (whole == k) offer(service, 100 + k.length * 2);
        continue;
      }
      for (final w in windows) {
        if (w == k) {
          offer(service, 100 + k.length * 2);
        } else if (k.length >= 6 &&
            !service.id.startsWith('store_') &&
            w[0] == k[0] &&
            (w.length - k.length).abs() <= 2) {
          // Near misses only for (Latin-named) subscriptions, from the
          // same first sound: «спотифай» ≈ Spotify, «аптека» ≠ ЕАПТЕКА.
          final d = _distance(w, k);
          if (d <= (k.length * .2).floor()) {
            offer(service, 60 + k.length - d * 6);
          }
        }
      }
    }
    return tie ? null : best;
  }

  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
