import 'package:flutter/material.dart';

import '../../../../domain/finorio/finorio.dart';

/// Every word Finorio shows: live Flutter text, never baked into art.
abstract final class FinNames {
  static String item(FinItem i) => switch (i) {
    FinItem.ironOre => 'Железная руда',
    FinItem.copperOre => 'Медная руда',
    FinItem.crystal => 'Кристалл',
    FinItem.biomass => 'Биомасса',
    FinItem.ironPlate => 'Железная пластина',
    FinItem.copperPlate => 'Медная пластина',
    FinItem.gear => 'Шестерня',
    FinItem.circuit => 'Электронная схема',
  };

  static String building(FinBuilding b) => switch (b) {
    FinBuilding.drill => 'Буровая',
    FinBuilding.furnace => 'Плавильная печь',
    FinBuilding.assembler => 'Сборочный станок',
    FinBuilding.generator => 'Генератор',
    FinBuilding.storage => 'Склад',
    FinBuilding.belt => 'Конвейер',
    FinBuilding.fastBelt => 'Быстрый конвейер',
    FinBuilding.lab => 'Исследовательский терминал',
  };

  static String terrain(FinTerrain t) => switch (t) {
    FinTerrain.ground => 'Свободная территория',
    FinTerrain.iron => 'Месторождение железа',
    FinTerrain.copper => 'Месторождение меди',
    FinTerrain.crystal => 'Кристаллические залежи',
    FinTerrain.biomass => 'Месторождение биомассы',
    FinTerrain.rock => 'Скалы — строить нельзя',
  };

  static String recipe(String id) => switch (id) {
    'iron_plate' => 'Железная пластина',
    'copper_plate' => 'Медная пластина',
    'gear' => 'Шестерня',
    'circuit' => 'Электронная схема',
    _ => id,
  };

  static String status(FinStatus s, FinBuilding kind) => switch (s) {
    FinStatus.working => 'Работает',
    FinStatus.noInput =>
      kind == FinBuilding.generator ? 'Нет топлива' : 'Нет сырья',
    FinStatus.noPower => 'Нет электричества',
    FinStatus.outputBlocked =>
      kind == FinBuilding.storage ? 'Склад заполнен' : 'Выход заблокирован',
    FinStatus.done => 'Производство завершено',
    FinStatus.needsSetup => 'Ожидает настройки',
    FinStatus.idle => 'Ожидает',
  };

  static Color statusColor(FinStatus s) => switch (s) {
    FinStatus.working => const Color(0xFF2FB58C),
    FinStatus.noInput => const Color(0xFFE0A33A),
    FinStatus.noPower => const Color(0xFFE0566B),
    FinStatus.outputBlocked => const Color(0xFF9B6BE0),
    FinStatus.done => const Color(0xFF4C9BE8),
    FinStatus.needsSetup => const Color(0xFF8E8AA0),
    FinStatus.idle => const Color(0xFFB4B0C4),
  };

  static String tech(String id) => switch (id) {
    'logistics' => 'Улучшенная логистика',
    'mining' => 'Улучшенная добыча',
    'express_belts' => 'Экспресс-конвейеры',
    'inserters' => 'Манипуляторы',
    'sorters' => 'Сортировщики',
    'power_grid' => 'Энергосети',
    'solar' => 'Солнечные генераторы',
    'batteries' => 'Аккумуляторы',
    'auto_logistics' => 'Автоматическая логистика',
    'robots' => 'Роботы',
    'rail' => 'Железнодорожные системы',
    'quantum' => 'Квантовые технологии',
    _ => id,
  };

  static String techResult(String id) => switch (id) {
    'logistics' =>
      'Открывает быстрый конвейер: вдвое быстрее, 4 предмета в секунду.',
    _ => 'Появится в одном из следующих обновлений.',
  };
}
