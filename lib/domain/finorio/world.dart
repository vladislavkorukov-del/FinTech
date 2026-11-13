import 'dart:convert';

import 'config.dart';
import 'entities.dart';
import 'terrain.dart';

part 'world_actions.dart';
part 'world_tasks.dart';
part 'world_save.dart';

/// One Finorio factory: the map, buildings, the player's inventory and the
/// fixed-step simulation. Pure Dart; the screen only draws it and sends
/// actions. Every tick visits buildings in id order and belts downstream
/// first, so the same state always gives the same result.
class FinWorld {
  FinWorld({required this.seed, FinTerrainMap? terrain})
    : terrain = terrain ?? FinTerrainMap.generate(seed) {
    _cells = List<int?>.filled(this.terrain.width * this.terrain.height, null);
    cameraX = this.terrain.width / 2 + .5;
    cameraY = this.terrain.height / 2 + .5;
  }

  /// A new factory with the starter kit.
  factory FinWorld.start(int seed) {
    final w = FinWorld(seed: seed);
    w.kits.addAll(FinConfig.starterBuildings);
    w.inventory.addAll(FinConfig.starterItems);
    FinConfig.starterItems.forEach(w._noteStart);
    return w;
  }

  final int seed;
  final FinTerrainMap terrain;
  late final List<int?> _cells;

  final Map<int, FinMachine> machines = {};
  int nextId = 1;
  int tick = 0;

  /// Building kits and items the player carries.
  final Map<FinBuilding, int> kits = {};
  final Map<FinItem, int> inventory = {};

  final Set<String> researched = {};
  final Set<int> tasksDone = {};

  /// Ledger for the balance check: items that entered the factory from
  /// outside (the starter kit), were made (mining, recipes) or were used
  /// up (recipe inputs, fuel, research, construction).
  final Map<FinItem, int> started = {};
  final Map<FinItem, int> created = {};
  final Map<FinItem, int> destroyed = {};

  /// Progress counters for the tasks.
  int furnaceOre = 0, labDelivered = 0;

  /// Power of the last tick, for the HUD.
  int supply = 0, demand = 0;

  /// View and settings, saved with the factory (not part of the simulation).
  late double cameraX, cameraY;
  double zoom = 1;
  bool showGrid = true, tips = true;

  /// The painted ground under the map (view only; never changes cells).
  late String terrainTheme =
      FinConfig.terrainThemes[seed % FinConfig.terrainThemes.length];

  /// Reward ids already handed to the shared wallet of the world.
  final Set<String> claimed = {};

  bool _beltsDirty = true;
  List<FinMachine> _beltOrder = const [];

  void _noteStart(FinItem i, int n) => started[i] = (started[i] ?? 0) + n;
  void _note(Map<FinItem, int> ledger, FinItem i, [int n = 1]) =>
      ledger[i] = (ledger[i] ?? 0) + n;

  FinMachine? machineAt(int x, int y) {
    if (!terrain.inside(x, y)) return null;
    final id = _cells[y * terrain.width + x];
    return id == null ? null : machines[id];
  }

  List<FinMachine> get sorted =>
      machines.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  // ---------------------------------------------------------------- tick

  /// Advances the factory by one fixed step of [FinRules.tickMs].
  void step() {
    final order = sorted;
    _power(order);
    for (final m in order) {
      _work(m);
    }
    for (final m in order) {
      if (!m.isBelt && m.output.isNotEmpty) _push(m);
    }
    for (final b in _belts()) {
      _moveBelt(b);
    }
    for (final m in order) {
      _status(m);
    }
    tick++;
    if (tick % 5 == 0) _checkTasks();
  }

  /// Whether a machine would draw power this tick.
  bool _wants(FinMachine m) {
    switch (m.kind) {
      case FinBuilding.drill:
        return m.count(m.output) < m.spec.outputCap &&
            FinConfig.deposits.containsKey(terrain.at(m.x, m.y));
      case FinBuilding.furnace:
      case FinBuilding.assembler:
        return m.crafting != null || _canStart(m);
      case FinBuilding.lab:
        final tech = FinConfig.tech(m.researching ?? '');
        return tech != null &&
            tech.cost.entries.every((e) => (m.input[e.key] ?? 0) >= e.value);
      default:
        return false;
    }
  }

