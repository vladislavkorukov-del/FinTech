/// «Магистрали»: the rules of the transport game in one place, so balance
/// changes never touch the simulation.
library;

import 'config_vehicles.dart';

enum MagCargo {
  grain,
  wood,
  ore,
  food,
  goods,

  // Stage 3 of the master plan: the first production chains.
  stone,
  planks,
  flour,
  bread,

  // Stage 5: industry.
  coal,
  clay,
  bricks,
  steel,
  parts,
}

enum MagTerrain { grass, forest, hill, river, lake }

/// Road surfaces; [none] is a cell without a road.
enum MagRoad { none, dirt, asphalt, highway, motorway }

enum MagIndustryKind {
  farm,
  sawmill,
  mine,
  foodPlant,
  factory,
  city,
  village,

  /// Built by the player (stage 2): stores any cargo.
  warehouse,

  // Master plan stage 3: first production chains.
  quarry,
  mill,
  bakery,
  lumbermill,

  // Master plan stage 5: industry.
  coalMine,
  clayPit,
  brickworks,
  steelMill,
  partsFactory,

  /// Built by the player (stage S7): orders supplies for the company's
  /// plants and the settlements around it.
  logisticsCenter,

  /// A city's great work (stage S10), built by the company's deliveries.
  megaproject,
}

/// Upgrade lines of a truck.
enum MagUpgrade { engine, body, economy, reliability }

/// The four directions on the grid: up (−y), right (+x), down, left.
abstract final class MagDir {
  static const dx = [0, 1, 0, -1], dy = [-1, 0, 1, 0];
  static int opposite(int d) => (d + 2) % 4;
}

class MagRoadSpec {
  const MagRoadSpec(this.cost, this.speed, this.level, this.upkeep);

  /// Credits per cell on grass (terrain multiplies it).
  final int cost;

  /// Speed multiplier for vehicles on it.
  final double speed;

  /// Company level that unlocks it.
  final int level;

  /// Credits per 10 cells per day.
  final int upkeep;
}

class MagIndustrySpec {
  const MagIndustrySpec({
    required this.size,
    this.produces = const {},
    this.accepts = const {},
    this.converts = const {},
    this.stores = false,
    this.ratio = const {},
    this.price = 0,
    this.near,
    this.extra = const {},
    this.buildLevel = 2,
  });

  /// More inputs used up for every unit made, besides the main one: a
  /// steel mill burns 1 coal for each steel it makes from ore.
  final Map<MagCargo, int> extra;

  /// Company level from which the player may build it.
  final int buildLevel;

  /// Does it take [c] in to make something (a main or an extra input)?
  bool takesIn(MagCargo c) => converts.containsKey(c) || extra.containsKey(c);

  /// Input units per output unit (1 when missing): a mill turns 2 grain
  /// into 1 flour.
  final Map<MagCargo, int> ratio;

  /// Price to buy it from its independent owner (0: not for sale). Building
  /// a new one costs more ([MagRules.buildFactor]).
  final int price;

  /// Terrain it must stand near to be built (a quarry by hills).
  final MagTerrain? near;

  /// A warehouse: takes any cargo into its stock and hands it out again.
  final bool stores;

  /// Footprint in cells (square).
  final int size;

  /// Raw production per day.
  final Map<MagCargo, int> produces;

  /// Cargo it takes in.
  final Set<MagCargo> accepts;

  /// Processing: each input unit becomes one unit of the output.
  final Map<MagCargo, MagCargo> converts;
}

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
  });

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

abstract final class MagRules {
  static const mapSize = 64;
  static const defaultSeed = 20261113;
  static const startMoney = 6000;

  /// Fixed step: 10 ticks per second at 1×, 40 ticks a day, 30 days a month.
  static const tickMs = 100;
  static const ticksPerSecond = 10;
  static const ticksPerDay = 40;
  static const daysPerMonth = 30;

  static const outputCap = 80;

  /// Store for delivered cargo at plants (orders never overfill it).
  static const inputCap = 120;

  /// An order whose truck finds no road this many days fails.
  static const orderNoRoadDays = 3;

  /// Warehouses: room before technologies, price of the first, ids kept
  /// apart from the map's places.
  static const warehouseBase = 200;
  static const warehousePrice = 3000;
  static const warehouseIdBase = 100000;

