/// The vehicle models of the game, from the horse cart to the diesel
/// locomotive (see config.dart).
library;

class MagTruckModel {
  const MagTruckModel({
    required this.id,
    required this.name,
    required this.speed,
    required this.capacity,
    required this.price,
    required this.runningCost,
    required this.upkeep,
    required this.level,
    required this.color,
    this.horse = false,
    this.rail = false,
    this.wagonCapacity = 0,
    this.maxWagons = 0,
    this.wagonPrice = 0,
    this.water = false,
    this.passengers = false,
    this.tech,
    this.body,
  });

  /// A special body (VEH-05): 'tank' — liquids only; 'reefer' — fresh food
  /// only, paid more; 'dump' — bulk only, carries more.
  final String? body;

  /// The technology that opens buying it (VEH-04, 1.83); null: none.
  final String? tech;

  /// Carries people only (stage S11): a coach or a bus. Lorries and carts
  /// never take passengers; trains and vessels take both.
  final bool passengers;

  /// A goods vehicle on roads with an engine (not horse, rail, water or
  /// a passenger model).
  bool get motorGoods => !horse && !rail && !water && !passengers;

  /// Comfort for people (PASS-07): their fare is multiplied by it.
  double get comfort => body == 'tram'
      ? 1.25
      : horse
      ? .85
      : passengers
      ? 1.15
      : rail
      ? 1.1
      : 1;

  /// A vessel (stage S9): it sails rivers and lakes between ports.
  final bool water;
  final String id, name;

  /// A locomotive (stage S8): it runs on rails between stations and pulls
  /// wagons; its capacity is in the wagons.
  final bool rail;
  final int wagonCapacity, maxWagons, wagonPrice;

  /// Drawn by horses (era I): the road surface hardly changes its pace,
  /// it eats feed instead of fuel, and needs no engine technology.
  final bool horse;

  /// Cells per second at 1× on asphalt.
  final double speed;
  final int capacity, price;

  /// Credits per cell driven.
  final double runningCost;

  /// Credits per day.
  final int upkeep;
  final int level;
  final int color;
}