  bool _canStart(FinMachine m) {
    final r = FinConfig.recipe(m.recipe);
    if (r == null) return false;
    if ((m.output[r.output] ?? 0) >= m.spec.outputCap) return false;
    return r.inputs.entries.every((e) => (m.input[e.key] ?? 0) >= e.value);
  }

  /// Generators power consumers within their radius. Generators that share
  /// a consumer form one network; each network shares its power evenly:
  /// every consumer runs at delivered / demanded.
  void _power(List<FinMachine> order) {
    final gens = order.where((m) => m.kind == FinBuilding.generator).toList();
    final consumers = order
        .where((m) => m.spec.power > 0 && m.kind != FinBuilding.generator)
        .toList();
    for (final c in consumers) {
      c.powered = 0;
    }
    // Union-find over generators.
    final parent = {for (final g in gens) g.id: g.id};
    int find(int i) {
      while (parent[i] != i) {
        i = parent[i] = parent[parent[i]!]!;
      }
      return i;
    }

    final covering = <int, List<FinMachine>>{};
    for (final c in consumers) {
      final cover = [
        for (final g in gens)
          if ((g.x - c.x).abs() <= FinRules.generatorRadius &&
              (g.y - c.y).abs() <= FinRules.generatorRadius)
            g,
      ];
      covering[c.id] = cover;
      for (var i = 1; i < cover.length; i++) {
        final a = find(cover[0].id), b = find(cover[i].id);
        if (a != b) parent[a > b ? a : b] = a < b ? a : b;
      }
    }
    final need = <int, int>{};
    final members = <int, List<FinMachine>>{};
    for (final c in consumers) {
      final cover = covering[c.id]!;
      if (cover.isEmpty || !_wants(c)) continue;
      final net = find(cover.first.id);
      need[net] = (need[net] ?? 0) + c.spec.power;
      (members[net] ??= []).add(c);
    }
    supply = 0;
    demand = 0;
    for (final g in gens) {
      final fuelled = g.energy > 0 || (g.input[FinItem.biomass] ?? 0) > 0;
      if (fuelled) supply += g.spec.power;
    }
    final perNet = <int, int>{};
    for (final g in gens) {
      final net = find(g.id);
      var left = (need[net] ?? 0) - (perNet[net] ?? 0);
      if (left <= 0) continue;
      final give = left < g.spec.power ? left : g.spec.power;
      if (g.energy < give && (g.input[FinItem.biomass] ?? 0) > 0) {
        g.take(g.input, FinItem.biomass);
        _note(destroyed, FinItem.biomass);
        g.energy +=
            g.spec.power * FinRules.biomassSeconds * FinRules.ticksPerSecond;
      }
      final delivered = give < g.energy ? give : g.energy;
      g.energy -= delivered;
      perNet[net] = (perNet[net] ?? 0) + delivered;
    }
    for (final e in members.entries) {
      final asked = need[e.key]!;
      demand += asked;
      final got = perNet[e.key] ?? 0;
      final share = got >= asked ? FinRules.work : got * FinRules.work ~/ asked;
      for (final c in e.value) {
        c.powered = share;
      }
    }
  }

