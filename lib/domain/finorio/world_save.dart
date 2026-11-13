part of 'world.dart';

/// Versioned JSON of a factory. Loading rebuilds the map from its seed and
/// checks every building and item, so a broken file is refused whole
/// instead of producing an inconsistent factory.
extension FinWorldSave on FinWorld {
  static const version = 1;

  Map<String, Object?> toJson() => {
    'version': version,
    'seed': seed,
    'size': terrain.width,
    'terrain': base64Encode(terrain.bytes),
    'biomes': base64Encode(terrain.biomeBytes),
    'tick': tick,
    'nextId': nextId,
    'kits': {for (final e in kits.entries) e.key.name: e.value},
    'inventory': _items(inventory),
    'researched': researched.toList()..sort(),
    'tasks': tasksDone.toList()..sort(),
    'started': _items(started),
    'created': _items(created),
    'destroyed': _items(destroyed),
    'furnaceOre': furnaceOre,
    'labDelivered': labDelivered,
    'camera': [cameraX, cameraY, zoom],
    'settings': {'grid': showGrid, 'tips': tips, 'theme': terrainTheme},
    'claimed': claimed.toList()..sort(),
    'machines': [
      for (final m in sorted)
        {
          'id': m.id,
          'kind': m.kind.name,
          'x': m.x,
          'y': m.y,
          'dir': m.dir,
          if (m.recipe != null) 'recipe': m.recipe,
          if (m.input.isNotEmpty) 'input': _items(m.input),
          if (m.output.isNotEmpty) 'output': _items(m.output),
          if (m.crafting != null) 'crafting': m.crafting,
          if (m.progress != 0) 'progress': m.progress,
          if (m.energy != 0) 'energy': m.energy,
          if (m.researching != null) 'researching': m.researching,
          if (m.items.isNotEmpty)
            'items': [
              for (final i in m.items) [i.item.name, i.pos],
            ],
        },
    ],
  };

  static Map<String, int> _items(Map<FinItem, int> m) => {
    for (final e in m.entries)
      if (e.value != 0) e.key.name: e.value,
  };
}

