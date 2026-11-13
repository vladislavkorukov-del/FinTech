import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../../../../domain/finorio/finorio.dart';

/// Finorio's painted art (Finorio_Buildings, Belts, Ore_and_Items,
/// Terrain_Tiles, Terrain_Backgrounds), decoded once at a size that stays
/// sharp at the game's zoom. Drawing functions use it when loaded and fall
/// back to the procedural shapes otherwise.
class FinSpriteBank {
  FinSpriteBank._(this._images, this.theme);

  /// The bank the open Finorio screen loaded (null: procedural art).
  static FinSpriteBank? current;

  static const root = 'assets/finorio';
  final Map<String, ui.Image> _images;

  /// The terrain theme whose background is loaded.
  final String theme;

  static String _building(String name) => 'png/buildings/$name';

  /// Base sprite and optional animated layer of each building.
  static const buildingArt = <FinBuilding, (String, String?)>{
    FinBuilding.drill: ('drill_base', 'drill_bit'),
    FinBuilding.furnace: ('furnace_base', 'furnace_glow'),
    FinBuilding.assembler: ('assembler_base', 'assembler_gear'),
    FinBuilding.generator: ('generator_base', 'generator_core'),
    FinBuilding.storage: ('storage', null),
    FinBuilding.lab: ('lab_base', 'lab_light'),
  };

  static String itemArt(FinItem i) => switch (i) {
    FinItem.ironOre => 'item_iron_ore',
    FinItem.copperOre => 'item_copper_ore',
    FinItem.crystal => 'item_crystal',
    FinItem.biomass => 'item_biomass',
    FinItem.ironPlate => 'item_iron_plate',
    FinItem.copperPlate => 'item_copper_plate',
    FinItem.gear => 'item_gear',
    FinItem.circuit => 'item_circuit',
  };

  static Future<FinSpriteBank> load(String theme) async {
    final jobs = <String, (String, int)>{
      for (final e in buildingArt.values) ...{
        e.$1: ('${_building(e.$1)}.png', 384),
        if (e.$2 != null) e.$2!: ('${_building(e.$2!)}.png', 384),
      },
      for (final b in ['belt', 'fast_belt'])
        for (final f in ['straight', 'corner', 'chevron'])
          '${b}_$f': ('png/belts/${b}_$f.png', 384),
      for (final i in FinItem.values)
        itemArt(i): ('png/items/${itemArt(i)}.png', 96),
      for (final t in FinTerrain.values)
        for (final v in [1, 2])
          '${t.name}_$v': ('png/terrain/${t.name}_$v.png', 192),
      'background': ('backgrounds/terrain_$theme.webp', 1280),
    };
    final images = <String, ui.Image>{};
    try {
      await Future.wait([
        for (final e in jobs.entries)
          _decode(
            '$root/${e.value.$1}',
            e.value.$2,
          ).then((img) => images[e.key] = img),
      ]);
    } on Object {
      for (final img in images.values) {
        img.dispose();
      }
      rethrow;
    }
    return FinSpriteBank._(images, theme);
  }

  static Future<ui.Image> _decode(String asset, int width) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  ui.Image? operator [](String key) => _images[key];
  ui.Image? item(FinItem i) => _images[itemArt(i)];
  ui.Image? tile(FinTerrain t, int x, int y, int seed) =>
      _images['${t.name}_${((x * 7 + y * 13 + seed) & 1) + 1}'];
  ui.Image? get background => _images['background'];

  void dispose() {
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
  }
}