  void _work(FinMachine m) {
    switch (m.kind) {
      case FinBuilding.drill:
        final ore = FinConfig.deposits[terrain.at(m.x, m.y)];
        if (ore == null || m.powered == 0 || !_wants(m)) return;
        m.progress += m.powered;
        if (m.progress >= FinRules.mineTicks * FinRules.work) {
          m.progress -= FinRules.mineTicks * FinRules.work;
          m.add(m.output, ore);
          _note(created, ore);
        }
      case FinBuilding.furnace:
      case FinBuilding.assembler:
        if (m.crafting == null) {
          if (m.powered == 0 || !_canStart(m)) return;
          final r = FinConfig.recipe(m.recipe)!;
          r.inputs.forEach((i, n) => m.take(m.input, i, n));
          m.crafting = r.id;
          m.progress = 0;
        }
        if (m.powered == 0) return;
        final r = FinConfig.recipe(m.crafting)!;
        m.progress += m.powered;
        if (m.progress >= r.ticks * FinRules.work) {
          r.inputs.forEach((i, n) => _note(destroyed, i, n));
          m.add(m.output, r.output);
          _note(created, r.output);
          m.crafting = null;
          m.progress = 0;
        }
      case FinBuilding.lab:
        final tech = FinConfig.tech(m.researching ?? '');
        if (tech == null || m.powered == 0 || !_wants(m)) return;
        m.progress += m.powered;
        if (m.progress >=
            tech.seconds * FinRules.ticksPerSecond * FinRules.work) {
          tech.cost.forEach((i, n) {
            m.take(m.input, i, n);
            _note(destroyed, i, n);
          });
          researched.add(tech.id);
          m.researching = null;
          m.progress = 0;
        }
      default:
        break;
    }
  }

  /// A machine hands one finished item per tick to what is in front of it.
  void _push(FinMachine m) {
    final item = m.output.keys.first;
    final target = machineAt(m.frontX, m.frontY);
    if (target == null) return;
    if (target.isBelt) {
      if (target.dir == FinDir.opposite(m.dir)) return; // it feeds us
      if (!_beltHasRoomAtEntry(target)) return;
      m.take(m.output, item);
      target.items.add(FinBeltItem(item, 0));
    } else if (accept(target, item)) {
      m.take(m.output, item);
    }
  }

  bool _beltHasRoomAtEntry(FinMachine b) =>
      b.items.isEmpty || b.items.last.pos >= FinRules.beltSpacing;

  /// Whether [m] takes [item] into its input (and takes it if so).
  bool accept(FinMachine m, FinItem item) {
    final cap = m.spec.inputCap;
    switch (m.kind) {
      case FinBuilding.storage:
        if (m.count(m.input) >= FinRules.storageCapacity) return false;
      case FinBuilding.generator:
        if (item != FinItem.biomass || m.count(m.input) >= cap) return false;
      case FinBuilding.furnace:
        var r = FinConfig.recipe(m.recipe);
        if (r == null || !r.inputs.containsKey(item)) {
          // A furnace switches to the ore it is given once it is empty.
          final other = FinConfig.recipesFor(
            FinBuilding.furnace,
          ).where((x) => x.inputs.containsKey(item)).firstOrNull;
          if (other == null ||
              m.input.isNotEmpty ||
              m.crafting != null ||
              m.output.isNotEmpty) {
            return false;
          }
          m.recipe = other.id;
          r = other;
        }
        if ((m.input[item] ?? 0) >= cap) return false;
        furnaceOre++;
      case FinBuilding.assembler:
        final r = FinConfig.recipe(m.recipe);
        if (r == null || !r.inputs.containsKey(item)) return false;
        if ((m.input[item] ?? 0) >= cap) return false;
      case FinBuilding.lab:
        final tech = FinConfig.tech(m.researching ?? '');
        final want = tech?.cost[item] ?? 0;
        if ((m.input[item] ?? 0) >= want) return false;
        labDelivered++;
      default:
        return false;
    }
    m.add(m.input, item);
    return true;
  }

  // --------------------------------------------------------------- belts

  /// The belt an item leaves [b] onto, if any (belts never feed backwards).
  FinMachine? _nextBelt(FinMachine b) {
    final t = machineAt(b.frontX, b.frontY);
    if (t == null || !t.isBelt || t.dir == FinDir.opposite(b.dir)) return null;
    return t;
  }

