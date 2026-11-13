import 'config.dart';

/// Why a machine is (not) working, shown in its inspector.
enum FinStatus {
  working,
  noInput,
  noPower,
  outputBlocked,
  done,
  needsSetup,
  idle,
}

/// One item lying on a belt, [pos] in 1/20 of the cell from its entry.
class FinBeltItem {
  FinBeltItem(this.item, this.pos);
  final FinItem item;
  int pos;
}

/// A building on the map. Mutable: the simulation owns and updates it.
class FinMachine {
  FinMachine({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    this.dir = 1,
    this.recipe,
  });

  final int id;
  final FinBuilding kind;
  final int x, y;
  int dir;

  /// Chosen recipe (assembler; a furnace sets its own from the ore).
  String? recipe;

  final Map<FinItem, int> input = {};
  final Map<FinItem, int> output = {};

  /// The recipe being made right now (its inputs are already taken) and
  /// how far along it is, in [FinRules.work] per tick at full power.
  String? crafting;
  int progress = 0;

  /// Generators: energy left from the biomass being burnt (power-ticks).
  int energy = 0;

  /// Labs: the research being worked on.
  String? researching;

  /// Belts: items on this cell, front first.
  final List<FinBeltItem> items = [];

  /// Updated every tick for the inspector (not saved).
  FinStatus status = FinStatus.idle;

  /// Share of the power asked for that was available, 0..1000.
  int powered = 0;

  bool get isBelt => kind == FinBuilding.belt || kind == FinBuilding.fastBelt;
  int get frontX => x + FinDir.dx[dir];
  int get frontY => y + FinDir.dy[dir];
  FinBuildingSpec get spec => FinConfig.specs[kind]!;

  int count(Map<FinItem, int> m) => m.values.fold(0, (a, b) => a + b);

  void add(Map<FinItem, int> m, FinItem item, [int n = 1]) =>
      m[item] = (m[item] ?? 0) + n;

  void take(Map<FinItem, int> m, FinItem item, [int n = 1]) {
    final left = (m[item] ?? 0) - n;
    if (left < 0) throw StateError('Taking a missing item');
    if (left == 0) {
      m.remove(item);
    } else {
      m[item] = left;
    }
  }

  /// Every item this building holds, counting a craft in progress as the
  /// inputs it has taken (used for the balance check and for refunds).
  Map<FinItem, int> contents() {
    final out = <FinItem, int>{};
    void put(FinItem i, int n) => out[i] = (out[i] ?? 0) + n;
    input.forEach(put);
    output.forEach(put);
    for (final b in items) {
      put(b.item, 1);
    }
    final r = FinConfig.recipe(crafting);
    if (r != null) r.inputs.forEach(put);
    return out;
  }
}
