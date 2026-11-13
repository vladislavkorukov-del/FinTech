/// Finorio game data: items, buildings, recipes, costs, research and the
/// starter kit. Balance lives here, never in the interface.
library;

/// Everything that can be carried, moved on a belt or stored.
enum FinItem {
  ironOre,
  copperOre,
  crystal,
  biomass,
  ironPlate,
  copperPlate,
  gear,
  circuit,
}

/// Building kinds. All buildings occupy one cell in this first version.
enum FinBuilding {
  drill,
  furnace,
  assembler,
  generator,
  storage,
  belt,
  fastBelt,
  lab,
}

/// Terrain of one map cell.
enum FinTerrain { ground, iron, copper, crystal, biomass, rock }

/// Directions: 0 north, 1 east, 2 south, 3 west.
abstract final class FinDir {
  static const dx = [0, 1, 0, -1], dy = [-1, 0, 1, 0];
  static int opposite(int d) => (d + 2) % 4;
  static int turn(int d) => (d + 1) % 4;
}

class FinRecipe {
  const FinRecipe(
    this.id,
    this.inputs,
    this.output,
    this.seconds,
    this.machine,
  );
  final String id;
  final Map<FinItem, int> inputs;
  final FinItem output;
  final double seconds;
  final FinBuilding machine;
  int get ticks => (seconds * 1000 / FinRules.tickMs).round();
}

class FinBuildingSpec {
  const FinBuildingSpec({
    required this.kind,
    required this.power,
    required this.cost,
    this.inputCap = 0,
    this.outputCap = 0,
    this.unlockedBy,
  });
  final FinBuilding kind;

  /// Power units drawn while working (generators: units produced).
  final int power;
  final Map<FinItem, int> cost;
  final int inputCap, outputCap;

  /// The research that makes it buildable; null when available from start.
  final String? unlockedBy;
}

class FinTech {
  const FinTech(
    this.id,
    this.cost,
    this.seconds, {
    this.requires = const [],
    this.implemented = false,
  });
  final String id;
  final Map<FinItem, int> cost;
  final double seconds;
  final List<String> requires;

  /// Only implemented technologies can be researched; the rest are listed
  /// as plans for later updates and never offered as working buttons.
  final bool implemented;
}

abstract final class FinRules {
  /// The fixed simulation step.
  static const tickMs = 100;
  static const ticksPerSecond = 1000 ~/ tickMs;
  static const mapSize = 64;
  static const chunk = 16;

  /// Mining: 1 unit every 2 seconds at full power.
  static const mineSeconds = 2.0;
  static int get mineTicks => (mineSeconds * ticksPerSecond).round();

  /// Belts: positions along a cell in 1/20 cell; items keep half a cell
  /// apart. Basic: 1 cell/s → 2 items/s. Fast: 2 cells/s → 4 items/s.
  static const beltLength = 20, beltSpacing = 10;
  static const beltSpeed = {FinBuilding.belt: 2, FinBuilding.fastBelt: 4};

  /// One biomass keeps a generator at full power for 20 seconds.
  static const biomassSeconds = 20;
  static const generatorRadius = 6;
  static const storageCapacity = 200;

  /// Work is counted in thousandths of a tick at full power.
  static const work = 1000;
}

abstract final class FinConfig {
  static const specs = <FinBuilding, FinBuildingSpec>{
    FinBuilding.drill: FinBuildingSpec(
      kind: FinBuilding.drill,
      power: 2,
      cost: {FinItem.ironPlate: 3, FinItem.gear: 3},
      outputCap: 2,
    ),
    FinBuilding.furnace: FinBuildingSpec(
      kind: FinBuilding.furnace,
      power: 2,
      cost: {FinItem.ironPlate: 5},
      inputCap: 10,
      outputCap: 10,
    ),
    FinBuilding.assembler: FinBuildingSpec(
      kind: FinBuilding.assembler,
      power: 3,
      cost: {FinItem.ironPlate: 4, FinItem.gear: 4, FinItem.circuit: 2},
      inputCap: 10,
      outputCap: 10,
    ),
    FinBuilding.generator: FinBuildingSpec(
      kind: FinBuilding.generator,
      power: 12,
      cost: {FinItem.ironPlate: 6, FinItem.gear: 2},
      inputCap: 20,
    ),
    FinBuilding.storage: FinBuildingSpec(
      kind: FinBuilding.storage,
      power: 0,
      cost: {FinItem.ironPlate: 6},
    ),
    FinBuilding.belt: FinBuildingSpec(
      kind: FinBuilding.belt,
      power: 0,
      cost: {FinItem.ironPlate: 1, FinItem.gear: 1},
    ),
    FinBuilding.fastBelt: FinBuildingSpec(
      kind: FinBuilding.fastBelt,
      power: 0,
      cost: {FinItem.gear: 2, FinItem.circuit: 1},
      unlockedBy: 'logistics',
    ),
    FinBuilding.lab: FinBuildingSpec(
      kind: FinBuilding.lab,
      power: 2,
      cost: {FinItem.ironPlate: 6, FinItem.circuit: 4},
      inputCap: 10,
    ),
  };

