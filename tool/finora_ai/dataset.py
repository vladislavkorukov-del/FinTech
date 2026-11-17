"""Dataset for the Finora transaction classifier.

Format (CSV, UTF-8, header row):

    merchant,description,amount_minor,kind,account_type,date,label

    merchant      payee as the bank or the person wrote it («MAGNIT MM KOSTROMA»)
    description   optional free text / note
    amount_minor  amount in kopecks, positive
    kind          expense | income
    account_type  card | cash | savings | credit | '' (unknown)
    date          YYYY-MM-DD
    label         canonical class, one of CLASSES

The first model is trained on a synthetic set built from the app's own store
and service catalogs plus hand-written seeds for classes the catalogs do not
cover, with bank-statement style noise. Real labelled data (exported from
consenting users, or a curated set) can be added with --extra file.csv.
"""

from __future__ import annotations

import csv
import random
import re
from datetime import date, timedelta
from pathlib import Path

from features import TransactionInput

ROOT = Path(__file__).resolve().parents[2]

CLASSES = [
    # expenses
    "groceries", "cafe", "transport", "car", "housing", "utilities",
    "health", "pharmacy", "entertainment", "subscriptions", "shopping",
    "clothes", "gifts", "travel", "education", "kids", "pets", "taxes",
    "loans", "other",
    # incomes
    "salary", "side_job", "business", "interest", "investments", "refunds",
    "gifts_in", "other_in",
]
INCOME = set(CLASSES[20:])

# Catalog groups → class.
STORE_GROUPS = {
    "groceries": "groceries", "food": "cafe", "shops": "shopping",
    "beauty": "clothes", "pharmacy": "pharmacy", "transport": "transport",
    "travel": "travel", "fuel": "car", "services": "shopping",
}
SERVICE_GROUPS = {
    "video": "subscriptions", "music": "subscriptions",
    "reading": "subscriptions", "ai": "subscriptions",
    "cloud": "subscriptions", "design": "subscriptions",
    "development": "subscriptions", "productivity": "subscriptions",
    "security": "subscriptions", "other": "subscriptions",
    "games": "entertainment", "education": "education",
    "telecom": "utilities",
}

# Classes the catalogs do not cover: realistic payee / description seeds.
SEEDS = {
    "housing": ["Аренда квартиры", "Оплата аренды", "Ипотека Сбербанк",
                "ПИК Комфорт", "Самолет Плюс аренда", "Циан аренда",
                "ТСЖ Вымпел", "Квартплата"],
    "utilities": ["ЖКХ оплата", "Мосэнергосбыт", "Мосводоканал",
                  "Газпром межрегионгаз", "ЕИРЦ", "Ростелеком", "Билайн",
                  "МТС оплата связи", "МегаФон", "Tele2", "Дом.ру"],
    "health": ["Клиника Медси", "Стоматология Улыбка", "Инвитро",
               "Гемотест", "СМ-Клиника", "Поликлиника платные услуги",
               "Доктор рядом", "Медицинский центр"],
    "entertainment": ["Кинотеатр Синема Парк", "Каро Фильм", "Яндекс Афиша",
                      "Боулинг", "Квест", "Концерт Kassir", "Театр",
                      "Парк аттракционов", "Steam", "PlayStation Store"],
    "gifts": ["Цветы Флорист", "Подарок маме", "Букет", "Сувениры",
              "Подарочный сертификат"],
    "education": ["Skyeng", "Нетология", "Яндекс Практикум", "Курсы английского",
                  "Учебный центр", "Репетитор", "Онлайн школа"],
    "kids": ["Детский мир", "Кораблик", "Детский сад", "Игрушки",
             "Секция для ребенка", "Лабиринт детские книги"],
    "pets": ["Четыре лапы", "Бетховен зоомагазин", "Ветклиника", "Зоомагазин",
             "Корм для кошки", "Petshop"],
    "taxes": ["ФНС налог", "Госуслуги налог", "Налог на имущество",
              "Транспортный налог", "НДФЛ"],
    "loans": ["Погашение кредита", "Платеж по кредиту", "Тинькофф кредит",
              "Альфа кредитная карта погашение", "Займ", "Рассрочка"],
    "car": ["Лукойл АЗС", "Газпромнефть АЗС", "Роснефть", "Шиномонтаж",
            "Автомойка", "Парковка", "ОСАГО", "Автосервис"],
    "other": ["Перевод другу", "Разное", "Оплата услуг", "Комиссия банка",
              "Наличные снятие"],
    "salary": ["Зарплата", "Аванс", "ООО Ромашка зарплата", "Заработная плата",
               "Перечисление заработной платы", "Премия"],
    "side_job": ["Фриланс", "Подработка", "Оплата заказа", "Kwork",
                 "Самозанятость доход", "FL.ru"],
    "business": ["ИП доход", "Поступление от клиента", "Оплата по счету",
                 "Выручка"],
    "interest": ["Проценты по вкладу", "Проценты на остаток", "Кэшбэк",
                 "Капитализация процентов", "Cashback"],
    "investments": ["Дивиденды", "Купон по облигациям", "Тинькофф Инвестиции",
                    "Продажа акций", "БКС брокер"],
    "refunds": ["Возврат средств", "Возврат покупки", "Refund",
                "Возврат Wildberries", "Возврат Ozon"],
    "gifts_in": ["Подарок от родителей", "Перевод подарок", "На день рождения"],
    "other_in": ["Поступление", "Перевод от друга", "Пополнение",
                 "Возврат долга"],
}

