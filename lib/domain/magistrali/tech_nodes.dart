/// The nodes of the company's technology tree (see tech.dart).
library;

import 'tech.dart';
import 'tech_nodes_later.dart';

const magTechNodes = <MagTech>[
  // ---- Автопарк: эпоха I — лошади ----
  MagTech(
    id: 'stud',
    branch: MagBranch.fleet,
    title: 'Конный завод',
    lore:
        'Свой табун и знающий конюх. Лошади крепче, шаг бодрее — '
        'телеги доходят засветло.',
    effect: 'Скорость гужевого транспорта +12%',
    effects: {MagBonus.horseSpeed: .12},
    cost: 700,
    level: 2,
  ),
  MagTech(
    id: 'springs',
    branch: MagBranch.fleet,
    title: 'Рессоры и железные оси',
    lore:
        'Кузнец перековал оси и поставил рессоры. Телега не трещит под '
        'лишним мешком.',
    effect: 'Вместимость повозок +20%',
    effects: {MagBonus.horseCapacity: .2},
    cost: 1100,
    level: 3,
  ),
  MagTech(
    id: 'harness',
    branch: MagBranch.fleet,
    title: 'Хомуты и упряжь',
    lore:
        'Мягкий хомут не натирает шею — лошадь тянет дольше и не '
        'устаёт к вечеру.',
    effect: 'Скорость повозок +10%, износ −10%',
    effects: {MagBonus.horseSpeed: .1, MagBonus.wear: -.1},
    cost: 2000,
    level: 5,
    requires: ['stud'],
  ),
  // Era II — railways (stage S8, TECH-03).
  MagTech(
    id: 'steam',
    branch: MagBranch.fleet,
    title: 'Паровая тяга',
    lore:
        'Чугунные рельсы, шпалы из лиственницы и паровоз, который тянет '
        'больше, чем сорок подвод. Дорого строить — дёшево возить.',
    effect: 'Железные дороги, станции и паровоз «Искра»',
    effects: {MagBonus.rails: 1},
    cost: 9000,
    level: 6,
    requires: ['stud'],
    deliveries: 80,
  ),
  MagTech(
    id: 'dieseltrain',
    branch: MagBranch.fleet,
    title: 'Тепловозная тяга',
    lore:
        'Дизель вместо котла: локомотив не ждёт воды и угля, тянет вдвое '
        'длиннее состав и идёт быстрее.',
    effect: 'Тепловоз «Восток»: до 8 вагонов',
    effects: {MagBonus.diesel: 1},
    cost: 20000,
    level: 12,
    requires: ['steam', 'combustion'],
    deliveries: 300,
  ),
  MagTech(
    id: 'combustion',
    branch: MagBranch.fleet,
    title: 'Двигатель внутреннего сгорания',
    lore:
        'Из столицы привезли чертежи и первый мотор. Он чихает и дымит, '
        'но не просит овса и не устаёт.',
    effect: 'Открывает грузовики (пикап, «Терра», тягач)',
    effects: {MagBonus.motors: 1},
    cost: 4000,
    level: 4,
    requires: ['stud'],
    deliveries: 30,
  ),
  // ---- Автопарк: моторы ----
  // Master plan stage 5: the first motor technologies of the industrial age.
  MagTech(
    id: 'steelbodies',
    branch: MagBranch.fleet,
    title: 'Стальные кузова',
    lore:
        'Своя сталь пошла в дело: кузова стали прочнее и вместительнее, а '
        'рама больше не гнётся на ухабах.',
    effect: 'Вместимость моторных машин +8%, износ −5%',
    effects: {MagBonus.capacity: .08, MagBonus.wear: -.05},
    cost: 6000,
    level: 5,
    requires: ['combustion'],
    deliveries: 60,
  ),
  MagTech(
    id: 'spareparts',
    branch: MagBranch.fleet,
    title: 'Склад запчастей',
    lore:
        'Свечи, ремни и подшипники — на полке, а не в столице. Машина больше '
        'не стоит неделю в ожидании одной детали.',
    effect: 'Ремонт −20%, содержание машин −5%',
    effects: {MagBonus.service: -.2, MagBonus.upkeep: -.05},
    cost: 7000,
    level: 6,
    requires: ['steelbodies'],
    deliveries: 90,
  ),
  MagTech(
    id: 'turbo',
    branch: MagBranch.fleet,
    title: 'Турбонаддув',
    lore:
        'Механики нашли в старом гараже ящик турбин. Пикапы зарычали по-новому.',
    effect: 'Скорость всех машин +5%',
    effects: {MagBonus.speed: .05},
    cost: 1200,
    level: 2,
  ),
  MagTech(
    id: 'injector',
    branch: MagBranch.fleet,
    title: 'Инжектор нового поколения',
    lore: 'Точная подача топлива: мотор отзывается на педаль без задержки.',
    effect: 'Скорость +5%',
    effects: {MagBonus.speed: .05},
    cost: 4500,
    level: 6,
    requires: ['turbo'],
  ),
  MagTech(
    id: 'hybrid',
    branch: MagBranch.fleet,
    title: 'Гибридная тяга',
    lore:
        'Электромотор помогает на разгоне — грузовики идут в гору, как по равнине.',
    effect: 'Скорость +7%, расход −5%',
    effects: {MagBonus.speed: .07, MagBonus.fuel: -.05},
    cost: 16000,
    level: 14,
    requires: ['injector', 'aero'],
    deliveries: 300,
  ),
  MagTech(
    id: 'sides',
    branch: MagBranch.fleet,
    title: 'Наращённые борта',
    lore:
        'Двадцать сантиметров фанеры по периметру — и в кузов входит ещё мешок.',
    effect: 'Вместимость машин +8%',
    effects: {MagBonus.capacity: .08},
    cost: 1800,
    level: 3,
  ),
  MagTech(
    id: 'trailer',
    branch: MagBranch.fleet,
    title: 'Сцепка-полуприцеп',
    lore:
        'Стандартный фаркоп и прицеп из соседнего колхоза. Водители довольны.',
    effect: 'Вместимость +10%',
    effects: {MagBonus.capacity: .1},
    cost: 6500,
    level: 8,
    requires: ['sides'],
    deliveries: 60,
  ),
  MagTech(
    id: 'composite',
    branch: MagBranch.fleet,
    title: 'Композитный кузов',
    lore:
        'Лёгкий как пластик, прочный как сталь. Машина везёт больше, а весит меньше.',
    effect: 'Вместимость +12%, износ −5%',
    effects: {MagBonus.capacity: .12, MagBonus.wear: -.05},
    cost: 18000,
    level: 18,
    requires: ['trailer'],
    deliveries: 500,
  ),
  MagTech(
    id: 'eco',
    branch: MagBranch.fleet,
    title: 'Эко-вождение',
    lore:
        'Курсы плавного разгона для водителей. Бак пустеет заметно медленнее.',
    effect: 'Расход топлива −8%',
    effects: {MagBonus.fuel: -.08},
    cost: 1000,
    level: 2,
  ),
  MagTech(
    id: 'aero',
    branch: MagBranch.fleet,
    title: 'Аэродинамические обтекатели',
    lore: 'Ветер больше не тормозит кабину — он обтекает её.',
    effect: 'Расход −10%, скорость +2%',
    effects: {MagBonus.fuel: -.1, MagBonus.speed: .02},
    cost: 5200,
    level: 10,
    requires: ['eco'],
  ),
  MagTech(
    id: 'maintenance',
    branch: MagBranch.fleet,
    title: 'Регламент ТО',
    lore:
        'Масло по расписанию, фильтры по чек-листу. Поломок стало вдвое меньше.',
    effect: 'Износ −15%, ремонт дешевле на 15%',
    effects: {MagBonus.wear: -.15, MagBonus.service: -.15},
    cost: 2200,
    level: 4,
  ),
  MagTech(
    id: 'telemetry',
    branch: MagBranch.fleet,
    title: 'Телеметрия',
    lore:
        'Каждая машина шлёт сводку о себе. Неисправности ловим до того, как они случатся.',
    effect: 'Износ −20%, обслуживание машин −10%',
    effects: {MagBonus.wear: -.2, MagBonus.upkeep: -.1},
    cost: 9000,
    level: 12,
    requires: ['maintenance'],
    deliveries: 150,
  ),
  // ---- Дороги ----
  MagTech(
    id: 'survey',
    branch: MagBranch.roads,
    title: 'Геодезия',
    lore:
        'Теодолит и пара толковых инженеров: трасса ложится по рельефу, а не поперёк.',
    effect: 'Строительство дорог −10%',
    effects: {MagBonus.roadCost: -.1},
    cost: 900,
    level: 2,
  ),
  MagTech(
    id: 'bridges',
    branch: MagBranch.roads,
    title: 'Мостостроение',
    lore: 'Сборные пролёты из бетона. Реки перестают быть стеной.',
    effect: 'Мосты через реку −35%',
    effects: {MagBonus.bridge: -.35},
    cost: 2600,
    level: 5,
    requires: ['survey'],
  ),
  MagTech(
    id: 'paver',
    branch: MagBranch.roads,
    title: 'Асфальтоукладчик',
    lore: 'Своя техника вместо подрядчиков: километр дороги — за смену.',
    effect: 'Строительство дорог ещё −10%',
    effects: {MagBonus.roadCost: -.1},
    cost: 4800,
    level: 7,
    requires: ['survey'],
  ),
  MagTech(
    id: 'marking',
    branch: MagBranch.roads,
    title: 'Разметка и знаки',
    lore:
        'Чёткие полосы и понятные указатели — водители не сбавляют ход на развилках.',
    effect: 'Скорость на дорогах +5%',
    effects: {MagBonus.roadSpeed: .05},
    cost: 6000,
    level: 9,
    requires: ['paver'],
  ),
  MagTech(
    id: 'roadcrew',
    branch: MagBranch.roads,
    title: 'Дорожная служба',
    lore:
        'Бригада латает ямы раньше, чем их заметят. Содержание сети дешевеет.',
    effect: 'Содержание дорог −30%',
    effects: {MagBonus.roadUpkeep: -.3},
    cost: 5500,
    level: 11,
    requires: ['paver'],
  ),
  MagTech(
    id: 'smartroads',
    branch: MagBranch.roads,
    title: 'Умные трассы',
    lore: 'Датчики в покрытии и зелёная волна на перекрёстках.',
    effect: 'Скорость на дорогах +8%',
    effects: {MagBonus.roadSpeed: .08},
    cost: 20000,
    level: 20,
    requires: ['marking', 'roadcrew'],
    deliveries: 600,
  ),
  ...magTechNodesLater,
];
