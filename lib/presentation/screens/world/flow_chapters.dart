import 'package:flutter/painting.dart';

import '../../../domain/flow/flow.dart';

/// One painted chapter theme (Finora_Potok_Chapters packs): a backdrop for
/// the level screen and one 724 × 2172 part of the level map — one period
/// of 13 platforms on the same anchors as the terraces.
class FlowChapterTheme {
  const FlowChapterTheme(this.key, this.title, this.mist, this.sky);
  final String key, title;

  /// Clouds hiding the join where a part follows itself, and the sky above
  /// the top of the map.
  final Color mist, sky;

  String get background =>
      'assets/finora/match3/chapters/$key/gameplay_background.webp';
  String get map => 'assets/finora/match3/chapters/$key/level_map.webp';
}

/// Chapters of 50 levels: chapter 1 keeps the original sky and terraces,
/// chapters 2–10 take the nine painted themes in their pack order.
abstract final class FlowChapters {
  static const themes = <FlowChapterTheme>[
    FlowChapterTheme(
      'sakura',
      'Сад сакуры',
      Color(0xFFF5E6E5),
      Color(0xFFCDBBA0),
    ),
    FlowChapterTheme(
      'jade',
      'Нефритовые каскады',
      Color(0xFFDAE2D3),
      Color(0xFFBDBD93),
    ),
    FlowChapterTheme(
      'lagoon',
      'Коралловая лагуна',
      Color(0xFFEFE8E2),
      Color(0xFFE5B38F),
    ),
    FlowChapterTheme(
      'dunes',
      'Янтарные дюны',
      Color(0xFFF4DFD0),
      Color(0xFFE0966F),
    ),
    FlowChapterTheme(
      'autumn',
      'Кленовые террасы',
      Color(0xFFEAD0C9),
      Color(0xFFC4849D),
    ),
    FlowChapterTheme(
      'amethyst',
      'Аметистовый грот',
      Color(0xFFE5D8F1),
      Color(0xFFBEA9EF),
    ),
    FlowChapterTheme(
      'ice',
      'Ледяной дворец',
      Color(0xFFE1EDF9),
      Color(0xFF9DABD3),
    ),
    FlowChapterTheme(
      'storm',
      'Грозовые острова',
      Color(0xFFD3D4DC),
      Color(0xFF9890BD),
    ),
    FlowChapterTheme(
      'moon',
      'Лунная обсерватория',
      Color(0xFFDEDAE7),
      Color(0xFF9C92C4),
    ),
  ];

  /// The theme of a chapter (null for chapter 1: the original art).
  static FlowChapterTheme? of(int chapter) =>
      chapter >= 2 && chapter - 2 < themes.length ? themes[chapter - 2] : null;

  static FlowChapterTheme? forLevel(int levelId) =>
      of(FlowLevelGenerator.chapterOf(levelId));
}