# Typical amounts per class in rubles (log-normal median, spread).
AMOUNTS = {
    "groceries": (900, .8), "cafe": (650, .7), "transport": (350, .8),
    "car": (2500, .7), "housing": (35000, .4), "utilities": (3500, .6),
    "health": (3000, .8), "pharmacy": (700, .8), "entertainment": (1200, .8),
    "subscriptions": (399, .5), "shopping": (2500, 1.0), "clothes": (3500, .8),
    "gifts": (2500, .8), "travel": (9000, 1.0), "education": (4000, .8),
    "kids": (2500, .9), "pets": (1500, .8), "taxes": (6000, .9),
    "loans": (15000, .5), "other": (1500, 1.0), "salary": (90000, .4),
    "side_job": (15000, .8), "business": (40000, .9), "interest": (900, 1.0),
    "investments": (5000, 1.0), "refunds": (1800, 1.0), "gifts_in": (5000, .8),
    "other_in": (5000, 1.0),
}

_ENTRY = re.compile(
    r'SubscriptionService\(\s*id: "([^"]+)",\s*name: "([^"]+)",\s*'
    r'group: "([^"]+)",(?:\s*aliases: \[(.*?)\],)?',
    re.S,
)


def catalog(path: Path) -> list[tuple[str, list[str], str]]:
    out = []
    for m in _ENTRY.finditer(path.read_text(encoding="utf-8")):
        aliases = re.findall(r'"([^"]+)"', m.group(4) or "")
        out.append((m.group(2), aliases, m.group(3)))
    return out


_TRANSLIT = str.maketrans({
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e",
    "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch",
    "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
})
# Words banks and receipts put next to a merchant (MCC-like descriptors).
DESCRIPTORS = {
    "groceries": ["Супермаркет", "Продукты", "Гипермаркет", "SUPERMARKET",
                  "GROCERY", "Магазин у дома"],
    "cafe": ["Кафе", "Ресторан", "Кофейня", "Пиццерия", "CAFE", "RESTAURANT",
             "Доставка еды", "Бургерная"],
    "transport": ["Такси", "Метро", "TAXI", "Самокаты", "Каршеринг",
                  "Транспортная карта"],
    "car": ["АЗС", "AZS", "Топливо", "FUEL", "Автосервис", "Парковка"],
    "pharmacy": ["Аптека", "APTEKA", "PHARMACY", "Лекарства"],
    "health": ["Клиника", "Медцентр", "CLINIC", "Стоматология"],
    "shopping": ["Маркетплейс", "Магазин", "Интернет-магазин", "SHOP",
                 "Гипермаркет электроники"],
    "clothes": ["Одежда", "Обувь", "CLOTHES", "Магазин одежды", "Косметика"],
    "travel": ["Авиабилеты", "Отель", "Ж/д билеты", "HOTEL", "AIRLINES",
               "Бронирование"],
    "subscriptions": ["Подписка", "SUBSCRIPTION", "Ежемесячная подписка",
                      "Premium"],
    "entertainment": ["Кино", "Билеты", "Развлечения", "Игры"],
    "education": ["Курсы", "Обучение", "Школа"],
    "utilities": ["Связь", "Интернет", "ЖКХ", "Коммунальные"],
    "pets": ["Зоомагазин", "Ветклиника"],
    "kids": ["Детские товары", "Игрушки"],
}