const magTruckModels = <MagTruckModel>[
  // Era I — horses.
  MagTruckModel(
    id: 'cart',
    name: 'Телега «Гнедко»',
    speed: .75,
    capacity: 6,
    price: 650,
    runningCost: .08,
    upkeep: 2,
    level: 1,
    color: 0xFF9A6A3A,
    horse: true,
  ),
  MagTruckModel(
    id: 'wagon',
    name: 'Фургон «Пара гнедых»',
    speed: .9,
    capacity: 12,
    price: 1800,
    runningCost: .14,
    upkeep: 4,
    level: 2,
    color: 0xFF6F4E37,
    horse: true,
  ),
  // Era III — trucks (open with «Двигатель внутреннего сгорания» in new
  // games; older companies have them already).
  // People (stage S11).
  MagTruckModel(
    id: 'coach',
    name: 'Экипаж «Тройка»',
    speed: .95,
    capacity: 8,
    price: 900,
    runningCost: .1,
    upkeep: 2,
    level: 2,
    color: 0xFF7A3B2E,
    horse: true,
    passengers: true,
  ),
  MagTruckModel(
    id: 'bus',
    name: 'Автобус «Ветерок»',
    speed: 1.35,
    capacity: 30,
    price: 7500,
    runningCost: .7,
    upkeep: 7,
    level: 4,
    color: 0xFFE8B23E,
    passengers: true,
  ),
  MagTruckModel(
    id: 'pickup',
    name: 'Пикап «Старт»',
    speed: 1.25,
    capacity: 10,
    price: 2200,
    runningCost: .5,
    upkeep: 4,
    level: 1,
    color: 0xFF2BB59A,
  ),
  MagTruckModel(
    id: 'lorry',
    name: 'Грузовик «Терра»',
    speed: 1.4,
    capacity: 22,
    price: 6800,
    runningCost: .9,
    upkeep: 8,
    level: 3,
    color: 0xFFE28A3B,
  ),
  MagTruckModel(
    id: 'tractor',
    name: 'Тягач «Магистраль»',
    speed: 1.6,
    capacity: 38,
    price: 16500,
    runningCost: 1.4,
    upkeep: 14,
    level: 6,
    color: 0xFF4A6FD8,
  ),
  // Trams (PASS-08, 1.90): people between settlements only.
  MagTruckModel(
    id: 'tram',
    name: 'Трамвай «Липа»',
    speed: 1.05,
    capacity: 60,
    price: 20000,
    runningCost: .3,
    upkeep: 10,
    level: 10,
    color: 0xFFD64B5C,
    passengers: true,
    tech: 'electrotransport',
    body: 'tram',
  ),
  // Special bodies (VEH-05, 1.89).
  MagTruckModel(
    id: 'tanker',
    name: 'Цистерна «Нефтевоз»',
    speed: 1.4,
    capacity: 30,
    price: 14000,
    runningCost: 1.1,
    upkeep: 12,
    level: 6,
    color: 0xFF8C6D3F,
    tech: 'petroleum',
    body: 'tank',
  ),
  MagTruckModel(
    id: 'reefer',
    name: 'Рефрижератор «Холод»',
    speed: 1.45,
    capacity: 26,
    price: 12000,
    runningCost: 1.0,
    upkeep: 11,
    level: 5,
    color: 0xFFE7EEF2,
    body: 'reefer',
  ),
  MagTruckModel(
    id: 'dumper',
    name: 'Самосвал «Карьер»',
    speed: 1.25,
    capacity: 48,
    price: 15000,
    runningCost: 1.3,
    upkeep: 13,
    level: 5,
    color: 0xFFD9A441,
    body: 'dump',
  ),
  // Modern trucks (VEH-04, 1.83): opened by technologies.
  MagTruckModel(
    id: 'semi',
    name: 'Фура «Дальнобой»',
    speed: 1.75,
    capacity: 56,
    price: 34000,
    runningCost: 1.9,
    upkeep: 20,
    level: 10,
    color: 0xFF8E3B46,
    tech: 'trailer',
  ),
  MagTruckModel(
    id: 'electric',
    name: 'Электрогрузовик «Вольт»',
    speed: 1.7,
    capacity: 44,
    price: 42000,
    runningCost: .55,
    upkeep: 16,
    level: 14,
    color: 0xFF3FA7D6,
    tech: 'hybrid',
  ),
  // Era II — railways (stage S8): a locomotive plus wagons.
  MagTruckModel(
    id: 'steam',
    name: 'Паровоз «Искра»',
    speed: 1.5,
    capacity: 0,
    price: 12000,
    runningCost: .7,
    upkeep: 10,
    level: 6,
    color: 0xFF3B3F44,
    rail: true,
    wagonCapacity: 18,
    maxWagons: 4,
    wagonPrice: 1600,
  ),
  MagTruckModel(
    id: 'diesel',
    name: 'Тепловоз «Восток»',
    speed: 2,
    capacity: 0,
    price: 30000,
    runningCost: 1.1,
    upkeep: 18,
    level: 12,
    color: 0xFFC0473F,
    rail: true,
    wagonCapacity: 24,
    maxWagons: 8,
    wagonPrice: 2400,
  ),
  // Water (stage S9): rivers and lakes, between ports.
  MagTruckModel(
    id: 'barge',
    name: 'Баржа «Волжанка»',
    speed: .9,
    capacity: 60,
    price: 9000,
    runningCost: .35,
    upkeep: 6,
    level: 8,
    color: 0xFF6F4E37,
    water: true,
  ),
  MagTruckModel(
    id: 'freighter',
    name: 'Сухогруз «Ладога»',
    speed: 1.3,
    capacity: 150,
    price: 26000,
    runningCost: .8,
    upkeep: 14,
    level: 14,
    color: 0xFF2E5E8C,
    water: true,
  ),
];
