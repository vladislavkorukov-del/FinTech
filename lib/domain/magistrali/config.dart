/// «Магистрали»: the rules of the transport game in one place, so balance
/// changes never touch the simulation.
library;

import 'config_industries.dart';
import 'config_vehicles.dart';

export 'config_vehicles.dart' show MagTruckModel;

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

  // Stage S11: people travelling between settlements.
  passengers,

  // Stage S13: people going to work at businesses (PASS-05).
  workers,

  // Stage S17: oil and fuel (PROD-11), electronics (PROD-12).
  oil,
  fuel,
  electronics,

  // Stage S21: machine tools (PROD-10).
  machines;

  /// Liquids: carried only in tanks (a tanker, rail or a vessel; VEH-05).
  bool get liquid => this == oil || this == fuel;

  /// People, not goods: carried by coaches, buses, trains and vessels.
  bool get people => this == passengers || this == workers;
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

  // Stage S17: oil, fuel and electronics.
  oilWell,
  refinery,
  electronicsPlant,

  // Stage S21: machine-tool works, built by the player (PROD-10).
  machineWorks,

  // Stage S23: resorts, built by the player (TOUR-01).
  lakeResort,
  skiResort,
}

/// Upgrade lines of a truck.
enum MagUpgrade { engine, body, economy, reliability }

/// The four directions on the grid: up (−y), right (+x), down, left.
abstract final class MagDir {
  static const dx = [0, 1, 0, -1], dy = [-1, 0, 1, 0];
  static int opposite(int d) => (d + 2) % 4;
}

class MagRoadSpec {
  const MagRoadSpec(
    this.cost,
    this.speed,
    this.level,
    this.upkeep,
    this.capacity,
  );

  /// Vehicles a day a cell of it carries before it slows down (ROAD-08).
  final int capacity;

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
    this.tech,
  });

  /// The technology that opens building it (TECH-10, 1.83); null: none.
  final String? tech;

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

abstract final class MagRules {
  static const mapSize = 64;

  /// The map of new games from 1.83 (generator 5): three times the land.
  static const bigMapSize = 112;
  static const defaultSeed = 20261113;
  static const startMoney = 6000;

  /// S16: one raw producer in [richOneIn] sits on a rich deposit
  /// ([richYield]); depots — price, the wear they repair from, the share of
  /// the repair price paid there, and the upkeep cut each brings.
  static const richOneIn = 6, richYield = 1.5;

  /// S17: refrigerated fresh food pays more; waiting passengers leave a
  /// share a day; complexes — reach, output bonus, conveyor a day;
  /// terminals — price and market bonus each; vessel hulls.
  static const reeferBonus = 1.15, waitLeave = .2;

  /// S18: a share of passengers at a hub rides on; paint; auctions —
  /// every so many days, start share of the price, daily rise, days;
  /// regions — the price step; by-products of processing.
  static const transferShare = .3, paintPrice = 300;

  /// S19: rivals — from this level, every so many days a place, their cut
  /// of the pay where they serve, income and value; megalopolis stars;
  /// reputation; the collection; the overdraft.
  static const rivalLevel = 5, rivalEvery = 6, rivalCut = .2;
  static const rivalIncome = 400, rivalBase = 20000, rivalPerClaim = 9000;
  static const starDays = 20, starBonus = .05, reputationMax = .1;
  static const collectionSteps = [(5, 3000), (10, 10000), (15, 25000)];
  static const veteranAfter = 8, veteranBonus = 1.1;

  /// Stage S20: how far a chain's input may lie for the map to count as
  /// viable; mountain ranges (hill cells) and their yield; the region's
  /// speciality yield for own producers; a multimodal terminal's room.
  static const chainReach = 70, mountainCells = 25, mountainYield = 1.2;
  static const regionYield = 1.1, multimodalRoom = 1.5;

  /// Stage S21: subsidies of cities (CONT-10).
  static const subsidyLevel = 4, subsidyEvery = 9, subsidyDays = 25;
  static const subsidyBonus = .4;

  /// Stage S22: an airport's price.
  static const airportPrice = 25000;

  /// Chance of an event on a day, percent.
  static const eventChance = 12;

  /// Stage S23: disasters and repairs; shares.
  static const disasterLevel = 4, repairDays = 6, crewRepairDays = 2;
  static const crewReach = 10, repairBase = 400;
  static const shares = 1000, controlShares = 510;
  static const touristPay = 1.6, touristPeak = 1.5;

  /// Stage S24: bonds (monthly coupon, term, share of the company's value
  /// the market takes), insurance.
  static const bondCoupon = .015, bondDays = 180, bondShare = .5;
  static const premiumMin = 500, premiumShare = .003, insurancePayout = 1500;

  /// Stage S25: container terminals (price, how much faster vessels load,
  /// what containers add to pay), signals, interchanges, mortgages (per
  /// town level, days, return, faster growth), night shifts.
  static const containerTerminalPrice = 30000, terminalHandling = 3;
  static const containerBonus = 1.2;
  static const signalPrice = 1500, signalBlock = 40;
  static const interchangePrice = 6000;
  static const mortgagePerLevel = 15000, mortgageDays = 180;
  static const mortgageReturn = 1.3, mortgageGrowth = 1.6;
  static const nightBonus = .3, nightWage = 40;

