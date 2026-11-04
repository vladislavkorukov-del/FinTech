#!/usr/bin/env python3
"""Regenerate the static Material outline catalog using the pinned Flutter SDK.

Never reorder the 36 legacy indices: category/account rows store those integers.
All icon references are compile-time Icons constants for release font tree shaking.
Run: python3 tool/generate_icon_catalog.py [path/to/material/icons.dart]
"""
import json
import os
from pathlib import Path
import re
import sys

LEGACY = '''shopping_basket_outlined restaurant_outlined directions_bus_outlined directions_car_outlined home_outlined bolt_outlined favorite_border_rounded medication_outlined movie_outlined subscriptions_outlined shopping_bag_outlined checkroom_outlined card_giftcard_outlined flight_outlined school_outlined child_care_outlined pets_outlined receipt_long_outlined credit_card_outlined more_horiz_rounded work_outline_rounded laptop_outlined storefront_outlined percent_rounded trending_up_rounded undo_rounded wallet_outlined savings_outlined account_balance_outlined beach_access_outlined devices_outlined shield_outlined sports_esports_outlined fitness_center_outlined coffee_outlined music_note_outlined'''.split()
# Group order is a user-facing spending taxonomy, not a technical icon taxonomy.
GROUPS = {
 'food': 'Еда и продукты', 'transport': 'Транспорт', 'home': 'Дом и жильё',
 'finance': 'Финансы', 'health': 'Здоровье', 'beauty': 'Уход и красота',
 'shopping': 'Покупки и одежда', 'family': 'Семья и дети', 'pets': 'Животные',
 'travel': 'Путешествия', 'leisure': 'Досуг', 'sport': 'Спорт',
 'education': 'Образование', 'work': 'Работа и бизнес', 'tech': 'Техника',
 'utilities': 'Связь и услуги', 'nature': 'Природа', 'other': 'Все остальные',
}
# Explicit localized labels/search terms for common finance scenarios. Additional
# icon names and individual English words remain searchable across the full set.
CURATED = {
 'shopping_basket': ('Продукты', 'food', 'продукты корзина магазин супермаркет groceries grocery food supermarket'),
 'restaurant': ('Ресторан', 'food', 'кафе ресторан еда ужин обед завтрак restaurant dining meal'),
 'directions_bus': ('Автобус', 'transport', 'автобус транспорт проезд билет общественный bus public transport'),
 'directions_car': ('Автомобиль', 'transport', 'автомобиль машина авто car vehicle driving'),
 'home': ('Дом', 'home', 'дом квартира жилье аренда недвижимость ипотека mortgage rent housing property'),
 'bolt': ('Электричество', 'utilities', 'коммунальные электричество свет энергия electric electricity power utilities'),
 'favorite_border': ('Здоровье', 'health', 'здоровье сердце пульс медицина health heart'),
 'medication': ('Аптека', 'health', 'аптека лекарства таблетки витамины pharmacy medicine drugs'),
 'movie': ('Кино', 'leisure', 'кино фильм развлечения билеты movie cinema film'),
 'subscriptions': ('Подписки', 'utilities', 'подписки сервисы регулярные streaming subscriptions netflix spotify'),
 'shopping_bag': ('Покупки', 'shopping', 'покупки сумка шопинг магазин shopping bag retail'),
 'checkroom': ('Одежда', 'shopping', 'одежда гардероб пальто рубашка вешалка clothing clothes wardrobe fashion'),
 'card_giftcard': ('Подарки', 'shopping', 'подарки подарок праздник день рождения gift present birthday'),
 'flight': ('Перелёт', 'travel', 'путешествия самолет перелет авиабилеты отпуск flight airport airline travel'),
 'school': ('Образование', 'education', 'образование школа учеба обучение курсы университет school education college'),
 'child_care': ('Дети', 'family', 'дети ребенок малыш детский сад семья child baby kindergarten'),
 'pets': ('Питомцы', 'pets', 'животные питомцы собака кошка корм ветеринар pets dog cat veterinary animal'),
 'receipt_long': ('Чек', 'finance', 'налоги чек квитанция расходы tax receipt bill invoice'),
 'credit_card': ('Банковская карта', 'finance', 'кредит карта дебет банк кредитка credit debit card bank'),
 'more_horiz': ('Прочее', 'other', 'прочее другое разное other more miscellaneous'),
 'work_outline': ('Работа', 'work', 'зарплата работа офис доход карьера salary work job office income'),
 'laptop': ('Ноутбук', 'tech', 'подработка ноутбук компьютер фриланс laptop computer freelance'),
 'storefront': ('Бизнес', 'work', 'бизнес магазин продажи торговля предпринимательство business shop store commerce'),
 'percent': ('Проценты', 'finance', 'проценты скидка ставка кэшбэк percent interest discount cashback'),
 'trending_up': ('Инвестиции', 'finance', 'инвестиции акции фонд биржа доход рост investments stocks market trading'),
 'undo': ('Возврат', 'finance', 'возврат возмещение компенсация refund return reimbursement'),
 'wallet': ('Наличные', 'finance', 'кошелек наличные деньги бумажник cash money wallet'),
 'savings': ('Накопления', 'finance', 'накопления копилка сбережения цель savings goal piggy bank'),
 'account_balance': ('Банк', 'finance', 'банк счет вклад банковский депозит bank account deposit'),
 'beach_access': ('Отпуск', 'travel', 'отпуск пляж море путешествия туризм beach vacation travel holiday'),
 'devices': ('Техника', 'tech', 'техника электроника устройства компьютер телефон devices electronics gadgets'),
 'shield': ('Страхование', 'finance', 'безопасность подушка страхование страховка полис осаго каско insurance protection security'),
 'sports_esports': ('Игры', 'leisure', 'игры приставка консоль развлечения game gaming console playstation'),
 'fitness_center': ('Тренажёрный зал', 'sport', 'спорт фитнес зал тренажер тренировка абонемент fitness gym workout'),
 'coffee': ('Кофе', 'food', 'кофе кофейня напитки coffee cafe cappuccino'),
 'music_note': ('Музыка', 'leisure', 'музыка концерт песня ноты music concert song'),
 'medical_services': ('Медицина', 'health', 'медицина клиника врач стоматолог зубы стоматология dentist dental teeth doctor clinic hospital'),
 'health_and_safety': ('Медицинская страховка', 'health', 'здоровье страховка страхование дмс страховой полис health insurance medical'),
 'healing': ('Лечение', 'health', 'лечение здоровье травма врач перевязка healing treatment injury'),
 'local_hospital': ('Больница', 'health', 'больница госпиталь поликлиника медицина hospital clinic doctor'),
 'local_pharmacy': ('Лекарства', 'health', 'аптека лекарства таблетки pharmacy drugs medicine'),
 'vaccines': ('Вакцинация', 'health', 'вакцина прививка укол вакцинация vaccines injection shot'),
 'bloodtype': ('Анализы', 'health', 'анализы кровь лаборатория диагностика blood laboratory test'),
 'monitor_heart': ('Обследование', 'health', 'кардиолог сердце обследование экг диагностика cardiology heart checkup'),
 'psychology': ('Психолог', 'health', 'психолог психотерапия ментальное здоровье консультация psychology therapy mental health'),
 'spa': ('Уход и красота', 'beauty', 'маникюр ногти педикюр красота салон уход спа массаж nails manicure beauty salon spa massage'),
 'face_retouching_natural': ('Косметология', 'beauty', 'косметология косметика уход лицо красота makeup cosmetics face beauty'),
 'content_cut': ('Парикмахерская', 'beauty', 'парикмахерская стрижка волосы салон барбер haircut hair barber salon'),
 'brush': ('Косметика', 'beauty', 'косметика макияж кисть маникюр ногти makeup cosmetics brush nails manicure'),
 'dry_cleaning': ('Химчистка', 'utilities', 'химчистка прачечная стирка clean laundry dry cleaning'),
 'local_taxi': ('Такси', 'transport', 'такси поездка яндекс uber taxi cab ride'),
 'local_gas_station': ('Топливо', 'transport', 'топливо бензин дизель заправка газ fuel petrol gasoline diesel gas station'),
 'local_parking': ('Парковка', 'transport', 'парковка стоянка автомобиль parking car'),
 'car_repair': ('Ремонт автомобиля', 'transport', 'ремонт авто машина обслуживание шиномонтаж car repair service mechanic tires'),
 'car_rental': ('Аренда автомобиля', 'transport', 'аренда авто каршеринг прокат car rental carsharing'),
 'electric_car': ('Электромобиль', 'transport', 'электромобиль зарядка авто electric car charging'),
 'electric_scooter': ('Самокат', 'transport', 'самокат электросамокат прокат scooter kick scooter'),
 'directions_bike': ('Велосипед', 'transport', 'велосипед велопрокат транспорт bicycle bike cycling'),
 'directions_subway': ('Метро', 'transport', 'метро транспорт подземка subway underground metro'),
 'train': ('Поезд', 'transport', 'поезд железная дорога билет ржд train railway'),
 'tram': ('Трамвай', 'transport', 'трамвай транспорт tram transport'),
 'sailing': ('Лодка', 'travel', 'лодка яхта круиз паром море boat yacht cruise sailing'),
 'house': ('Жильё', 'home', 'жилье дом квартира аренда ипотека mortgage housing rent home house'),
 'real_estate_agent': ('Недвижимость', 'home', 'недвижимость ипотека квартира жилье покупка mortgage real estate property housing'),
 'cottage': ('Дача', 'home', 'дача загородный дом сад коттедж cottage garden house'),
 'apartment': ('Квартира', 'home', 'квартира жилье аренда ипотека apartment flat rent mortgage'),
 'home_work': ('Аренда и ипотека', 'home', 'аренда ипотека жилье коммунальные rent mortgage housing utilities'),
 'construction': ('Ремонт', 'home', 'ремонт строительство инструменты construction renovation repair tools'),
 'handyman': ('Мастер', 'home', 'мастер сантехник ремонт инструменты handyman plumber repair'),
 'plumbing': ('Сантехника', 'home', 'сантехника водопровод трубы вода plumbing water'),
 'chair': ('Мебель', 'home', 'мебель кресло диван стул chair sofa furniture'),
 'bed': ('Спальня', 'home', 'спальня кровать матрас мебель bed bedroom mattress'),
 'kitchen': ('Кухня', 'home', 'кухня холодильник мебель бытовая техника kitchen fridge furniture'),
 'water_drop': ('Вода', 'utilities', 'вода водоснабжение коммунальные water utilities'),
 'thermostat': ('Отопление', 'utilities', 'отопление тепло газ коммунальные heating thermostat utilities'),
 'wifi': ('Интернет', 'utilities', 'интернет связь вайфай провайдер wifi internet broadband'),
 'phone_android': ('Телефон', 'tech', 'телефон смартфон android мобильный phone smartphone'),
 'phone_iphone': ('Смартфон', 'tech', 'телефон смартфон iphone apple phone mobile'),
 'sim_card': ('Мобильная связь', 'utilities', 'мобильная связь телефон сим карта тариф sim phone mobile telecom'),
 'payments': ('Платежи', 'finance', 'платежи деньги наличные выплаты оплата payment money cash'),
 'account_balance_wallet': ('Кошелёк', 'finance', 'кошелек наличные баланс счет wallet cash balance account'),
 'request_quote': ('Налоги и счета', 'finance', 'налоги счет квитанция оплата задолженность tax bill invoice debt'),
 'price_check': ('Скидки', 'shopping', 'скидки покупки цена выгода discount sale price'),
 'local_offer': ('Купоны', 'shopping', 'купоны скидки промокод акция discount coupon offer sale'),
 'currency_exchange': ('Обмен валюты', 'finance', 'обмен валюта рубль доллар евро курс currency exchange rub usd eur'),
 'currency_ruble': ('Рубль', 'finance', 'рубль рубли валюта деньги ruble rub currency'),
 'attach_money': ('Деньги', 'finance', 'деньги доллар финансы money dollar income'),
 'paid': ('Оплачено', 'finance', 'оплачено оплата деньги доход paid payment money'),
 'volunteer_activism': ('Благотворительность', 'finance', 'благотворительность пожертвование помощь charity donation support'),
 'redeem': ('Подарок', 'shopping', 'подарки подарок праздник бонус gift present reward'),
 'child_friendly': ('Коляска', 'family', 'дети ребенок коляска малыш baby child stroller'),
 'crib': ('Детская кроватка', 'family', 'детская кроватка ребенок младенец малыш crib baby infant'),
 'toys': ('Игрушки', 'family', 'игрушки дети ребенок toys child kids'),
 'family_restroom': ('Семья', 'family', 'семья родители дети семейные расходы family parents children'),
 'diversity_1': ('Близкие', 'family', 'семья близкие родители поддержка family relatives people'),
 'cruelty_free': ('Забота о животных', 'pets', 'животные питомцы кролик ветеринар корм pet rabbit animal veterinary'),
 'hotel': ('Отель', 'travel', 'отель гостиница путешествия проживание hotel accommodation travel'),
 'luggage': ('Багаж', 'travel', 'багаж чемодан поездка путешествия suitcase luggage travel'),
 'passport': ('Документы', 'travel', 'паспорт виза поездка документы passport visa travel document'),
 'map': ('Карта путешествий', 'travel', 'карта туризм маршрут путешествия map travel route tourism'),
 'travel_explore': ('Путешествия', 'travel', 'путешествия туризм отпуск поездка travel tourism explore vacation'),
 'local_dining': ('Питание', 'food', 'еда питание ресторан кафе dining restaurant food'),
 'local_cafe': ('Кафе', 'food', 'кафе кофе кофейня cafe coffee'),
 'local_bar': ('Бар', 'food', 'бар напитки коктейль алкоголь bar drink cocktail'),
 'local_pizza': ('Пицца', 'food', 'пицца доставка еда pizza delivery food'),
 'delivery_dining': ('Доставка еды', 'food', 'доставка еда курьер delivery food courier'),
 'fastfood': ('Фастфуд', 'food', 'фастфуд бургер еда быстрое питание fastfood burger food'),
 'bakery_dining': ('Выпечка', 'food', 'выпечка хлеб пекарня круассан bakery bread croissant'),
 'ramen_dining': ('Лапша', 'food', 'лапша рамен азиатская кухня ramen noodles dining'),
 'icecream': ('Мороженое', 'food', 'мороженое десерт сладости icecream dessert sweets'),
 'cake': ('Торт', 'food', 'торт день рождения десерт сладости cake birthday dessert'),
 'egg': ('Яйца', 'food', 'яйца продукты еда eggs groceries food'),
 'local_grocery_store': ('Супермаркет', 'food', 'супермаркет продукты магазин покупки grocery supermarket groceries'),
 'local_mall': ('Торговый центр', 'shopping', 'торговый центр покупки магазин shopping mall retail'),
 'diamond': ('Украшения', 'shopping', 'украшения ювелирный кольцо бриллиант jewelry diamond ring'),
 'watch': ('Часы', 'shopping', 'часы аксессуары украшения watch accessories'),
 'menu_book': ('Книги', 'education', 'книги чтение учебник обучение book reading textbook'),
 'auto_stories': ('Чтение', 'education', 'книги чтение библиотека учеба book reading library'),
 'science': ('Наука', 'education', 'наука лаборатория учеба эксперимент science laboratory education'),
 'translate': ('Иностранные языки', 'education', 'языки английский перевод обучение курсы language english translation learning'),
 'sports_soccer': ('Футбол', 'sport', 'спорт футбол тренировка мяч soccer football sport'),
 'sports_tennis': ('Теннис', 'sport', 'теннис ракетка спорт tennis racket sport'),
 'pool': ('Бассейн', 'sport', 'бассейн плавание абонемент спорт pool swimming sport'),
 'hiking': ('Поход', 'sport', 'поход туризм пеший прогулки hiking trekking walking'),
 'sports_gymnastics': ('Гимнастика', 'sport', 'гимнастика спорт растяжка тренировка gymnastics exercise'),
 'self_improvement': ('Йога', 'sport', 'йога медитация расслабление yoga meditation wellness'),
 'theater_comedy': ('Театр', 'leisure', 'театр спектакль представление comedy theater show'),
 'museum': ('Музей', 'leisure', 'музей выставка культура искусство museum exhibition culture art'),
 'celebration': ('Праздник', 'leisure', 'праздник вечеринка развлечения party celebration birthday'),
 'photo_camera': ('Фотоаппарат', 'tech', 'фото камера съемка техника photography camera photo'),
 'headphones': ('Наушники', 'tech', 'наушники музыка техника headphones audio music'),
 'computer': ('Компьютер', 'tech', 'компьютер техника электроника computer desktop electronics'),
 'print': ('Печать', 'work', 'печать принтер офис документы printing printer office'),
 'business_center': ('Деловые расходы', 'work', 'бизнес командировка работа деловые расходы business work office'),
 'receipt': ('Квитанция', 'finance', 'чек квитанция налог оплата receipt tax bill'),
 'gavel': ('Юридические услуги', 'finance', 'юрист адвокат суд штраф юридические услуги legal lawyer fine court'),
 'park': ('Парк', 'nature', 'парк деревья природа прогулка park tree nature'),
 'forest': ('Лес', 'nature', 'лес деревья природа отдых forest trees nature'),
 'local_florist': ('Цветы', 'nature', 'цветы флорист букет растения flower florist bouquet plants'),
}
GROUP_PATTERNS = {
 'food': 'food dining restaurant coffee cafe pizza bakery egg cake icecream liquor tapas lunch breakfast dinner rice soup kebab brunch bento grocery kitchen restaurant ramen set_meal local_drink'.split(),
 'transport': 'car taxi bus train subway tram bike bicycle scooter motorcycle moped gas parking garage traffic commute transit railway tire wheel charging station ev route transportation'.split(),
 'home': 'home house cottage apartment furniture chair bed bedroom bathroom shower bathtub door window construction handyman plumbing roof foundation fence cabin living balcony stairs room yard weekend deck countertop microwave'.split(),
 'finance': 'account_balance wallet savings payment credit debit money currency euro dollar ruble yen bank receipt price percent paid quote monetization coin request tax insurance shield security policy sell shopping_cart_checkout'.split(),
 'health': 'health medical medication hospital pharmacy healing blood vaccines heart emergency psychology accessible blind deaf masks sick coronavirus monitor_weight personal_injury sanitizer wheelchair medical_information'.split(),
 'beauty': 'spa face brush cut beauty woman_2 man_2 dry_cleaning'.split(),
 'shopping': 'shopping checkroom gift redeem diamond watch store mall offer loyalty label style handbag umbrella umbrella'.split(),
 'family': 'child baby family crib toys boy girl pregnant elderly diversity person people man woman groups supervised'.split(),
 'pets': 'pets cruelty_free animal'.split(),
 'travel': 'flight airplane airport luggage hotel beach travel explore map tour boat sailing ferry snowmobile passport connecting_airports connecting_airports connecting_airports'.split(),
 'leisure': 'movie theater music piano guitar headphones games game casino celebration festival camera museum mic karaoke attractions nightlife piano headphones podcasts radio tv local_play'.split(),
 'sport': 'sports sport fitness pool hiking skateboarding surfing skiing snowboard kayaking kitesurfing golf running run rowing climbing downhill_skiing nordic_walking self_improvement'.split(),
 'education': 'school book library science translate abc education calculate draw history_edu auto_stories class'.split(),
 'work': 'work business laptop office print badge engineering analytics insights factory warehouse meeting co_present support_agent inventory'.split(),
 'tech': 'devices computer phone laptop tablet smartphone headset mouse keyboard memory usb bluetooth router battery developer camera video screen monitor cable hardware terminal settings_input storage fax'.split(),
 'utilities': 'wifi network signal sim internet subscriptions subscription bolt power electric electricity water thermostat ac_unit light heat local_laundry laundry cleaning waste delete recycling telephone mail cellular call satellite cell utility'.split(),
 'nature': 'park forest flower eco grass tree nature agriculture terrain landscape sun cloudy cloud rainbow thunderstorm air compost tsunami waves volcano'.split(),
}
WORDS_RU = {
 'add':'добавить плюс','remove':'убрать минус','delete':'удалить корзина','home':'дом жилье','house':'дом жилье','apartment':'квартира жилье ипотека',
 'car':'авто машина автомобиль','bus':'автобус транспорт','train':'поезд транспорт','flight':'самолет перелет путешествия','taxi':'такси',
 'gas':'топливо бензин заправка','local_gas_station':'топливо бензин заправка','parking':'парковка стоянка','electric':'электричество зарядка',
 'restaurant':'ресторан еда','dining':'еда питание','food':'еда продукты','coffee':'кофе','cafe':'кафе','bar':'бар напитки','drink':'напиток',
 'water':'вода','drop':'капля','shopping':'покупки магазин','basket':'корзина продукты','bag':'сумка','store':'магазин','gift':'подарок',
 'health':'здоровье','heart':'сердце здоровье','medical':'медицина врач','pharmacy':'аптека','medication':'лекарства аптека',
 'face':'лицо красота','spa':'красота маникюр ногти салон массаж','cut':'стрижка волосы','brush':'косметика маникюр',
 'child':'ребенок дети','baby':'малыш ребенок','family':'семья дети','pets':'питомцы животные','school':'школа учеба образование',
 'book':'книга учеба','library':'библиотека','science':'наука','sports':'спорт','fitness':'фитнес тренировка','pool':'бассейн плавание',
 'music':'музыка','movie':'кино фильм','theater':'театр','games':'игры','game':'игра','beach':'пляж отпуск','hotel':'отель гостиница',
 'travel':'путешествия туризм отпуск','luggage':'чемодан багаж','map':'карта маршрут','wallet':'кошелек наличные',
 'money':'деньги','payment':'платеж оплата','payments':'платежи оплата','bank':'банк','balance':'баланс счет','credit':'кредит карта',
 'savings':'накопления сбережения цель','currency':'валюта обмен','receipt':'чек квитанция','percent':'проценты ставка скидка',
 'work':'работа зарплата доход','business':'бизнес работа','computer':'компьютер техника','laptop':'ноутбук компьютер',
 'phone':'телефон связь','headphones':'наушники музыка','camera':'камера фото','watch':'часы','devices':'устройства техника',
 'wifi':'интернет связь','sim':'связь сим тариф','subscriptions':'подписки','power':'электричество питание','bolt':'электричество свет',
 'plumbing':'сантехника ремонт','construction':'ремонт строительство','chair':'стул кресло мебель','bed':'кровать спальня',
 'kitchen':'кухня техника','light':'свет лампа','shield':'страховка страхование защита','security':'безопасность защита',
 'park':'парк природа','forest':'лес природа','flower':'цветы букет','eco':'экология природа','sun':'солнце','cloud':'облако погода',
 'fast':'быстро','delivery':'доставка','calendar':'календарь дата','event':'событие дата','schedule':'расписание время','alarm':'будильник',
 'check':'проверить галочка','favorite':'избранное сердце','star':'звезда избранное','settings':'настройки','person':'человек участник',
}