  /// Open automatic orders per warehouse rule, the smallest one sent on,
  /// and how often warehouses plan (ticks).
  static const autoOrdersPerRule = 3;
  static const minAutoBatch = 5;
  static const planEveryTicks = 20;
  static const processPerDay = 14;

  /// Loading and unloading: units per tick, and the shortest stop.
  static const handlePerTick = 4;
  static const minStopTicks = 6;

  /// A partly loaded truck leaves after this many days of waiting.
  static const partialWaitDays = 2;

  /// A truck that finds no road tries again after this many ticks.
  static const retryTicks = 20;

  static const maxUpgrade = 10;
  static const maxContracts = 3;

  /// Logistics centre: the radius it serves and the orders it keeps open,
  /// at level 1 and more with each level.
  static const centerRadius = 8, centerRadiusStep = 3;
  static const centerOrders = 3, centerOrdersStep = 2;

  /// Railways (stage S8): a cell of track on grass, a station, what each
  /// wagon costs to run and keep, how much each wagon slows a train, and
  /// how long a train waits for a blocked track before looking for
  /// another way.
  static const railCost = 60, stationPrice = 1500, stationReach = 2;
  static const wagonRunning = .08, wagonUpkeep = 1, wagonDrag = .04;
  static const trainWaitTicks = 20;

  /// The one-time reward for the first megalopolis grown from a hamlet.
  static const megapolisReward = 150000;

  /// Water (stage S9): a port, and how far from its place it may stand.
  static const portPrice = 3000, portReach = 2;

  /// Days a city waits before its next order after one ends.
  static const cityOrderPause = 4;

  static const roads = <MagRoad, MagRoadSpec>{
    MagRoad.dirt: MagRoadSpec(20, .75, 1, 1),
    MagRoad.asphalt: MagRoadSpec(55, 1, 2, 2),
    MagRoad.highway: MagRoadSpec(140, 1.3, 12, 4),
    MagRoad.motorway: MagRoadSpec(320, 1.6, 30, 7),
  };

  /// Building cost multiplier per terrain (null: not buildable).
  static double? terrainCost(MagTerrain t) => switch (t) {
    MagTerrain.grass => 1,
    MagTerrain.forest => 1.8, // clearing
    MagTerrain.hill => 2.4,
    MagTerrain.river => 6, // a bridge
    MagTerrain.lake => null,
  };