  /// Stage S26: metro (town level, price, passengers, growth, fare per
  /// resident a day), yards and hubs, futures, excursions.
  static const metroLevel = 8, metroPrice = 120000;
  static const metroPassengers = 1.5, metroGrowth = 1.2, metroFare = .02;
  static const yardPrice = 20000, yardHandling = 2.0;
  static const hubPrice = 25000, hubHandling = 2.0, hubRoom = 1.5;
  static const futuresLevel = 12, futuresMax = 3, futureDays = 30;
  static const futureMargin = .15, futurePremium = .45;
  static const excursionPay = 1.5;

  /// Stage S28: bridges and overpasses (longest span, price a cell),
  /// interchanges, street trams.
  static const maxSpan = 14, spanCost = 900;
  static const overpassPrice = 15000, cloverPrice = 40000;
  static const roundaboutPrice = 12000;
  static const turbinePrice = 55000, stackPrice = 80000; // S29
  static const metroLineCell = 3000, metroLineReach = 40;
  static const metroLineFare = .01, metroLineGrowth = .1;
  static const tramTownLevel = 4, tramStreetPay = 1.25;
  static const overdraftRate = .01, crisisDays = 30;
  static const auctionEvery = 10, auctionStart = .7, auctionRise = .05;
  static const auctionDays = 5, regionPrice = 15000;
  static const byProducts = <MagIndustryKind, (MagCargo, double)>{
    MagIndustryKind.steelMill: (MagCargo.stone, .25),
    MagIndustryKind.brickworks: (MagCargo.stone, .2),
    MagIndustryKind.refinery: (MagCargo.coal, .25),
  };
  static const complexReach = 5, complexBonus = .15, conveyorPerDay = 20;
  static const terminalPrice = 3000, terminalBonus = .05;
  static const maxHull = 3, hullCapacity = .15;
  static const depotPrice = 4000, depotWear = 30;
  static const depotService = .7, depotUpkeepCut = .05;

  /// Loans (FIN-15): the bank lends this plus so much a company level, at
  /// this interest a day on the debt.
  static const loanBase = 10000, loanPerLevel = 5000, loanRate = .004;

  /// The big map (S12): a new company starts with more, the first bridge
  /// in mind; contracts reach this far from the start, plus 2 cells a level.
  static const startMoneyBig = 8000, contractReach = 22;

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

  /// Passengers (stage S11): people per day per this many inhabitants of a
  /// settlement with a stop, and how many days of them may wait.
  /// Workers (PASS-05): one a day per this many people, kept up to
  /// [workerDays]; a business wants [staffPerCell] per cell of its land for
  /// the full bonus [staffBonus]; staff fade by [staffFade] a day.
  static const peoplePerWorker = 80, workerDays = 3, staffPerCell = 2;
  static const staffBonus = .3, staffFade = .8;

  static const peoplePerTraveller = 40, passengerDays = 3;

  /// Market prices (stage S11): a flooded market pays up to 30% less, a
  /// shortage of what a settlement needs pays 25% more; the flood fades
  /// by this share a day.
  static const glutDiscount = .3, deficitBonus = .25, glutFade = .9;

  /// The one-time reward for the first megalopolis grown from a hamlet.
  static const megapolisReward = 150000;

  /// Water (stage S9): a port, and how far from its place it may stand.
  /// Share of the building price returned when a road or track is taken
  /// away (ROAD-05, 1.83).
  static const demolishRefund = .3;

  static const portPrice = 3000, portReach = 2;

  /// Days a city waits before its next order after one ends.
  static const cityOrderPause = 4;

  static const roads = <MagRoad, MagRoadSpec>{
    MagRoad.dirt: MagRoadSpec(20, .75, 1, 1, 24),
    MagRoad.asphalt: MagRoadSpec(55, 1, 2, 2, 48),
    MagRoad.highway: MagRoadSpec(140, 1.3, 12, 4, 96),
    MagRoad.motorway: MagRoadSpec(320, 1.6, 30, 7, 192),
  };

  /// Building cost multiplier per terrain (null: not buildable).
  static double? terrainCost(MagTerrain t) => switch (t) {
    MagTerrain.grass => 1,
    MagTerrain.forest => 1.8, // clearing
    // Through hills a way is a tunnel, over a river a bridge — both cost
    // far more than a road on the flat (stage S11).
    MagTerrain.hill => 7, // a tunnel
    MagTerrain.river => 9, // a bridge
    MagTerrain.lake => null,
  };

  static const industries = magIndustrySpecs;

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
    MagCargo.passengers: 3.0,
    MagCargo.workers: 2.4,
    MagCargo.oil: 2.4,
    MagCargo.fuel: 3.4,
    MagCargo.electronics: 6.0,
    MagCargo.machines: 7.0,
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
    MagCargo.passengers: 0,
    MagCargo.workers: 0,
    MagCargo.oil: 6,
    MagCargo.fuel: 14,
    MagCargo.electronics: 90,
    MagCargo.machines: 120,
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