def metadata(icon):
    name = re.sub(r'_(outlined|rounded)$', '', icon)
    if name in CURATED:
        return CURATED[name]
    tokens = name.split('_')
    group = 'other'
    # Whole-name and word matches avoid classifying "barcode" as "car".
    for candidate, terms in GROUP_PATTERNS.items():
        if any(term in tokens or term == name or f'_{term}_' in f'_{name}_' for term in terms):
            group = candidate
            break
    ru = ' '.join(WORDS_RU[t] for t in tokens if t in WORDS_RU)
    label = name.replace('_', ' ').capitalize()
    return label, group, ru


def main():
    root = Path(__file__).resolve().parents[1]
    source = Path(sys.argv[1]) if len(sys.argv)>1 else Path(os.environ.get('FLUTTER_ROOT','/workspace/flutter-sdk'))/'packages/flutter/lib/src/material/icons.dart'
    names = re.findall(r'static const IconData (\w+_outlined)\s*=', source.read_text())
    if len(names) < 1500:
        raise SystemExit('Unexpected Flutter icon source; refusing to shrink catalog')
    # Once an index has shipped it must stay stable even when Flutter adds icons.
    output = root/'lib/presentation/theme/icon_catalog.dart'
    previous = re.findall(r'^  Icons\.(\w+),$',output.read_text(),re.M) if output.exists() else []
    existing = previous or LEGACY
    if existing[:36] != LEGACY:
        raise SystemExit('Legacy icon indices changed')
    if not set(existing).issubset(set(names)|set(LEGACY)):
        raise SystemExit('Pinned SDK removed a stored icon; explicit migration is required')
    ordered = existing + sorted(set(names)-set(existing))
    def dart(value): return json.dumps(value, ensure_ascii=False)
    lines = ['// GENERATED by tool/generate_icon_catalog.py. Do not reorder stored indices.',
      '// Source: Flutter Material Icons; static references preserve font tree shaking.',
      "import 'package:flutter/material.dart';", '',
      'class FinanceIconEntry {',
      '  const FinanceIconEntry(this.index, this.name, this.label, this.group, this.keywords);',
      '  final int index;', '  final String name, label, group, keywords;',
      '  IconData get icon => iconChoices[index];',
      '}', '', 'const iconGroups = <String, String>{']
    lines += [f'  {dart(k)}: {dart(v)},' for k,v in GROUPS.items()]
    lines += ['};','','const iconChoices = <IconData>[']
    lines += [f'  Icons.{n},' for n in ordered]
    lines += ['];','','const iconCatalog = <FinanceIconEntry>[']
    for i,n in enumerate(ordered):
        label,group,ru = metadata(n)
        english = re.sub(r'_(outlined|rounded)$','',n).replace('_',' ')
        search = f'{english} {ru} {GROUPS[group]}'
        lines.append(f'  FinanceIconEntry({i}, {dart(n)}, {dart(label)}, {dart(group)}, {dart(search)}),')
    lines += ['];','',r'''String normalizeIconQuery(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[_\-]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _iconSearchIndex = iconCatalog.map((entry) => normalizeIconQuery('${entry.label} ${entry.keywords} ${entry.name}')).toList(growable: false);

/// All query words must match; order/case and the spelling ё/е do not matter.
List<FinanceIconEntry> searchFinanceIcons(String query, {String? group}) {
  final words = normalizeIconQuery(query).split(' ').where((s) => s.isNotEmpty).toList();
  return iconCatalog.where((entry) {
    if (group != null && group != 'all' && entry.group != group) {
      return false;
    }
    return words.every(_iconSearchIndex[entry.index].contains);
  }).toList(growable: false);
}

IconData categoryIcon(int index) =>
    iconChoices[index.abs() % iconChoices.length];
''']
    output.write_text('\n'.join(lines)+'\n')
    print(f'Generated {len(ordered)} stable icons from {source}')

if __name__=='__main__': main()