  static const recipes = <FinRecipe>[
    FinRecipe(
      'iron_plate',
      {FinItem.ironOre: 2},
      FinItem.ironPlate,
      4,
      FinBuilding.furnace,
    ),
    FinRecipe(
      'copper_plate',
      {FinItem.copperOre: 2},
      FinItem.copperPlate,
      4,
      FinBuilding.furnace,
    ),
    FinRecipe(
      'gear',
      {FinItem.ironPlate: 2},
      FinItem.gear,
      4,
      FinBuilding.assembler,
    ),
    FinRecipe(
      'circuit',
      {FinItem.copperPlate: 1, FinItem.crystal: 1},
      FinItem.circuit,
      6,
      FinBuilding.assembler,
    ),
  ];
  static FinRecipe? recipe(String? id) =>
      recipes.where((r) => r.id == id).firstOrNull;
  static List<FinRecipe> recipesFor(FinBuilding machine) =>
      recipes.where((r) => r.machine == machine).toList();

  /// What a drill mines on each deposit.
  static const deposits = <FinTerrain, FinItem>{
    FinTerrain.iron: FinItem.ironOre,
    FinTerrain.copper: FinItem.copperOre,
    FinTerrain.crystal: FinItem.crystal,
    FinTerrain.biomass: FinItem.biomass,
  };

  /// Enough to finish the tutorial twice over, so a wrong build can always
  /// be taken down and rebuilt.
  static const starterBuildings = <FinBuilding, int>{
    FinBuilding.drill: 6,
    FinBuilding.furnace: 4,
    FinBuilding.assembler: 3,
    FinBuilding.generator: 2,
    FinBuilding.storage: 2,
    FinBuilding.belt: 80,
    FinBuilding.lab: 1,
  };
  static const starterItems = <FinItem, int>{FinItem.biomass: 30};

  static const research = <FinTech>[
    FinTech('logistics', {FinItem.circuit: 5}, 10, implemented: true),
    FinTech('mining', {FinItem.circuit: 20}, 30, requires: ['logistics']),
    FinTech(
      'express_belts',
      {FinItem.circuit: 30},
      40,
      requires: ['logistics'],
    ),
    FinTech('inserters', {FinItem.circuit: 30}, 40, requires: ['logistics']),
    FinTech('sorters', {FinItem.circuit: 50}, 60, requires: ['inserters']),
    FinTech('power_grid', {FinItem.circuit: 40}, 50, requires: ['logistics']),
    FinTech('solar', {FinItem.circuit: 80}, 80, requires: ['power_grid']),
    FinTech('batteries', {FinItem.circuit: 80}, 80, requires: ['power_grid']),
    FinTech(
      'auto_logistics',
      {FinItem.circuit: 120},
      120,
      requires: ['sorters'],
    ),
    FinTech(
      'robots',
      {FinItem.circuit: 200},
      180,
      requires: ['auto_logistics', 'batteries'],
    ),
    FinTech('rail', {FinItem.circuit: 160}, 150, requires: ['express_belts']),
    FinTech(
      'quantum',
      {FinItem.circuit: 500},
      300,
      requires: ['robots', 'solar'],
    ),
  ];

  /// Painted ground themes for the whole map (Finorio_Terrain_Backgrounds).
  static const terrainThemes = [
    'meadow',
    'quarry',
    'canyon',
    'wetlands',
    'tundra',
    'volcanic',
  ];

  static FinTech? tech(String id) =>
      research.where((t) => t.id == id).firstOrNull;
}
