#!/usr/bin/env python3
"""Build/verify the offline catalog of Russian stores and everyday services.

Every logo is the icon the brand's own website publishes (apple-touch-icon /
site icon). Many Russian sites cannot be reached from the build host (TLS by
a Russian CA, bot protection), so the file is taken from a public favicon
mirror that serves exactly that site icon: Google's favicon service first,
Yandex's as a fallback. The mirror URL, the brand's site, the SHA-256 and the
date are recorded per logo.

Each fetched icon is reviewed by eye. A brand stays in the catalog only with
an icon that is its current mark; rejected brands are listed in REJECTED
with the reason and get no logo (nothing is drawn or guessed).

Modes (network is developer-only and opt-in):
  --fetch      download candidates into assets/stores/ and record them
  --sheet PNG  contact sheet of fetched icons for the visual review
  --render     rebuild display copies from the originals (shape, no network)
  --generate   write lib/domain/store_catalog.dart from the manifest
  --verify     offline: files, display copies and Dart agree with the manifest
"""
import argparse
import datetime
import hashlib
import io
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import logo_shape  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/stores'
RASTER = ASSETS / 'raster'
MANIFEST = ASSETS / 'manifest.json'
DART = ROOT / 'lib/domain/store_catalog.dart'
MAX_BYTES = 2 * 1024 * 1024
MIN_SIDE = 96
UA = {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36'}

GROUPS = {
    'groceries': 'Продукты и супермаркеты',
    'food': 'Кафе, рестораны и доставка еды',
    'shops': 'Маркетплейсы и магазины',
    'beauty': 'Красота и одежда',
    'pharmacy': 'Аптеки и здоровье',
    'transport': 'Такси, самокаты и каршеринг',
    'travel': 'Транспорт и путешествия',
    'fuel': 'АЗС',
    'services': 'Сервисы и доставка',
}

# id: (name, group, site domain, aliases). Aliases are how the payee shows up
# in bank statements and how people type it; matching ignores case, «ё»,
# punctuation and a trailing store number/address.
BRANDS = {
    # Продукты
    'pyaterochka': ('Пятёрочка', 'groceries', '5ka.ru', ['Пятерочка', 'Pyaterochka', '5ka', 'Пятёрочка Доставка']),
    'magnit': ('Магнит', 'groceries', 'magnit.ru', ['Magnit', 'Магнит у дома', 'Магнит Экстра', 'Магнит Семейный', 'Магнит Косметик', 'MAGNIT MM', 'MM MAGNIT']),
    'perekrestok': ('Перекрёсток', 'groceries', 'perekrestok.ru', ['Перекресток', 'Perekrestok', 'Перекрёсток Впрок']),
    'vkusvill': ('ВкусВилл', 'groceries', 'vkusvill.ru', ['Вкус Вилл', 'Vkusvill']),
    'lenta': ('Лента', 'groceries', 'lenta.com', ['Lenta', 'Лента Онлайн', 'Супер Лента']),
    'auchan': ('Ашан', 'groceries', 'auchan.ru', ['Auchan', 'Атак']),
    'dixy': ('Дикси', 'groceries', 'dixy.ru', ['Dixy']),
    'metro_cc': ('METRO', 'groceries', 'online.metro-cc.ru', ['Метро Кэш энд Керри', 'METRO Cash & Carry', 'Metro CC']),
    'spar': ('SPAR', 'groceries', 'spar.ru', ['Спар', 'Eurospar', 'Евроспар']),
    'okey': ('О’КЕЙ', 'groceries', 'okmarket.ru', ['Окей', 'OKEY', 'О кей', "О'КЕЙ"]),
    'fixprice': ('Fix Price', 'groceries', 'fix-price.com', ['Фикс Прайс', 'Fixprice']),
    'samokat': ('Самокат', 'groceries', 'samokat.ru', ['Samokat']),
    'yandex_lavka': ('Яндекс Лавка', 'groceries', 'lavka.yandex.ru', ['Yandex Lavka']),
    'kuper': ('Купер', 'groceries', 'kuper.ru', ['Kuper', 'СберМаркет', 'Sbermarket']),
    'chizhik': ('Чижик', 'groceries', 'chizhik.club', ['Chizhik']),
    'miratorg': ('Мираторг', 'groceries', 'miratorg.ru', ['Miratorg']),
    'azbuka_vkusa': ('Азбука вкуса', 'groceries', 'av.ru', ['Азбука Вкуса', 'AV Daily']),
    'globus': ('Глобус', 'groceries', 'globus.ru', ['Globus']),
    'verny': ('Верный', 'groceries', 'verno-info.ru', ['Verny']),
    'krasnoe_beloe': ('Красное&Белое', 'groceries', 'krasnoeibeloe.ru', ['Красное и Белое', 'KRASNOE&BELOE', 'Krasnoe Beloe']),
    'bristol': ('Бристоль', 'groceries', 'bristol.ru', ['Bristol']),
    'monetka': ('Монетка', 'groceries', 'monetka.ru', ['Monetka']),
    'maria_ra': ('Мария-Ра', 'groceries', 'maria-ra.ru', ['Мария Ра', 'Maria-Ra']),
    'svetofor': ('Светофор', 'groceries', 'svetoforonline.ru', ['Svetofor']),
    # Еда
    'vkusno_i_tochka': ('Вкусно — и точка', 'food', 'vkusnoitochka.ru', ['Вкусно и точка', 'Вкусно и Точка', 'Vkusno i tochka']),
    'rostics': ('Rostic’s', 'food', 'rostics.ru', ['Ростикс', "Rostic's", 'Rostics', 'KFC']),
    'burger_king': ('Бургер Кинг', 'food', 'burgerkingrus.ru', ['Burger King']),
    'dodo': ('Додо Пицца', 'food', 'dodopizza.ru', ['Dodo Pizza', 'Додо']),
    'teremok': ('Теремок', 'food', 'teremok.ru', ['Teremok']),
    'shokoladnitsa': ('Шоколадница', 'food', 'shoko.ru', ['Shokoladnitsa']),
    'cofix': ('Cofix', 'food', 'cofix.ru', ['Кофикс']),
    'coffee_like': ('Coffee Like', 'food', 'coffee-like.com', ['Кофе Лайк', 'Coffeelike']),
    'stars_coffee': ('Stars Coffee', 'food', 'stars-coffee.ru', ['Старс Кофе']),
    'coffeemania': ('Кофемания', 'food', 'coffeemania.ru', ['Coffeemania']),
    'yandex_eda': ('Яндекс Еда', 'food', 'eda.yandex.ru', ['Yandex Eda', 'Яндекс.Еда']),
    'tanuki': ('Тануки', 'food', 'tanuki.ru', ['Tanuki']),
    'yakitoriya': ('Якитория', 'food', 'yakitoriya.ru', ['Yakitoriya']),
    'papa_johns': ('Папа Джонс', 'food', 'papajohns.ru', ['Papa Johns', "Papa John's"]),
    # Маркетплейсы и магазины
    'wildberries': ('Wildberries', 'shops', 'wildberries.ru', ['Вайлдберриз', 'Валдберис', 'WB']),
    'ozon': ('Ozon', 'shops', 'ozon.ru', ['Озон', 'OZON.RU']),
    'yandex_market': ('Яндекс Маркет', 'shops', 'market.yandex.ru', ['Yandex Market', 'Яндекс.Маркет']),
    'megamarket': ('Мегамаркет', 'shops', 'megamarket.ru', ['Megamarket']),
    'aliexpress': ('AliExpress', 'shops', 'aliexpress.ru', ['Алиэкспресс']),
    'avito': ('Авито', 'shops', 'avito.ru', ['Avito']),
    'lamoda': ('Lamoda', 'shops', 'lamoda.ru', ['Ламода']),
    'mvideo': ('М.Видео', 'shops', 'mvideo.ru', ['МВидео', 'M.Video', 'Mvideo']),
    'eldorado': ('Эльдорадо', 'shops', 'eldorado.ru', ['Eldorado']),
    'dns': ('DNS', 'shops', 'dns-shop.ru', ['ДНС', 'DNS Shop']),
    'citilink': ('Ситилинк', 'shops', 'citilink.ru', ['Citilink']),
    'lemana_pro': ('Лемана ПРО', 'shops', 'lemanapro.ru', ['Леруа Мерлен', 'Leroy Merlin', 'Лемана Про', 'Lemana Pro']),
    'obi': ('OBI', 'shops', 'obi.ru', ['Оби']),
    'petrovich': ('Петрович', 'shops', 'petrovich.ru', ['Petrovich']),
    'hoff': ('Hoff', 'shops', 'hoff.ru', ['Хофф']),
    'detmir': ('Детский мир', 'shops', 'detmir.ru', ['Детмир', 'Detmir']),
    'sportmaster': ('Спортмастер', 'shops', 'sportmaster.ru', ['Sportmaster']),
    'chitai_gorod': ('Читай-город', 'shops', 'chitai-gorod.ru', ['Читай город', 'Chitai-gorod']),
    'familia': ('Familia', 'shops', 'famil.ru', ['Фамилия']),
    # Красота и одежда
    'goldapple': ('Золотое Яблоко', 'beauty', 'goldapple.ru', ['Золотое яблоко', 'Goldapple', 'Gold Apple']),
    'letu': ('Л’Этуаль', 'beauty', 'letu.ru', ['Летуаль', "Л'Этуаль", 'Letual']),
    'rivegauche': ('Рив Гош', 'beauty', 'rivegauche.ru', ['Rive Gauche']),
    'podruzhka': ('Подружка', 'beauty', 'podrygka.ru', ['Podruzhka']),
    'ulybka_radugi': ('Улыбка радуги', 'beauty', 'r-ulybka.ru', ['Улыбка Радуги']),
    'gloria_jeans': ('Gloria Jeans', 'beauty', 'gloria-jeans.ru', ['Глория Джинс']),
    # Аптеки и здоровье
    'rigla': ('Ригла', 'pharmacy', 'rigla.ru', ['Rigla']),
    'gorzdrav': ('Горздрав', 'pharmacy', 'gorzdrav.org', ['Gorzdrav']),
    'apteka_366': ('Аптека 36,6', 'pharmacy', '366.ru', ['36,6', '36.6', 'Аптеки 36,6']),
    'apteka_april': ('Аптека Апрель', 'pharmacy', 'apteka-april.ru', ['Апрель']),
    'eapteka': ('ЕАПТЕКА', 'pharmacy', 'eapteka.ru', ['Еаптека', 'eApteka']),
    'zdravcity': ('Здравсити', 'pharmacy', 'zdravcity.ru', ['Zdravcity']),
    'apteka_ru': ('Аптека.ру', 'pharmacy', 'apteka.ru', ['Apteka.ru']),
    'planeta_zdorovya': ('Планета Здоровья', 'pharmacy', 'planetazdorovo.ru', ['Планета здоровья']),
    'stolichki': ('Столички', 'pharmacy', 'stolichki.ru', ['Stolichki']),
    'invitro': ('Инвитро', 'pharmacy', 'invitro.ru', ['Invitro']),
    'gemotest': ('Гемотест', 'pharmacy', 'gemotest.ru', ['Gemotest']),
    'sberzdorovie': ('СберЗдоровье', 'pharmacy', 'sberhealth.ru', ['Сбер Здоровье', 'SberHealth']),
    # Такси, самокаты, каршеринг
    'whoosh': ('Whoosh', 'transport', 'whoosh-bike.ru', ['Вуш', 'Woosh', 'Whoosh самокаты']),
    'urent': ('Юрент', 'transport', 'urent.ru', ['Urent', 'МТС Юрент']),
    'yandex_go': ('Яндекс Go', 'transport', 'go.yandex', ['Яндекс Такси', 'Yandex Go', 'Yandex Taxi', 'Yandex.Taxi', 'Яндекс Самокаты']),
    'citydrive': ('Ситидрайв', 'transport', 'citydrive.ru', ['Citydrive']),
    'delimobil': ('Делимобиль', 'transport', 'delimobil.ru', ['Delimobil']),
    'belkacar': ('BelkaCar', 'transport', 'belkacar.ru', ['Белка Кар', 'Белкакар']),
    'yandex_drive': ('Яндекс Драйв', 'transport', 'drive.yandex.ru', ['Yandex Drive']),
    'taxi_maxim': ('Такси Максим', 'transport', 'taximaxim.ru', ['Maxim']),
    'indrive': ('inDrive', 'transport', 'indrive.com', ['Индрайв', 'inDriver']),
    # Транспорт и путешествия
    'mosmetro': ('Московское метро', 'travel', 'mosmetro.ru', ['Метро Москвы', 'Московский метрополитен', 'Mosmetro']),
    'rzd': ('РЖД', 'travel', 'rzd.ru', ['Российские железные дороги', 'RZD']),
    'aeroflot': ('Аэрофлот', 'travel', 'aeroflot.ru', ['Aeroflot']),
    's7': ('S7 Airlines', 'travel', 's7.ru', ['S7']),
    'pobeda': ('Победа', 'travel', 'pobeda.aero', ['Pobeda']),
    'ural_airlines': ('Уральские авиалинии', 'travel', 'uralairlines.ru', ['Ural Airlines']),
    'tutu': ('Туту', 'travel', 'tutu.ru', ['Tutu.ru', 'Туту.ру']),
    'aeroexpress': ('Аэроэкспресс', 'travel', 'aeroexpress.ru', ['Aeroexpress']),
    'yandex_travel': ('Яндекс Путешествия', 'travel', 'travel.yandex.ru', ['Yandex Travel']),
    'ostrovok': ('Островок', 'travel', 'ostrovok.ru', ['Ostrovok']),
    'aviasales': ('Авиасейлс', 'travel', 'aviasales.ru', ['Aviasales']),
    # АЗС
    'lukoil': ('Лукойл', 'fuel', 'lukoil.ru', ['Lukoil', 'ЛУКОЙЛ']),
    'rosneft': ('Роснефть', 'fuel', 'rosneft-azs.ru', ['Rosneft']),
    'gazpromneft': ('Газпромнефть', 'fuel', 'gpnbonus.ru', ['Газпром нефть', 'Gazpromneft', 'ГПН']),
    'tatneft': ('Татнефть', 'fuel', 'tatneft.ru', ['Tatneft']),
    # Сервисы и доставка
    'gosuslugi': ('Госуслуги', 'services', 'gosuslugi.ru', ['Gosuslugi']),
    'pochta': ('Почта России', 'services', 'pochta.ru', ['Russian Post']),
    'cdek': ('СДЭК', 'services', 'cdek.ru', ['CDEK']),
    'boxberry': ('Boxberry', 'services', 'boxberry.ru', ['Боксберри']),
    'cian': ('ЦИАН', 'services', 'cian.ru', ['Cian']),
    'profi': ('Профи', 'services', 'profi.ru', ['Profi.ru']),
    'world_class': ('World Class', 'services', 'worldclass.ru', ['Ворлд Класс']),
    'ddx': ('DDX Fitness', 'services', 'ddxfitness.ru', ['DDX']),
    'karo': ('КАРО', 'services', 'karofilm.ru', ['KARO', 'Каро Фильм']),
}

# Icons taken straight from the official site (it serves a large icon the
# favicon mirrors do not pick up): id → icon URL.
OFFICIAL = {
    'miratorg': 'https://miratorg.ru/favicon-114x114.png',
}

# Reviewed by eye on the contact sheet and refused: id → reason. These brands
# keep the category icon; nothing is drawn or upscaled for them.
REJECTED = {
    'metro_cc': 'Only a tiny favicon exists; the 256 px rendition is a pixelated upscale.',
    'spar': 'Mirror returned an unrelated, damaged picture.',
    'svetofor': 'Official site of the chain not confirmed; icon is a generic traffic light.',
    'verny': 'Site publishes only a 16 px favicon; the 120 px copy is a blurry upscale.',
    'stars_coffee': 'Site publishes only a 16 px favicon; the 120 px copy is a blurry upscale.',
    'eldorado': 'Site publishes only a 48 px favicon; the 120 px copy is blurry.',
    'taxi_maxim': 'No large site icon; the 120 px copy is a blurry upscale.',
    'lukoil': 'Site publishes only a 16 px favicon; the 120 px copy is a blurry upscale.',
    'tatneft': 'No large site icon reachable; the 120 px copy is a blurry upscale.',
    'gosuslugi': 'No large site icon reachable; the 120 px copy is a blurry upscale.',
    'sberzdorovie': 'Site publishes only a 32 px favicon; the 120 px copy is blurry.',
    'obi': 'obi.ru serves the «ДОМ Лента» icon; the brand change is not verified.',
    'boxberry': 'boxberry.ru now redirects to Yandex Delivery; its icon is not Boxberry\'s.',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def get(url):
    for attempt in range(4):
        try:
            time.sleep(.6)
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40) as r:
                if urllib.parse.urlparse(r.url).scheme != 'https':
                    raise ValueError('redirected outside HTTPS')
                return r.read(MAX_BYTES + 1)
        except urllib.error.HTTPError as error:
            if error.code in (404, 400):
                return None
            time.sleep(3 * (attempt + 1))
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            time.sleep(3 * (attempt + 1))
    return None


def mirrors(domain):
    site = f'https://{domain}'
    return [
        ('google-favicon-service', 'https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON'
         '&fallback_opts=TYPE,SIZE,URL&url=' + urllib.parse.quote(site, safe='') + '&size=256'),
        ('yandex-favicon-service', f'https://favicon.yandex.net/favicon/v2/{domain}?size=120&stub=0'),
    ]


def as_png(content):
    """Display copy: the decoded icon in its own outline (round marks cut to
    the mark, see logo_shape), losslessly encoded as RGBA PNG, plus its shape."""
    image = Image.open(io.BytesIO(content))
    image.load()
    if min(image.size) < MIN_SIDE:
        return None
    shape, shown, backing = logo_shape.analyze(image)
    out = io.BytesIO()
    shown.convert('RGBA').save(out, 'PNG', optimize=True)
    return out.getvalue(), image.size, shape, backing


def corner_color(image):
    px = image.convert('RGBA').getpixel((2, 2))
    if px[3] < 200:
        return '#FFFFFF'
    return '#%02X%02X%02X' % px[:3]


def fetch():
    ASSETS.mkdir(parents=True, exist_ok=True)
    RASTER.mkdir(parents=True, exist_ok=True)
    items, missing = [], []
    for bid, (name, group, domain, aliases) in BRANDS.items():
        record = None
        sources = [('official-website', OFFICIAL[bid])] if bid in OFFICIAL else []
        for source, url in sources + mirrors(domain):
            content = get(url)
            if not content or len(content) > MAX_BYTES:
                continue
            try:
                converted = as_png(content)
            except Exception:
                converted = None
            if not converted:
                continue
            png, size, shape, backing = converted
            kind = {'PNG': 'png', 'JPEG': 'jpg', 'ICO': 'ico', 'WEBP': 'webp', 'GIF': 'gif'}.get(
                Image.open(io.BytesIO(content)).format, 'bin')
            original = ASSETS / f'{bid}.{kind}'
            original.write_bytes(content)
            (RASTER / f'{bid}.png').write_bytes(png)
            image = Image.open(io.BytesIO(png))
            record = {
                'id': bid, 'name': name, 'group': group, 'site': f'https://{domain}/',
                'sourceType': source, 'downloadUrl': url,
                'fetched': datetime.date.today().isoformat(),
                'originalPath': str(original.relative_to(ROOT)), 'originalSha256': digest(content),
                'originalBytes': len(content), 'size': list(size),
                'rasterPath': str((RASTER / f'{bid}.png').relative_to(ROOT)), 'rasterSha256': digest(png),
                'background': corner_color(image),
                'shape': shape, 'backing': bool(backing),
                'rights': 'Site icon published by the brand\'s official website, as served by a public '
                          'favicon mirror. Copyright and trademark belong to the brand owner; used only '
                          'to identify the payee; no endorsement implied.',
            }
            break
        if record:
            items.append(record)
            print(f'ok   {bid:18} {record["size"]} {record["sourceType"]}')
        else:
            missing.append(bid)
            print(f'MISS {bid:18} {domain}')
    MANIFEST.write_text(json.dumps({'items': items, 'missing': missing}, ensure_ascii=False, indent=1) + '\n')
    prune()
    print(f'{len(items)} fetched, {len(missing)} missing')


def prune():
    """Rejected brands keep their reviewed original for the record but ship no
    display copy."""
    data = json.loads(MANIFEST.read_text())
    for item in data['items']:
        if item['id'] in REJECTED and item.get('rasterPath'):
            (ROOT / item['rasterPath']).unlink(missing_ok=True)
            item['rasterPath'] = item['rasterSha256'] = None
            item['rejected'] = REJECTED[item['id']]
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n')


def sheet(path):
    items = json.loads(MANIFEST.read_text())['items']
    cell, cols = 150, 8
    rows = (len(items) + cols - 1) // cols
    from PIL import ImageDraw
    out = Image.new('RGBA', (cell * cols, cell * rows), (210, 210, 210, 255))
    draw = ImageDraw.Draw(out)
    for i, item in enumerate(items):
        im = Image.open(ROOT / item['rasterPath']).convert('RGBA').resize((112, 112), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * cell
        out.alpha_composite(im, (x + 19, y + 4))
        draw.text((x + 4, y + 120), f"{i}:{item['id']}"[:24], fill=(0, 0, 0, 255))
    out.save(path)


def render():
    """Rebuild display copies from the recorded originals (no network)."""
    data = json.loads(MANIFEST.read_text())
    for item in data['items']:
        content = (ROOT / item['originalPath']).read_bytes()
        if digest(content) != item['originalSha256']:
            raise SystemExit(f'{item["originalPath"]} differs from manifest')
        png, _, shape, backing = as_png(content)
        item.update({'shape': shape, 'backing': bool(backing)})
        if item['id'] in REJECTED:
            continue
        (ROOT / item['rasterPath']).write_bytes(png)
        item['rasterSha256'] = digest(png)
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n')
    print(f'Rendered {len(accepted())} display copies')


def accepted():
    items = json.loads(MANIFEST.read_text())['items']
    return [i for i in items if i['id'] not in REJECTED]


def dart_string(value):
    return json.dumps(value, ensure_ascii=False)


def dart_source():
    lines = [
        '// GENERATED by tool/store_catalog.py — do not edit by hand.',
        '// Russian stores and everyday services with their site icons.',
        '// Provenance: assets/stores/manifest.json, docs/STORES.md.',
        "import 'service_catalog.dart';",
        '',
        'abstract final class StoreCatalog {',
        '  static const groups = <String, String>{',
    ]
    lines += [f'    {dart_string(k)}: {dart_string(v)},' for k, v in GROUPS.items()]
    lines += ['  };', '', '  static const entries = <SubscriptionService>[']
    for item in accepted():
        name, group, domain, aliases = BRANDS[item['id']]
        shape = item.get('shape', 'tile')
        if shape == 'tile':
            background, inset = '0xFF' + item['background'].lstrip('#'), .1
        else:
            # Round and square marks show in their own outline with nothing
            # behind them; a see-through round mark keeps a white disc.
            background = '0xFFFFFFFF' if shape == 'round' and item.get('backing') else '0x00FFFFFF'
            inset = 0
        lines += [
            '    SubscriptionService(',
            f'      id: {dart_string("store_" + item["id"])},',
            f'      name: {dart_string(name)},',
            f'      group: {dart_string(group)},',
            f'      aliases: [{", ".join(dart_string(a) for a in aliases)}],',
            f'      assetPath: {dart_string(item["rasterPath"])},',
            f'      rasterPath: {dart_string(item["rasterPath"])},',
            '      preserveColors: true,',
            f'      background: {background},',
            f'      inset: {inset},',
            f'      shape: {dart_string(shape)},',
            '    ),',
        ]
    lines += ['  ];', '}', '']
    return '\n'.join(lines)


def generate():
    DART.write_text(dart_source())
    print(f'Wrote {DART.relative_to(ROOT)} with {len(accepted())} stores')


def verify():
    data = json.loads(MANIFEST.read_text())
    for item in data['items']:
        for key, sha in (('originalPath', 'originalSha256'), ('rasterPath', 'rasterSha256')):
            if item[key] is None:
                if item['id'] not in REJECTED:
                    raise SystemExit(f'{item["id"]} has no {key}')
                continue
            path = ROOT / item[key]
            if digest(path.read_bytes()) != item[sha]:
                raise SystemExit(f'{path} differs from manifest')
        if item['id'] not in BRANDS:
            raise SystemExit(f'unknown brand {item["id"]}')
    for rejected in REJECTED:
        if not any(i['id'] == rejected for i in data['items']):
            raise SystemExit(f'rejected id not fetched: {rejected}')
    shipped = {p.name for p in RASTER.glob('*.png')}
    expected = {f'{i["id"]}.png' for i in accepted()}
    if shipped != expected:
        raise SystemExit(f'display copies differ from accepted brands: {sorted(shipped ^ expected)}')

    def canonical(text):  # dart format only moves whitespace and commas
        return ''.join(ch for ch in text if not ch.isspace() and ch != ',')
    if canonical(DART.read_text()) != canonical(dart_source()):
        raise SystemExit('lib/domain/store_catalog.dart differs from tool output; run --generate')
    print(f'OK: {len(accepted())} store logos, {len(REJECTED)} rejected, '
          f'{len(data["missing"])} not available')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--fetch', action='store_true')
    mode.add_argument('--sheet', metavar='PNG')
    mode.add_argument('--render', action='store_true')
    mode.add_argument('--generate', action='store_true')
    mode.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if args.fetch:
        fetch()
    elif args.sheet:
        sheet(args.sheet)
    elif args.render:
        render()
    elif args.generate:
        generate()
    else:
        verify()


if __name__ == '__main__':
    sys.exit(main())