_CITIES = ["MOSCOW", "SPB", "KAZAN", "KOSTROMA", "EKB", "NOVOSIB", "SAMARA",
           "Москва", "Казань"]
_PREFIXES = ["", "", "", "PAY*", "SBP ", "OOO ", "ИП ", "Оплата ", "POS "]
_ACCOUNTS = ["card", "card", "card", "cash", "credit", "savings", ""]


def noisy(name: str, rnd: random.Random) -> str:
    s = name
    r = rnd.random()
    if r < .25:
        s = s.lower().translate(_TRANSLIT).upper()
    elif r < .4:
        s = s.upper()
    elif r < .5:
        s = s.lower()
    if rnd.random() < .35:
        s = f"{s} {rnd.choice(_CITIES)}"
    if rnd.random() < .25:
        s = f"{s} {rnd.randint(1, 9999)}"
    if rnd.random() < .2:
        s = f"{rnd.choice(_PREFIXES)}{s}"
    return s


def describe(name: str, label: str, rnd: random.Random) -> str:
    words = DESCRIPTORS.get(label)
    if not words or rnd.random() > .45:
        return name
    w = rnd.choice(words)
    return f"{w} {name}" if rnd.random() < .6 else f"{name} {w}"


def sample_amount(label: str, rnd: random.Random) -> int:
    med, spread = AMOUNTS[label]
    rub = max(1.0, rnd.lognormvariate(0, spread) * med)
    return int(round(rub * 100))


def synthetic(per_name: int = 14, seed: int = 7) -> list[tuple[TransactionInput, str, str]]:
    """Rows of (input, label, base name) — the base name lets the trainer
    hold out whole merchants for an honest validation."""
    rnd = random.Random(seed)
    names: list[tuple[str, str]] = []
    for name, aliases, group in catalog(ROOT / "lib/domain/store_catalog.dart"):
        if group in STORE_GROUPS:
            names += [(n, STORE_GROUPS[group]) for n in [name, *aliases]]
    for name, aliases, group in catalog(ROOT / "lib/domain/service_catalog.dart"):
        if group in SERVICE_GROUPS:
            names += [(n, SERVICE_GROUPS[group]) for n in [name, *aliases[:2]]]
    for label, seeds in SEEDS.items():
        names += [(n, label) for n in seeds for _ in range(3)]
    start = date(2025, 1, 1)
    rows = []
    for name, label in names:
        for _ in range(per_name):
            rows.append((
                TransactionInput(
                    merchant=noisy(describe(name, label, rnd), rnd),
                    description="",
                    amount_minor=sample_amount(label, rnd),
                    kind="income" if label in INCOME else "expense",
                    account_type=rnd.choice(_ACCOUNTS),
                    date=start + timedelta(days=rnd.randint(0, 540)),
                ),
                label,
                name.lower(),
            ))
    rnd.shuffle(rows)
    return rows


def load_csv(path: Path) -> list[tuple[TransactionInput, str, str]]:
    rows = []
    with path.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["label"] not in CLASSES:
                continue
            rows.append((
                TransactionInput(
                    merchant=r["merchant"],
                    description=r.get("description", ""),
                    amount_minor=int(r["amount_minor"]),
                    kind=r["kind"],
                    account_type=r.get("account_type", ""),
                    date=date.fromisoformat(r["date"]),
                ),
                r["label"],
                r["merchant"].lower(),
            ))
    return rows