/// Reads a saved factory, or throws [FormatException].
FinWorld finWorldFromJson(Map<String, dynamic> j) {
  if (j['version'] != FinWorldSave.version) {
    throw const FormatException('Unsupported Finorio save version');
  }
  int whole(Object? v, int lo, int hi) {
    if (v is! int || v < lo || v > hi) {
      throw const FormatException('Bad number in Finorio save');
    }
    return v;
  }

  Map<FinItem, int> items(Object? v) {
    final out = <FinItem, int>{};
    for (final e in (v as Map? ?? const {}).entries) {
      out[FinItem.values.byName(e.key as String)] = whole(e.value, 0, 1 << 40);
    }
    return out;
  }

  final seed = whole(j['seed'], 0, 0x7fffffff);
  final size = whole(j['size'] ?? FinRules.mapSize, 8, 1024);
  final map = j['terrain'] is String
      ? FinTerrainMap.fromBytes(
          seed,
          size,
          base64Decode(j['terrain'] as String),
          // Saves from before 1.67 have no landscapes: made from the seed.
          biomes: j['biomes'] is String
              ? base64Decode(j['biomes'] as String)
              : null,
        )
      : FinTerrainMap.generate(seed);
  final w = FinWorld(seed: seed, terrain: map);
  w.tick = whole(j['tick'], 0, 1 << 50);
  w.nextId = whole(j['nextId'], 1, 1 << 40);
  for (final e in (j['kits'] as Map? ?? const {}).entries) {
    w.kits[FinBuilding.values.byName(e.key as String)] = whole(
      e.value,
      0,
      100000,
    );
  }
  w.inventory.addAll(items(j['inventory']));
  w.started.addAll(items(j['started']));
  w.created.addAll(items(j['created']));
  w.destroyed.addAll(items(j['destroyed']));
  for (final r in j['researched'] as List? ?? const []) {
    if (FinConfig.tech(r as String) == null) {
      throw const FormatException('Unknown technology');
    }
    w.researched.add(r);
  }
  for (final t in j['tasks'] as List? ?? const []) {
    w.tasksDone.add(whole(t, 1, FinTasks.all.length));
  }
  w.furnaceOre = whole(j['furnaceOre'] ?? 0, 0, 1 << 50);
  w.labDelivered = whole(j['labDelivered'] ?? 0, 0, 1 << 50);
  final cam = j['camera'] as List?;
  if (cam != null && cam.length == 3) {
    w.cameraX = (cam[0] as num).toDouble().clamp(0, w.terrain.width.toDouble());
    w.cameraY = (cam[1] as num).toDouble().clamp(
      0,
      w.terrain.height.toDouble(),
    );
    w.zoom = (cam[2] as num).toDouble().clamp(.35, 3);
  }
  final settings = j['settings'] as Map? ?? const {};
  w.showGrid = settings['grid'] as bool? ?? true;
  w.tips = settings['tips'] as bool? ?? true;
  final theme = settings['theme'];
  if (theme is String && FinConfig.terrainThemes.contains(theme)) {
    w.terrainTheme = theme;
  }
  w.claimed.addAll((j['claimed'] as List? ?? const []).cast<String>());
  for (final raw in j['machines'] as List? ?? const []) {
    final m = Map<String, dynamic>.from(raw as Map);
    final kind = FinBuilding.values.byName(m['kind'] as String);
    final x = whole(m['x'], 0, w.terrain.width - 1);
    final y = whole(m['y'], 0, w.terrain.height - 1);
    final id = whole(m['id'], 1, w.nextId - 1);
    if (w.machines.containsKey(id) ||
        w.machineAt(x, y) != null ||
        !w.terrain.buildable(x, y) ||
        kind == FinBuilding.drill &&
            !FinConfig.deposits.containsKey(w.terrain.at(x, y))) {
      throw const FormatException('Inconsistent building in Finorio save');
    }
    final machine = FinMachine(
      id: id,
      kind: kind,
      x: x,
      y: y,
      dir: whole(m['dir'], 0, 3),
      recipe: m['recipe'] as String?,
    );
    if (machine.recipe != null && FinConfig.recipe(machine.recipe) == null) {
      throw const FormatException('Unknown recipe');
    }
    machine.input.addAll(items(m['input']));
    machine.output.addAll(items(m['output']));
    machine.crafting = m['crafting'] as String?;
    if (machine.crafting != null &&
        FinConfig.recipe(machine.crafting) == null) {
      throw const FormatException('Unknown recipe');
    }
    machine.progress = whole(m['progress'] ?? 0, 0, 1 << 40);
    machine.energy = whole(m['energy'] ?? 0, 0, 1 << 40);
    machine.researching = m['researching'] as String?;
    var last = FinRules.beltLength + FinRules.beltSpacing;
    for (final it in m['items'] as List? ?? const []) {
      final pair = it as List;
      final pos = whole(pair[1], 0, FinRules.beltLength);
      if (!machine.isBelt || pos > last - FinRules.beltSpacing) {
        throw const FormatException('Bad belt items in Finorio save');
      }
      machine.items.add(
        FinBeltItem(FinItem.values.byName(pair[0] as String), pos),
      );
      last = pos;
    }
    w.machines[id] = machine;
    w._cells[y * w.terrain.width + x] = id;
  }
  w._beltsDirty = true;
  // The ledger must still add up, or the file was altered or broken.
  final total = w.totalItems();
  for (final i in FinItem.values) {
    final expect =
        (w.started[i] ?? 0) + (w.created[i] ?? 0) - (w.destroyed[i] ?? 0);
    if ((total[i] ?? 0) != expect) {
      throw const FormatException('Finorio save does not balance');
    }
  }
  return w;
}
