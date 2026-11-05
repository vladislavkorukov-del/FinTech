#!/usr/bin/env python3
"""Build/verify the offline Russian bank catalog and its original logos.

Source of truth for the list of credit organizations is the official Bank of
Russia BIC directory (ED807, https://www.cbr.ru/s/newbik). Only participants
with PtType=20 (credit organizations) are included; branches, treasury and
Bank of Russia divisions are not banks a person keeps an account in.

Modes (network is developer-only and opt-in):
  --build ED807.zip   regenerate assets/banks/registry.json and
                      lib/domain/bank_catalog.dart from a downloaded directory
  --fetch-logos       download the curated original logos (Wikimedia Commons)
                      into assets/banks/ and write assets/banks/manifest.json
  --render            render PNG display copies (Inkscape for SVG originals)
  --verify            offline: registry/Dart/logos/PNGs agree with recorded SHA

A logo is attached only when an original file of the bank's *current* mark is
available with recorded provenance. Every other organization is shown with a
neutral, unbranded bank glyph; no logo is drawn or guessed.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/banks'
RASTER = ASSETS / 'raster'
REGISTRY = ASSETS / 'registry.json'
MANIFEST = ASSETS / 'manifest.json'
RASTER_MANIFEST = RASTER / 'manifest.json'
DART = ROOT / 'lib/domain/bank_catalog.dart'
SOURCE_URL = 'https://www.cbr.ru/s/newbik'
SIZE = 384
GUTTER = 2
MAX_BYTES = 2 * 1024 * 1024
UA = {'User-Agent': 'Finance-bank-catalog/1.6 (developer build tool)'}

# Brand names people actually use, plus former names/abbreviations for search.
# Keys are Bank of Russia registration numbers; names are verified against the
# official directory at build time (a missing number fails the build).
BRANDS = {
    '1481': ('Сбербанк', ['Сбер', 'Сбербанк России', 'Sber', 'Sberbank']),
    '1000': ('ВТБ', ['Банк ВТБ', 'ВТБ24', 'VTB']),
    '354': ('Газпромбанк', ['ГПБ', 'Банк ГПБ', 'Gazprombank']),
    '1326': ('Альфа-Банк', ['Альфа', 'Альфабанк', 'Alfa-Bank', 'Alfa Bank']),
    '2673': ('Т-Банк', ['ТБанк', 'Т Банк', 'Тинькофф', 'Тинькофф Банк', 'T-Bank', 'Tinkoff']),
    '3349': ('Россельхозбанк', ['РСХБ', 'Rosselkhozbank']),
    '963': ('Совкомбанк', ['Халва', 'Sovcombank']),
    '3292': ('Райффайзенбанк', ['Райффайзен', 'Raiffeisen', 'Raiffeisenbank']),
    '3251': ('ПСБ', ['Промсвязьбанк', 'Банк ПСБ', 'PSB', 'Promsvyazbank']),
    '1978': ('МКБ', ['Московский кредитный банк', 'MKB', 'Credit Bank of Moscow']),
    '2312': ('Банк ДОМ.РФ', ['ДОМ.РФ', 'Дом РФ', 'DOM.RF']),
    '2766': ('ОТП Банк', ['ОТП', 'OTP Bank', 'OTP']),
    '3545': ('Точка', ['Банк Точка', 'Tochka']),
    '3027': ('Яндекс Банк', ['Yandex Bank', 'Яндекс Пэй', 'Yandex Pay']),
    '3542': ('Озон Банк', ['Ozon Банк', 'Ozon Bank', 'Озон']),
    '841': ('WB Банк', ['ВБ Банк', 'Вайлдберриз Банк', 'Wildberries Банк', 'WB Bank']),
    '2306': ('Абсолют Банк', ['Абсолют', 'Absolut Bank']),
    '1810': ('АТБ', ['Азиатско-Тихоокеанский Банк', 'ATB']),
    '2590': ('Ак Барс Банк', ['Ак Барс', 'Ak Bars']),
    '328': ('Банк «Россия»', ['АБ Россия', 'Банк Россия', 'Bank Rossiya']),
    '2268': ('МТС Банк', ['МТС-Банк', 'MTS Bank']),
    '2557': ('РенКап Банк', ['Ситибанк', 'Citibank', 'RenCap Bank']),
    '316': ('Хоум Банк', ['ХКФ Банк', 'Хоум Кредит', 'Home Credit', 'Home Bank']),
    '3354': ('Ренессанс Банк', ['Ренессанс Кредит', 'Renaissance Credit']),
    '3255': ('Банк Зенит', ['Зенит', 'Zenit']),
    '1927': ('Модульбанк', ['Модуль', 'Modulbank']),
    '2225': ('Центр-инвест', ['Центр инвест', 'Center-invest']),
    '429': ('УБРиР', ['Уральский банк реконструкции и развития', 'UBRR']),
    '3510-К': ('ЮMoney', ['Юмани', 'YooMoney', 'Яндекс Деньги', 'ЮMoney НКО']),
    '2275': ('Уралсиб', ['Банк Уралсиб', 'Uralsib']),
    '436': ('Банк «Санкт-Петербург»', ['БСПБ', 'Банк Санкт-Петербург', 'Bank Saint Petersburg']),
    '2289': ('Русский Стандарт', ['Банк Русский Стандарт', 'Russian Standard']),
    '1': ('ЮниКредит Банк', ['ЮниКредит', 'UniCredit']),
    '2998': ('Экспобанк', ['Expobank']),
    '2707': ('Локо-Банк', ['Локо', 'Loko-Bank']),
    '101': ('БКС Банк', ['БКС', 'BCS Bank']),
    '2799': ('Банк Финам', ['Финам', 'Finam']),
    '2546': ('Новикомбанк', ['Novikombank']),
    '705': ('Банк Синара', ['Синара', 'СКБ-Банк', 'Sinara']),
    '3223': ('Свой Банк', ['Свой', 'Svoi Bank']),
    '2879': ('Банк Авангард', ['Авангард', 'Avangard']),
    '3311': ('Кредит Европа Банк', ['Credit Europe Bank']),
    '2440': ('Металлинвестбанк', ['Metallinvestbank']),
    '3279': ('Банк Траст', ['Траст', 'Trust']),
    '1143': ('Цифра банк', ['Цифра', 'Cifra bank']),
    '2368': ('Бланк банк', ['Бланк', 'Blanc bank']),
    '3538': ('Банк 131', ['131', 'Bank 131']),
    '1751': ('Мособлбанк', ['Mosoblbank']),
    '2733': ('Примсоцбанк', ['Primsotsbank']),
    '2210': ('ТКБ Банк', ['ТКБ', 'TKB Bank']),
}

# Original files of the current marks, chosen per bank after visual review.
# Each needs Commons provenance; files are kept byte-for-byte unchanged.
LOGOS = {}


HELPERS = r"""
  static final Map<String, RussianBank> _byReg = {
    for (final bank in entries) bank.regNumber.toUpperCase(): bank,
  };
  static final Map<String, RussianBank> _byBic = {
    for (final bank in entries)
      for (final bic in bank.bics) bic: bank,
  };

  static final Map<String, RussianBank> _byId = {
    for (final bank in entries) bank.id: bank,
  };
  static RussianBank? byId(String? id) => _byId[id];

  static RussianBank? byRegNumber(String? value) =>
      value == null ? null : _byReg[value.trim().toUpperCase()];
  static RussianBank? byBic(String? value) =>
      value == null ? null : _byBic[value.trim()];

  static String _key(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[«»"“”„()\-–—.,/]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Exact name, brand, former name, registration number or BIC. Ambiguous
  /// text returns null instead of guessing an institution.
  static RussianBank? byName(String? value) {
    if (value == null || _key(value).isEmpty) return null;
    final wanted = _key(value);
    final direct = byRegNumber(value) ?? byBic(value);
    if (direct != null) return direct;
    final found = entries
        .where(
          (bank) =>
              _key(bank.name) == wanted ||
              _key(bank.officialName) == wanted ||
              bank.aliases.any((alias) => _key(alias) == wanted),
        )
        .toList();
    return found.length == 1 ? found.single : null;
  }

  /// All query words must occur; exact names rank first, then names that
  /// start with the query, then word-prefix and plain substring matches.
  static List<RussianBank> search(String query) {
    final wanted = _key(query);
    final terms = wanted.split(' ').where((s) => s.isNotEmpty).toList();
    if (terms.isEmpty) return entries;
    final ranked = <(int, int, RussianBank)>[];
    for (var i = 0; i < entries.length; i++) {
      final bank = entries[i];
      final names = [bank.name, bank.officialName, ...bank.aliases].map(_key);
      final haystack = _key(
        [
          bank.name,
          bank.officialName,
          bank.regNumber,
          bank.city,
          ...bank.bics,
          ...bank.aliases,
        ].join(' '),
      );
      if (!terms.every(haystack.contains)) continue;
      final words = haystack.split(' ');
      final rank = names.any((n) => n == wanted) || bank.bics.contains(wanted)
          ? 0
          : names.any((n) => n.startsWith(wanted))
          ? 1
          : terms.every((t) => words.any((w) => w.startsWith(t)))
          ? 2
          : 3;
      ranked.add((rank, i, bank));
    }
    ranked.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [for (final item in ranked) item.$3];
  }"""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def id_for(reg):
    return 'bank_' + re.sub(r'[^0-9a-z]', '', reg.lower().replace('к', 'k').replace('ц', 'c'))


LEGAL = r'(?:ПАО|ОАО|ЗАО|АО|ООО|НКО|РНКО|КБ|АКБ|АИКБ|КИБ|ИКБР|МКИБ|ЦК|СКБ|НБКО)'


def clean_name(official):
    name = official.replace('&quot;', '"')
    name = re.sub(r'\((?:ПАО|ОАО|ЗАО|АО|ООО)\)', ' ', name)
    name = re.sub(rf'(?<![А-Яа-яЁё]){LEGAL}(?![А-Яа-яЁё])', ' ', name)
    name = name.replace('"', ' ').replace('«', ' ').replace('»', ' ')
    name = re.sub(r'\s+', ' ', name).strip(' -,')
    if name.isupper():
        name = ' '.join(w if len(w) <= 3 and w.isalpha() and w not in ('БАНК',) else w.capitalize()
                        for w in name.split(' '))
        name = re.sub(r'-([а-яё])', lambda m: '-' + m[1].upper(), name)
    return name or official


def non_bank(reg, official):
    return reg.endswith('-К') or reg.endswith('-ЦК') or bool(
        re.search(r'(?<![А-Яа-я])(?:НКО|РНКО|НДКО|ЦК)(?![А-Яа-я])', official))


def parse_ed807(path):
    raw = Path(path).read_bytes()
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        names = [n for n in archive.namelist() if n.endswith('.xml')]
        if len(names) != 1:
            raise SystemExit('Expected one ED807 XML file')
        xml = archive.read(names[0])
    root = ET.fromstring(xml)
    ns = {'e': 'urn:cbr-ru:ed:v2.0'}
    if root.tag != '{urn:cbr-ru:ed:v2.0}ED807':
        raise SystemExit('Not an ED807 BIC directory')
    banks = {}
    for entry in root.findall('e:BICDirectoryEntry', ns):
        info = entry.find('e:ParticipantInfo', ns)
        if info is None or info.get('PtType') != '20' or not info.get('RegN'):
            continue
        reg = info.get('RegN')
        item = banks.setdefault(reg, {'regNumber': reg, 'officialName': info.get('NameP'),
                                      'city': info.get('Nnp') or '', 'bics': []})
        item['bics'].append(entry.get('BIC'))
    items = sorted(banks.values(), key=lambda b: (int(re.match(r'\d+', b['regNumber'])[0]), b['regNumber']))
    for item in items:
        item['bics'].sort()
    return {
        'source': SOURCE_URL,
        'sourceDescription': 'Bank of Russia BIC directory ED807, participants PtType=20 (credit organizations)',
        'archive': names[0],
        'archiveSha256': digest(raw),
        'xmlSha256': digest(xml),
        'edDate': root.get('EDDate'),
        'businessDay': root.get('BusinessDay'),
        'count': len(items),
        'items': items,
    }


def dart_string(value):
    return json.dumps(value, ensure_ascii=False).replace('$', r'\$')


def generate_dart(registry, manifest, raster):
    logos = {x['regNumber']: x for x in manifest.get('items', [])}
    rendered = {x['id']: x for x in raster.get('items', [])}
    regs = {x['regNumber'] for x in registry['items']}
    missing = sorted(set(BRANDS) - regs)
    if missing:
        raise SystemExit(f'Brand registration numbers absent from the registry: {missing}')
    lines = [
        '// GENERATED by tool/bank_catalog.py — do not edit by hand.',
        '// Credit organizations: Bank of Russia BIC directory ED807',
        f"// ({registry['source']}), business day {registry['businessDay']},",
        f"// archive SHA-256 {registry['archiveSha256']}.",
        '// Logo provenance: assets/banks/manifest.json, docs/BANKS.md.',
        "import 'service_catalog.dart';",
        '',
        'class RussianBank {',
        '  const RussianBank({',
        '    required this.regNumber,',
        '    required this.bics,',
        '    required this.officialName,',
        '    required this.name,',
        '    this.city = \'\',',
        '    this.aliases = const [],',
        '    this.nonBank = false,',
        '    this.logoAsset,',
        '    this.preserveColors = true,',
        '    this.background = 0xFFFFFFFF,',
        '    this.inset = .1,',
        '  });',
        '',
        '  /// Registration number in the Bank of Russia register (e.g. 1481, 3510-К).',
        '  final String regNumber;',
        '  final List<String> bics;',
        '  final String officialName, name, city;',
        '  final List<String> aliases;',
        '',
        '  /// Non-bank credit organization (НКО/РНКО), still a licensed institution.',
        '  final bool nonBank;',
        '',
        '  /// Original logo file; null means no verified original mark is bundled.',
        '  final String? logoAsset;',
        '  final bool preserveColors;',
        '  final int background;',
        '  final double inset;',
        '',
        "  String get id => 'bank_${regNumber.toLowerCase().replaceAll('к', 'k').replaceAll('ц', 'c').replaceAll(RegExp('[^0-9a-z]'), '')}';",
        "  String? get rasterAsset => logoAsset == null ? null : 'assets/banks/raster/$id.png';",
        '',
        '  SubscriptionService toService() => SubscriptionService(',
        '    id: id,',
        '    name: name,',
        "    group: 'banks',",
        '    aliases: [officialName, regNumber, ...bics, ...aliases],',
        '    assetPath: logoAsset,',
        '    rasterPath: rasterAsset,',
        '    preserveColors: preserveColors,',
        '    background: background,',
        '    inset: inset,',
        '  );',
        '}',
        '',
        'abstract final class BankCatalog {',
        f"  static const sourceUrl = {dart_string(registry['source'])};",
        f"  static const businessDay = {dart_string(registry['businessDay'])};",
        '  static const entries = <RussianBank>[',
    ]
    order = list(BRANDS)
    ranked = sorted(registry['items'], key=lambda x: (
        order.index(x['regNumber']) if x['regNumber'] in BRANDS else len(order),
        clean_name(x['officialName']).lower().replace('ё', 'е')))
    for item in ranked:
        reg = item['regNumber']
        brand = BRANDS.get(reg)
        name = brand[0] if brand else clean_name(item['officialName'])
        aliases = list(brand[1]) if brand else []
        cleaned = clean_name(item['officialName'])
        if cleaned != name and cleaned not in aliases:
            aliases.append(cleaned)
        logo = logos.get(reg)
        lines.append('    RussianBank(')
        lines.append(f'      regNumber: {dart_string(reg)},')
        lines.append(f"      bics: [{', '.join(dart_string(b) for b in item['bics'])}],")
        lines.append(f"      officialName: {dart_string(item['officialName'])},")
        lines.append(f'      name: {dart_string(name)},')
        if item.get('city'):
            lines.append(f"      city: {dart_string(item['city'])},")
        if aliases:
            lines.append(f"      aliases: [{', '.join(dart_string(a) for a in aliases)}],")
        if non_bank(reg, item['officialName']):
            lines.append('      nonBank: true,')
        if logo:
            if id_for(reg) not in rendered:
                raise SystemExit(f'Logo without PNG display copy: {reg}')
            lines.append(f"      logoAsset: {dart_string(logo['assetPath'])},")
            lines.append(f"      background: 0xFF{logo.get('background', '#FFFFFF').lstrip('#').upper()},")
            lines.append(f"      inset: {logo.get('inset', 0.1)},")
        lines.append('    ),')
    lines += ['  ];', HELPERS, '}', '']
    return '\n'.join(lines)


def validate_artwork(name, content):
    if not content or len(content) > MAX_BYTES:
        raise ValueError(f'Invalid artwork size: {name}')
    if name.endswith('.svg'):
        if b'<!ENTITY' in content.upper():
            raise ValueError(f'External XML declarations are not allowed: {name}')
        if ET.fromstring(content).tag.rsplit('}', 1)[-1] != 'svg':
            raise ValueError(f'Not SVG artwork: {name}')
    elif name.endswith('.png'):
        if not content.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError(f'Not PNG artwork: {name}')
        width, height = struct.unpack('>II', content[16:24])
        if not width or not height or width > 12000 or height > 12000:
            raise ValueError(f'Invalid image dimensions: {name}')
    else:
        raise ValueError(f'Unsupported artwork type: {name}')


def commons(title):
    query = urllib.parse.urlencode({
        'action': 'query', 'titles': 'File:' + title, 'prop': 'imageinfo', 'format': 'json',
        'iiprop': 'url|mime|size|sha1|extmetadata|timestamp'})
    for attempt in range(8):
        try:
            time.sleep(4)
            with urllib.request.urlopen(urllib.request.Request(
                    'https://commons.wikimedia.org/w/api.php?' + query, headers=UA), timeout=60) as r:
                page = next(iter(json.load(r)['query']['pages'].values()))
                return page['imageinfo'][0]
        except urllib.error.HTTPError as error:
            if error.code != 429:
                raise
            time.sleep(30 * (attempt + 1))
    raise SystemExit('Commons rate limit')


def download(url):
    for attempt in range(8):
        try:
            time.sleep(3)
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                if urllib.parse.urlparse(r.url).scheme != 'https':
                    raise ValueError('Artwork redirected outside HTTPS')
                return r.read(MAX_BYTES + 1)
        except urllib.error.HTTPError as error:
            if error.code != 429:
                raise
            time.sleep(30 * (attempt + 1))
    raise SystemExit('Download rate limit')


def fetch_logos():
    ASSETS.mkdir(parents=True, exist_ok=True)
    items = []
    for reg, spec in LOGOS.items():
        info = commons(spec['title'])
        content = download(info['url'])
        if hashlib.sha1(content).hexdigest() != info['sha1']:
            raise SystemExit(f'Commons SHA-1 mismatch: {reg}')
        suffix = Path(urllib.parse.urlparse(info['url']).path).suffix.lower()
        path = ASSETS / f'{id_for(reg)}{suffix}'
        validate_artwork(path.name, content)
        path.write_bytes(content)
        meta = {k: v.get('value') for k, v in info.get('extmetadata', {}).items() if k in (
            'ImageDescription', 'Credit', 'Artist', 'LicenseShortName', 'UsageTerms',
            'AttributionRequired', 'Copyrighted', 'LicenseUrl', 'DateTimeOriginal')}
        items.append({
            'regNumber': reg, 'id': id_for(reg), 'brand': BRANDS[reg][0],
            'assetPath': str(path.relative_to(ROOT)), 'sourceType': 'wikimedia-commons',
            'source': info['descriptionurl'], 'downloadUrl': info['url'], 'mime': info['mime'],
            'bytes': len(content), 'width': info.get('width'), 'height': info.get('height'),
            'sha256': digest(content), 'commonsSha1': info['sha1'], 'commonsTimestamp': info['timestamp'],
            'license': meta, 'background': spec.get('background', '#FFFFFF'), 'inset': spec.get('inset', 0.1),
            'selection': spec['why'],
            'rights': 'Original file bytes from Wikimedia Commons with the license stated there. '
                      'Trademark rights remain with the bank; no endorsement is implied.',
        })
    MANIFEST.write_text(json.dumps({'items': items}, ensure_ascii=False, indent=1) + '\n')
    print(f'Fetched {len(items)} original bank logos')


def render_svg(source, temp):
    document = ET.fromstring(source.read_bytes())
    viewbox = [float(x) for x in re.split(r'[ ,]+', document.get('viewBox', '').strip()) if x]

    def dimension(value):
        match = re.fullmatch(r'([0-9.]+)(?:px)?', value or '')
        return float(match[1]) if match else None
    width, height = dimension(document.get('width')), dimension(document.get('height'))
    if width is None or height is None:
        if len(viewbox) != 4 or min(viewbox[2:]) <= 0:
            raise ValueError(f'Missing bounded SVG page: {source.name}')
        width, height = viewbox[2:]
    pixels = max(1, round((SIZE - 2 * GUTTER) * width / max(width, height)))
    result = subprocess.run(['inkscape', str(source), '--export-type=png', '--export-area-page',
                             f'--export-filename={temp}', f'--export-width={pixels}'],
                            capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'Inkscape failed for {source.name}: {result.stderr[-400:]}')
    from PIL import Image
    return Image.open(temp).convert('RGBA')


def render():
    from PIL import Image
    if not shutil.which('inkscape'):
        raise SystemExit('Inkscape is required for --render')
    manifest = json.loads(MANIFEST.read_text())
    RASTER.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory(prefix='finance-bank-raster-') as scratch:
        for item in manifest['items']:
            source = ROOT / item['assetPath']
            raw = source.read_bytes()
            if digest(raw) != item['sha256']:
                raise SystemExit(f'Original SHA mismatch: {item["id"]}')
            if source.suffix == '.svg':
                image = render_svg(source, Path(scratch) / 'render.png')
                operation = 'Inkscape SVG page rendered proportionally with transparent gutter; original colors unchanged'
            else:
                image = Image.open(io.BytesIO(raw)).convert('RGBA')
                image.thumbnail((SIZE - 2 * GUTTER, SIZE - 2 * GUTTER), Image.Resampling.LANCZOS)
                operation = 'Original PNG proportionally downscaled (Lanczos) into transparent canvas; colors unchanged'
            square = Image.new('RGBA', (SIZE, SIZE))
            square.alpha_composite(image, ((SIZE - image.width) // 2, (SIZE - image.height) // 2))
            out = io.BytesIO()
            square.save(out, format='PNG', optimize=True)
            data = out.getvalue()
            target = RASTER / f'{item["id"]}.png'
            target.write_bytes(data)
            records.append({'id': item['id'], 'regNumber': item['regNumber'],
                            'assetPath': str(target.relative_to(ROOT)), 'sourceAssetPath': item['assetPath'],
                            'sourceSha256': item['sha256'], 'sha256': digest(data), 'bytes': len(data),
                            'width': SIZE, 'height': SIZE, 'operation': operation})
    renderer = subprocess.check_output(['inkscape', '--version'], text=True, stderr=subprocess.DEVNULL).strip()
    RASTER_MANIFEST.write_text(json.dumps({
        'renderer': renderer, 'sourceManifestSha256': digest(MANIFEST.read_bytes()),
        'canvas': SIZE, 'gutter': GUTTER, 'items': records}, ensure_ascii=False, indent=1) + '\n')
    print(f'Rendered {len(records)} PNG display copies')


def verify():
    from PIL import Image
    registry = json.loads(REGISTRY.read_text())
    manifest = json.loads(MANIFEST.read_text())
    raster = json.loads(RASTER_MANIFEST.read_text())
    assert registry['count'] == len(registry['items']) > 300, 'registry too small'
    regs = [x['regNumber'] for x in registry['items']]
    assert len(regs) == len(set(regs)), 'duplicate registration numbers'
    bics = [b for x in registry['items'] for b in x['bics']]
    assert len(bics) == len(set(bics)) and all(re.fullmatch(r'\d{9}', b) for b in bics), 'bad BIC'
    assert raster['sourceManifestSha256'] == digest(MANIFEST.read_bytes()), 'raster manifest is stale'
    rendered = {x['id']: x for x in raster['items']}
    assert set(rendered) == {x['id'] for x in manifest['items']}, 'logo/PNG sets differ'
    for item in manifest['items']:
        assert item['regNumber'] in regs, f'logo for unknown bank {item["regNumber"]}'
        assert item['downloadUrl'].startswith('https://upload.wikimedia.org/'), item['id']
        assert item.get('license', {}).get('LicenseShortName'), f'missing license {item["id"]}'
        raw = (ROOT / item['assetPath']).read_bytes()
        validate_artwork(item['assetPath'], raw)
        assert digest(raw) == item['sha256'], f'original SHA mismatch {item["id"]}'
        png = rendered[item['id']]
        assert png['sourceSha256'] == item['sha256']
        data = (ROOT / png['assetPath']).read_bytes()
        assert digest(data) == png['sha256'], f'PNG SHA mismatch {item["id"]}'
        image = Image.open(io.BytesIO(data)).convert('RGBA')
        assert image.size == (SIZE, SIZE)
        assert image.getchannel('A').getextrema()[1] > 0, f'invisible PNG {item["id"]}'
    expected = generate_dart(registry, manifest, raster)

    def canonical(text):  # dart format only moves whitespace and commas
        return re.sub(r'[\s,]', '', text)
    if canonical(DART.read_text()) != canonical(expected):
        raise SystemExit('lib/domain/bank_catalog.dart differs from tool output; run --build')
    print(f'Verified {len(regs)} credit organizations ({len(bics)} BIC), '
          f'{len(manifest["items"])} original logos and PNG display copies')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--build', metavar='ED807_ZIP')
    mode.add_argument('--fetch-logos', action='store_true')
    mode.add_argument('--render', action='store_true')
    mode.add_argument('--generate', action='store_true', help='rewrite Dart from recorded JSON')
    mode.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if args.build:
        registry = parse_ed807(args.build)
        ASSETS.mkdir(parents=True, exist_ok=True)
        REGISTRY.write_text(json.dumps(registry, ensure_ascii=False, indent=1) + '\n')
        args.generate = True
    if args.fetch_logos:
        fetch_logos()
    if args.render:
        render()
    if args.generate:
        manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {'items': []}
        raster = json.loads(RASTER_MANIFEST.read_text()) if RASTER_MANIFEST.exists() else {'items': []}
        DART.write_text(generate_dart(json.loads(REGISTRY.read_text()), manifest, raster))
        if shutil.which('dart'):
            subprocess.run(['dart', 'format', str(DART)], check=True, capture_output=True)
        print(f'Generated {DART.relative_to(ROOT)}')
    if args.verify:
        verify()


if __name__ == '__main__':
    sys.exit(main())