  /// Belts ordered so that each moves before the one feeding it.
  List<FinMachine> _belts() {
    if (!_beltsDirty) return _beltOrder;
    final belts = sorted.where((m) => m.isBelt).toList();
    final state = <int, int>{};
    final order = <FinMachine>[];
    for (final start in belts) {
      if (state.containsKey(start.id)) continue;
      final path = <FinMachine>[];
      FinMachine? b = start;
      while (b != null && !state.containsKey(b.id)) {
        state[b.id] = 1;
        path.add(b);
        b = _nextBelt(b);
      }
      for (final p in path.reversed) {
        state[p.id] = 2;
        order.add(p);
      }
    }
    _beltOrder = order;
    _beltsDirty = false;
    return order;
  }

  void _moveBelt(FinMachine b) {
    if (b.items.isEmpty) return;
    final speed = FinRules.beltSpeed[b.kind]!;
    const length = FinRules.beltLength, gap = FinRules.beltSpacing;
    final lead = b.items.first;
    // An item rests at most just short of the edge: with half a cell
    // between items a cell then holds two, never three.
    var limit = length - 1;
    if (lead.pos + speed >= length) {
      if (_handOff(b, lead.item, lead.pos + speed - length)) {
        b.items.removeAt(0);
      } else {
        lead.pos = length - 1;
      }
    }
    for (var i = 0; i < b.items.length; i++) {
      final it = b.items[i];
      final cap = i == 0 ? limit : b.items[i - 1].pos - gap;
      final next = it.pos + speed;
      it.pos = next < cap ? next : (cap > it.pos ? cap : it.pos);
      if (i == 0) limit = it.pos;
    }
  }

  bool _handOff(FinMachine b, FinItem item, int over) {
    final next = _nextBelt(b);
    if (next != null) {
      if (!_beltHasRoomAtEntry(next)) return false;
      final room = next.items.isEmpty
          ? over
          : next.items.last.pos - FinRules.beltSpacing;
      next.items.add(FinBeltItem(item, over < room ? over : room));
      return true;
    }
    final t = machineAt(b.frontX, b.frontY);
    if (t == null || t.isBelt) return false;
    return accept(t, item);
  }

  void _status(FinMachine m) {
    final blocked =
        m.spec.outputCap > 0 && m.count(m.output) >= m.spec.outputCap;
    m.status = switch (m.kind) {
      FinBuilding.belt || FinBuilding.fastBelt =>
        m.items.isNotEmpty && m.items.first.pos >= FinRules.beltLength - 1
            ? FinStatus.outputBlocked
            : m.items.isEmpty
            ? FinStatus.idle
            : FinStatus.working,
      FinBuilding.storage =>
        m.count(m.input) >= FinRules.storageCapacity
            ? FinStatus.outputBlocked
            : FinStatus.idle,
      FinBuilding.generator =>
        m.energy > 0 || (m.input[FinItem.biomass] ?? 0) > 0
            ? FinStatus.working
            : FinStatus.noInput,
      FinBuilding.drill =>
        blocked
            ? FinStatus.outputBlocked
            : m.powered == 0
            ? FinStatus.noPower
            : FinStatus.working,
      FinBuilding.lab =>
        m.researching == null
            ? (researched.isNotEmpty ? FinStatus.done : FinStatus.needsSetup)
            : !_wants(m)
            ? FinStatus.noInput
            : m.powered == 0
            ? FinStatus.noPower
            : FinStatus.working,
      _ =>
        m.recipe == null
            ? (m.kind == FinBuilding.assembler
                  ? FinStatus.needsSetup
                  : FinStatus.noInput)
            : m.crafting != null
            ? (m.powered == 0 ? FinStatus.noPower : FinStatus.working)
            : blocked
            ? FinStatus.outputBlocked
            : !_canStart(m)
            ? FinStatus.noInput
            : FinStatus.noPower,
    };
  }

  /// Every item in the factory and the player's hands.
  Map<FinItem, int> totalItems() {
    final out = Map<FinItem, int>.of(inventory);
    for (final m in machines.values) {
      m.contents().forEach((i, n) => out[i] = (out[i] ?? 0) + n);
    }
    out.removeWhere((_, n) => n == 0);
    return out;
  }
}
