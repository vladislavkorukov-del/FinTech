/// The company's technology tree. Every node changes a real number of the
/// game: [MagTech.effects] adds to a named bonus that the simulation reads
/// (see `MagWorldTech.bonus`). Nodes are bought with credits once the
/// company level, the earlier nodes and the delivery record allow — no
/// timers.
library;

enum MagBranch { fleet, roads, storage, economy }

/// Bonus keys the simulation reads. Fractions add up (+.05 = +5 %);
/// counts add as numbers.
abstract final class MagBonus {
  static const speed = 'speed', capacity = 'capacity', fuel = 'fuel';
  static const wear = 'wear', service = 'service', upkeep = 'upkeep';
  static const roadCost = 'roadCost', bridge = 'bridge';
  static const roadSpeed = 'roadSpeed', roadUpkeep = 'roadUpkeep';
  static const pay = 'pay', contract = 'contract', xp = 'xp';
  static const handling = 'handling';

  /// Warehouses: how many may stand, extra room in each, modes.
  static const warehouses = 'warehouses', storage = 'storage';
  static const autoSupply = 'autoSupply', distribute = 'distribute';
}

class MagTech {
  const MagTech({
    required this.id,
    required this.branch,
    required this.title,
    required this.lore,
    required this.effect,
    required this.effects,
    required this.cost,
    required this.level,
    this.requires = const [],
    this.deliveries = 0,
  });

  final String id;
  final MagBranch branch;
  final String title;

  /// A line about what it is, for the player.
  final String lore;

  /// What it changes, in words.
  final String effect;
  final Map<String, double> effects;
  final int cost;

  /// Company level needed.
  final int level;

  /// Earlier nodes needed.
  final List<String> requires;

  /// Deliveries the company must have made.
  final int deliveries;
}

abstract final class MagTechTree {
  static MagTech? byId(String id) => all.where((t) => t.id == id).firstOrNull;

  static Iterable<MagTech> of(MagBranch b) => all.where((t) => t.branch == b);

