part of 'world.dart';

/// What the player can do. Every action keeps the item balance: a building
/// comes from a kit (or its cost in materials) and goes back as a kit with
/// everything it held.
extension FinWorldActions on FinWorld {
  bool unlocked(FinBuilding kind) {
    final need = FinConfig.specs[kind]!.unlockedBy;
    return need == null || researched.contains(need);
  }

  /// Whether the player can pay for one [kind]: a kit, or its materials.
  bool affordable(FinBuilding kind) =>
      (kits[kind] ?? 0) > 0 ||
      FinConfig.specs[kind]!.cost.entries.every(
        (e) => (inventory[e.key] ?? 0) >= e.value,
      );

  /// Why [kind] cannot be built at [x],[y], or null when it can.
  String? whyNot(FinBuilding kind, int x, int y) {
    if (!unlocked(kind)) return 'Нужно исследование';
    if (!terrain.inside(x, y)) return 'За краем карты';
    if (!terrain.buildable(x, y)) return 'Здесь скалы';
    if (machineAt(x, y) != null) return 'Клетка занята';
    if (kind == FinBuilding.drill &&
        !FinConfig.deposits.containsKey(terrain.at(x, y))) {
      return 'Буровую ставят на месторождение';
    }
    if (!affordable(kind)) return 'Не хватает материалов';
    return null;
  }

  FinMachine? place(FinBuilding kind, int x, int y, {int dir = 1}) {
    if (whyNot(kind, x, y) != null) return null;
    if ((kits[kind] ?? 0) > 0) {
      kits[kind] = kits[kind]! - 1;
    } else {
      FinConfig.specs[kind]!.cost.forEach((i, n) {
        _takeInventory(i, n);
        _note(destroyed, i, n);
      });
    }
    final m = FinMachine(id: nextId++, kind: kind, x: x, y: y, dir: dir & 3);
    machines[m.id] = m;
    _cells[y * terrain.width + x] = m.id;
    if (kind == FinBuilding.lab) _autoResearch(m);
    _beltsDirty = true;
    return m;
  }

  /// A straight run of belt from one cell to another, turning once (first
  /// along the longer axis). Cells already holding a belt are re-aimed,
  /// other occupied cells stop the line. Returns how many were placed.
  int placeBeltLine(
    int x0,
    int y0,
    int x1,
    int y1, {
    FinBuilding kind = FinBuilding.belt,
  }) {
    final path = beltPath(x0, y0, x1, y1);
    var placed = 0;
    for (final (x, y, dir) in path) {
      final there = machineAt(x, y);
      if (there != null) {
        if (!there.isBelt) break;
        there.dir = dir;
        _beltsDirty = true;
        continue;
      }
      if (place(kind, x, y, dir: dir) == null) break;
      placed++;
    }
    return placed;
  }

  /// The cells and directions of a belt line (for preview and building).
  List<(int, int, int)> beltPath(int x0, int y0, int x1, int y1) {
    final out = <(int, int, int)>[];
    final dx = x1 - x0, dy = y1 - y0;
    final horizontalFirst = dx.abs() >= dy.abs();
    var x = x0, y = y0;
    void run(int tx, int ty) {
      while (x != tx || y != ty) {
        final dir = tx > x
            ? 1
            : tx < x
            ? 3
            : ty > y
            ? 2
            : 0;
        out.add((x, y, dir));
        x += FinDir.dx[dir];
        y += FinDir.dy[dir];
      }
    }

    if (horizontalFirst) {
      run(x1, y0);
      run(x1, y1);
    } else {
      run(x0, y1);
      run(x1, y1);
    }
    // The last cell keeps the direction of the run into it.
    final last = out.isEmpty ? 1 : out.last.$3;
    out.add((x1, y1, last));
    return out;
  }

  void rotate(int id) {
    final m = machines[id];
    if (m == null) return;
    m.dir = FinDir.turn(m.dir);
    _beltsDirty = true;
  }

  /// Takes a building down: its kit and everything it held (a craft in
  /// progress returns its inputs) go back to the player.
  bool remove(int id) {
    final m = machines.remove(id);
    if (m == null) return false;
    _cells[m.y * terrain.width + m.x] = null;
    kits[m.kind] = (kits[m.kind] ?? 0) + 1;
    m.contents().forEach(_giveInventory);
    _beltsDirty = true;
    return true;
  }

  /// Picks an assembler's (or furnace's) recipe. Inputs that the new recipe
  /// does not use, and a craft in progress, go back to the player.
  bool setRecipe(int id, String? recipe) {
    final m = machines[id];
    final r = FinConfig.recipe(recipe);
    if (m == null || (recipe != null && (r == null || r.machine != m.kind))) {
      return false;
    }
    if (m.recipe == recipe) return true;
    final c = FinConfig.recipe(m.crafting);
    if (c != null) c.inputs.forEach(_giveInventory);
    m.crafting = null;
    m.progress = 0;
    for (final i in m.input.keys.toList()) {
      if (r == null || !r.inputs.containsKey(i)) {
        _giveInventory(i, m.input.remove(i)!);
      }
    }
    m.recipe = recipe;
    return true;
  }

  /// Puts items from the inventory into a machine (fuel, ore, circuits).
  int insert(int id, FinItem item, int n) {
    final m = machines[id];
    if (m == null || m.isBelt) return 0;
    var moved = 0;
    while (moved < n && (inventory[item] ?? 0) > 0 && accept(m, item)) {
      _takeInventory(item, 1);
      moved++;
    }
    return moved;
  }

  /// Takes items out of a machine's buffers into the inventory.
  int collect(int id, FinItem item, int n) {
    final m = machines[id];
    if (m == null) return 0;
    var moved = 0;
    for (final buffer in [m.output, m.input]) {
      while (moved < n && (buffer[item] ?? 0) > 0) {
        m.take(buffer, item);
        _giveInventory(item, 1);
        moved++;
      }
    }
    return moved;
  }

  /// Starts a technology in a lab, if it can be researched now.
  bool startResearch(int labId, String techId) {
    final m = machines[labId];
    final tech = FinConfig.tech(techId);
    if (m == null || m.kind != FinBuilding.lab || tech == null) return false;
    if (!canResearch(tech)) return false;
    m.researching = tech.id;
    m.progress = 0;
    return true;
  }

  bool canResearch(FinTech tech) =>
      tech.implemented &&
      !researched.contains(tech.id) &&
      tech.requires.every(researched.contains);

  void _autoResearch(FinMachine lab) {
    for (final t in FinConfig.research) {
      if (canResearch(t)) {
        lab.researching = t.id;
        return;
      }
    }
  }

  void _takeInventory(FinItem i, int n) {
    final left = (inventory[i] ?? 0) - n;
    if (left < 0) throw StateError('Not enough $i');
    if (left == 0) {
      inventory.remove(i);
    } else {
      inventory[i] = left;
    }
  }

  void _giveInventory(FinItem i, int n) {
    if (n > 0) inventory[i] = (inventory[i] ?? 0) + n;
  }
}
