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

  /// Short names for the build palette.
  static String short(FinBuilding b) => switch (b) {
    FinBuilding.drill => 'Буровая',
    FinBuilding.furnace => 'Печь',
    FinBuilding.assembler => 'Станок',
    FinBuilding.generator => 'Генератор',
    FinBuilding.storage => 'Склад',
    FinBuilding.belt => 'Конвейер',
    FinBuilding.fastBelt => 'Быстрый',
    FinBuilding.lab => 'Терминал',
  };

  static String buildingAbout(FinBuilding b) => switch (b) {
    FinBuilding.drill =>
      'Ставится прямо на месторождение и добывает его сырьё: одну единицу '
          'за 2 секунды. Выдаёт добычу в клетку перед собой — на конвейер или '
          'сразу в станок. Работает только с энергией и встаёт, когда выход занят.',
    FinBuilding.furnace =>
      'Плавит руду в пластины: 2 руды — 1 пластина за 4 секунды. Сама выбирает '
          'рецепт по первой поданной руде — железной или медной. Готовые пластины '
          'выходят вперёд.',
    FinBuilding.assembler =>
      'Собирает детали по выбранному рецепту: шестерни из железных пластин или '
          'электронные схемы из медной пластины и кристалла. Принимает сырьё с '
          'любой стороны, отдаёт результат вперёд.',
    FinBuilding.generator =>
      'Сжигает биомассу и питает всё в радиусе 6 клеток — до 12 единиц мощности. '
          'Одной биомассы хватает на 20 секунд полной нагрузки. Топливо можно '
          'подвезти конвейером.',
    FinBuilding.storage =>
      'Принимает любые предметы с конвейера и хранит их раздельно по видам, '
          'до 200 штук. Из склада можно забрать всё в инвентарь.',
    FinBuilding.belt =>
      'Везёт предметы по клеткам со скоростью 2 предмета в секунду. Линию можно '
          'протянуть удержанием или двумя касаниями; на поворотах лента сама '
          'изгибается. Энергия не нужна.',
    FinBuilding.fastBelt =>
      'Вдвое быстрее обычного: 4 предмета в секунду. Открывается исследованием '
          '«Улучшенная логистика».',
    FinBuilding.lab =>
      'Ведёт исследования: принимает электронные схемы и с энергией открывает '
          'новые технологии.',
  };

  static String itemAbout(FinItem i) => switch (i) {
    FinItem.ironOre =>
      'Серо-голубые угловатые камни с месторождения железа. Плавится в печи в железные пластины.',
    FinItem.copperOre =>
      'Камни с медными прожилками. В печи становятся медными пластинами.',
    FinItem.crystal =>
      'Прозрачные гранёные кристаллы. Нужны для электронных схем.',
    FinItem.biomass =>
      'Брикеты из листьев и волокон — топливо для генератора: одна единица даёт 20 секунд полной мощности.',
    FinItem.ironPlate =>
      'Основной металл завода. Из двух пластин станок делает шестерню; пластины идут и на постройки.',
    FinItem.copperPlate =>
      'Хорошо проводит ток. Вместе с кристаллом превращается в электронную схему.',
    FinItem.gear =>
      'Механическая деталь для буровых, генераторов и конвейеров.',
    FinItem.circuit =>
      'Электроника завода: нужна станкам, терминалу и исследованиям.',
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

  static String terrainTheme(String key) => switch (key) {
    'meadow' => 'Шалфейная равнина',
    'quarry' => 'Сланцевый карьер',
    'canyon' => 'Пески каньона',
    'wetlands' => 'Моховые низины',
    'tundra' => 'Морозная тундра',
    'volcanic' => 'Вулканическое плато',
    _ => key,
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