  static const all = <MagTech>[
    // ---- Автопарк ----
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
    // ---- Склады и логистика ----
    MagTech(
      id: 'storage',
      branch: MagBranch.storage,
      title: 'Складское дело',
      lore: 'Первый ангар, первые стеллажи, первый кладовщик с журналом.',
      effect: 'Открывает постройку «Склад» (1 шт.)',
      effects: {MagBonus.warehouses: 1},
      cost: 1500,
      level: 2,
    ),
    MagTech(
      id: 'autosupply',
      branch: MagBranch.storage,
      title: 'Автопополнение',
      lore:
          'Кладовщик больше не звонит — склад сам пишет заявку, когда запас тает.',
      effect: 'Режим склада «Автопополнение»',
      effects: {MagBonus.autoSupply: 1},
      cost: 2500,
      level: 3,
      requires: ['storage'],
    ),
    MagTech(
      id: 'racks',
      branch: MagBranch.storage,
      title: 'Высотные стеллажи',
      lore: 'Склад растёт вверх, а не вширь.',
      effect: 'Вместимость каждого склада +100',
      effects: {MagBonus.storage: 100},
      cost: 3000,
      level: 4,
      requires: ['storage'],
    ),
    MagTech(
      id: 'distribution',
      branch: MagBranch.storage,
      title: 'Распределительный узел',
      lore: 'Склад принимает всё и сам решает, кому отправить излишки.',
      effect: 'Режим склада «Распределение»',
      effects: {MagBonus.distribute: 1},
      cost: 4500,
      level: 5,
      requires: ['autosupply'],
    ),
    MagTech(
      id: 'forklifts',
      branch: MagBranch.storage,
      title: 'Вилочные погрузчики',
      lore:
          'Паллеты летают из кузова на полку. Машины стоят у ворот вдвое меньше.',
      effect: 'Погрузка и разгрузка +30%',
      effects: {MagBonus.handling: .3},
      cost: 3800,
      level: 6,
      requires: ['storage'],
    ),
    MagTech(
      id: 'network',
      branch: MagBranch.storage,
      title: 'Сеть складов',
      lore: 'Второй ангар на другом конце карты — и цепочки становятся короче.',
      effect: 'Ещё +1 склад',
      effects: {MagBonus.warehouses: 1},
      cost: 6000,
      level: 7,
      requires: ['racks'],
      deliveries: 80,
    ),
    MagTech(
      id: 'wms',
      branch: MagBranch.storage,
      title: 'Складская система учёта',
      lore:
          'Каждая коробка со штрихкодом. Места на полках больше, ошибок меньше.',
      effect: 'Вместимость складов +150, ещё +1 склад',
      effects: {MagBonus.storage: 150, MagBonus.warehouses: 1},
      cost: 14000,
      level: 12,
      requires: ['network', 'distribution'],
      deliveries: 250,
    ),
    MagTech(
      id: 'crossdock',
      branch: MagBranch.storage,
      title: 'Кросс-докинг',
      lore: 'Груз переходит из машины в машину, не касаясь полки.',
      effect: 'Погрузка и разгрузка ещё +40%',
      effects: {MagBonus.handling: .4},
      cost: 12000,
      level: 15,
      requires: ['forklifts'],
      deliveries: 400,
    ),
    MagTech(
      id: 'megahub',
      branch: MagBranch.storage,
      title: 'Мегахаб',
      lore:
          'Логистический город в миниатюре: десятки ворот и круглосуточная смена.',
      effect: 'Вместимость складов +300, ещё +2 склада',
      effects: {MagBonus.storage: 300, MagBonus.warehouses: 2},
      cost: 38000,
      level: 25,
      requires: ['wms', 'crossdock'],
      deliveries: 1200,
    ),
    // ---- Экономика ----
    MagTech(
      id: 'marketing',
      branch: MagBranch.economy,
      title: 'Маркетинг',
      lore:
          'Логотип на бортах и визитки у фермеров. Нам стали платить чуть больше.',
      effect: 'Оплата перевозок +4%',
      effects: {MagBonus.pay: .04},
      cost: 1600,
      level: 3,
    ),
    MagTech(
      id: 'sales',
      branch: MagBranch.economy,
      title: 'Отдел продаж',
      lore: 'Менеджер, который умеет торговаться. Контракты стали жирнее.',
      effect: 'Награды за контракты +15%',
      effects: {MagBonus.contract: .15},
      cost: 3200,
      level: 5,
    ),
    MagTech(
      id: 'lean',
      branch: MagBranch.economy,
      title: 'Бережливое производство',
      lore: 'Убрали лишнее: простои, холостые пробеги, забытые фуры у забора.',
      effect: 'Обслуживание машин −10%',
      effects: {MagBonus.upkeep: -.1},
      cost: 3500,
      level: 6,
    ),
    MagTech(
      id: 'academy',
      branch: MagBranch.economy,
      title: 'Корпоративный университет',
      lore: 'Опытные водители учат новичков. Компания растёт быстрее.',
      effect: 'Опыт компании +10%',
      effects: {MagBonus.xp: .1},
      cost: 5000,
      level: 8,
      requires: ['lean'],
    ),
    MagTech(
      id: 'tariffs',
      branch: MagBranch.economy,
      title: 'Тарифная сетка',
      lore:
          'Цена считается по весу, срочности и расстоянию — честно и выгодно.',
      effect: 'Оплата перевозок +6%',
      effects: {MagBonus.pay: .06},
      cost: 8000,
      level: 10,
      requires: ['marketing'],
      deliveries: 120,
    ),
    MagTech(
      id: 'holding',
      branch: MagBranch.economy,
      title: 'Транспортный холдинг',
      lore: 'Совет директоров, своя биржа грузов и уважение конкурентов.',
      effect: 'Оплата +8%, контракты +15%, опыт +10%',
      effects: {MagBonus.pay: .08, MagBonus.contract: .15, MagBonus.xp: .1},
      cost: 45000,
      level: 22,
      requires: ['tariffs', 'sales', 'academy'],
      deliveries: 900,
    ),
  ];
}