  static const industries = <MagIndustryKind, MagIndustrySpec>{
    MagIndustryKind.farm: MagIndustrySpec(
      size: 2,
      produces: {MagCargo.grain: 9},
      price: 3500,
    ),
    MagIndustryKind.sawmill: MagIndustrySpec(
      size: 2,
      produces: {MagCargo.wood: 8},
      price: 3500,
      near: MagTerrain.forest,
    ),
    MagIndustryKind.mine: MagIndustrySpec(
      size: 2,
      produces: {MagCargo.ore: 8},
      price: 6000,
      near: MagTerrain.hill,
    ),
    MagIndustryKind.foodPlant: MagIndustrySpec(
      size: 2,
      accepts: {MagCargo.grain},
      converts: {MagCargo.grain: MagCargo.food},
      price: 9000,
    ),
    MagIndustryKind.factory: MagIndustrySpec(
      size: 3,
      accepts: {MagCargo.wood, MagCargo.ore},
      converts: {MagCargo.wood: MagCargo.goods, MagCargo.ore: MagCargo.goods},
      price: 16000,
    ),
    MagIndustryKind.city: MagIndustrySpec(
      size: 3,
      accepts: {MagCargo.food, MagCargo.goods},
    ),
    MagIndustryKind.village: MagIndustrySpec(size: 2, accepts: {MagCargo.food}),
    MagIndustryKind.warehouse: MagIndustrySpec(
      size: 2,
      accepts: {...MagCargo.values},
      stores: true,
    ),
    MagIndustryKind.quarry: MagIndustrySpec(
      size: 2,
      produces: {MagCargo.stone: 7},
      price: 4000,
      near: MagTerrain.hill,
    ),
    MagIndustryKind.mill: MagIndustrySpec(
      size: 2,
      accepts: {MagCargo.grain},
      converts: {MagCargo.grain: MagCargo.flour},
      ratio: {MagCargo.grain: 2},
      price: 4500,
    ),
    MagIndustryKind.bakery: MagIndustrySpec(
      size: 2,
      accepts: {MagCargo.flour},
      converts: {MagCargo.flour: MagCargo.bread},
      price: 5000,
    ),
    MagIndustryKind.lumbermill: MagIndustrySpec(
      size: 2,
      accepts: {MagCargo.wood},
      converts: {MagCargo.wood: MagCargo.planks},
      ratio: {MagCargo.wood: 2},
      price: 4500,
    ),
    MagIndustryKind.coalMine: MagIndustrySpec(
      size: 2,
      produces: {MagCargo.coal: 7},
      price: 6500,
      near: MagTerrain.hill,
      buildLevel: 3,
    ),
    MagIndustryKind.clayPit: MagIndustrySpec(
      size: 2,
      produces: {MagCargo.clay: 8},
      price: 3000,
      near: MagTerrain.river,
    ),
    MagIndustryKind.brickworks: MagIndustrySpec(
      size: 2,
      accepts: {MagCargo.clay},
      converts: {MagCargo.clay: MagCargo.bricks},
      ratio: {MagCargo.clay: 2},
      price: 5500,
      buildLevel: 3,
    ),
    MagIndustryKind.steelMill: MagIndustrySpec(
      size: 3,
      accepts: {MagCargo.ore, MagCargo.coal},
      converts: {MagCargo.ore: MagCargo.steel},
      ratio: {MagCargo.ore: 2},
      extra: {MagCargo.coal: 1},
      price: 14000,
      buildLevel: 4,
    ),
    MagIndustryKind.partsFactory: MagIndustrySpec(
      size: 2,
      accepts: {MagCargo.steel, MagCargo.planks},
      converts: {MagCargo.steel: MagCargo.parts},
      extra: {MagCargo.planks: 1},
      price: 12000,
      buildLevel: 5,
    ),
    MagIndustryKind.logisticsCenter: MagIndustrySpec(
      size: 2,
      price: 9000,
      buildLevel: 6,
    ),
    MagIndustryKind.megaproject: MagIndustrySpec(size: 3),
  };

  /// Credits per unit per cell of distance between the two places.
  static const cargoRate = <MagCargo, double>{
    MagCargo.grain: 1.8,
    MagCargo.wood: 1.9,
    MagCargo.ore: 2.2,
    MagCargo.food: 2.9,
    MagCargo.goods: 3.8,
    MagCargo.stone: 2.0,
    MagCargo.planks: 2.6,
    MagCargo.flour: 2.4,
    MagCargo.bread: 3.2,
    MagCargo.coal: 2.1,
    MagCargo.clay: 1.7,
    MagCargo.bricks: 2.6,
    MagCargo.steel: 3.4,
    MagCargo.parts: 4.2,
  };

  /// Market price of a unit: what a buyer pays for goods the company owns,
  /// and what the company pays an independent producer for its goods.
  static const cargoValue = <MagCargo, double>{
    MagCargo.grain: 3,
    MagCargo.wood: 3.5,
    MagCargo.ore: 4.5,
    MagCargo.food: 8,
    MagCargo.goods: 12,
    MagCargo.stone: 4,
    MagCargo.planks: 9,
    MagCargo.flour: 8,
    MagCargo.bread: 13,
    MagCargo.coal: 4,
    MagCargo.clay: 2.5,
    MagCargo.bricks: 8,
    MagCargo.steel: 18,
    MagCargo.parts: 34,
  };

  /// Own production (master plan stage 3): building costs more than
  /// buying, levels 1–5 add output and storage, every level costs upkeep;
  /// processing has a small cost per unit made.
  static const buildFactor = 1.3;
  static const maxIndustryLevel = 5;
  static const levelOutput = .4, levelStorage = .5;
  static const upkeepShare = 250;
  static const processCost = .5;
  static const builtIdBase = 200000;

  static const minPayDistance = 4;

  static const trucks = magTruckModels;

  /// How much a road surface speeds a horse (hooves care little for
  /// asphalt).
  static double horseRoad(MagRoad r) => switch (r) {
    MagRoad.none => 0,
    MagRoad.dirt => 1,
    _ => 1.05,
  };

  static MagTruckModel? truck(String id) =>
      trucks.where((t) => t.id == id).firstOrNull;
}
