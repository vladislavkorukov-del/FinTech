/// The three small activities removed in 1.55 (Созвездия, Посылка для
/// Финоры, Экспедиция). They can no longer be played; this validation stays
/// only so older saves and backups that contain their moves still load.
abstract final class WorldGames {
  static const kinds = ['constellation', 'parcel', 'expedition'];
  static const levels = 3;

  static bool validKey(String key) =>
      RegExp(r'^(constellation|parcel|expedition):[0-2]$').hasMatch(key);

  static int levelOf(String key) => int.parse(key.split(':').last);

  static String title(String kind) => switch (kind) {
    'constellation' => 'Созвездия',
    'parcel' => 'Посылка для Финоры',
    'expedition' => 'Экспедиция',
    _ => '',
  };

  static bool validate(String key, List<int> moves) {
    if (!validKey(key)) return false;
    final level = levelOf(key);
    switch (key.split(':').first) {
      case 'constellation':
        final pattern = constellations[level].pattern;
        if (moves.length > pattern.length) return false;
        for (var i = 0; i < moves.length; i++) {
          if (moves[i] != pattern[i]) return false;
        }
        return true;
      case 'parcel':
        final board = parcels[level];
        final occupied = <int>{};
        final pieces = <int>{};
        if (moves.length > board.pieces.length) return false;
        for (final move in moves) {
          if (move < 0) return false;
          final piece = move ~/ 100, anchor = move % 100;
          if (piece >= board.pieces.length || !pieces.add(piece)) return false;
          final cells = board.cellsAt(piece, anchor);
          if (cells == null || cells.any(occupied.contains)) return false;
          occupied.addAll(cells);
        }
        return true;
      case 'expedition':
        return moves.length <= 3 && moves.every((m) => m >= 0 && m <= 2);
    }
    return false;
  }

  static bool complete(String key, List<int> moves) {
    if (!validate(key, moves)) return false;
    final level = levelOf(key);
    return moves.length ==
        switch (key.split(':').first) {
          'constellation' => constellations[level].pattern.length,
          'parcel' => parcels[level].pieces.length,
          'expedition' => 3,
          _ => -1,
        };
  }
}

class StarPoint {
  const StarPoint(this.x, this.y);
  final double x, y;
}

class ConstellationPuzzle {
  const ConstellationPuzzle(this.name, this.points, this.pattern);
  final String name;
  final List<StarPoint> points;
  final List<int> pattern;
}

const constellations = [
  ConstellationPuzzle(
    'Мятный парус',
    [
      StarPoint(.18, .77),
      StarPoint(.48, .16),
      StarPoint(.8, .77),
      StarPoint(.48, .57),
      StarPoint(.48, .86),
    ],
    [0, 1, 2, 3, 4],
  ),
  ConstellationPuzzle(
    'Жемчужный цветок',
    [
      StarPoint(.5, .15),
      StarPoint(.8, .38),
      StarPoint(.68, .79),
      StarPoint(.32, .79),
      StarPoint(.2, .38),
      StarPoint(.5, .48),
    ],
    [0, 2, 4, 1, 3, 5],
  ),
  ConstellationPuzzle(
    'Путеводная звезда',
    [
      StarPoint(.17, .28),
      StarPoint(.5, .13),
      StarPoint(.83, .28),
      StarPoint(.73, .69),
      StarPoint(.5, .85),
      StarPoint(.27, .69),
    ],
    [5, 0, 2, 4, 1, 3],
  ),
];

class ParcelPiece {
  const ParcelPiece(this.name, this.cells);
  final String name;

  /// Local offsets (column, row). No rotations are implicit.
  final List<(int, int)> cells;
}

class ParcelPuzzle {
  const ParcelPuzzle(this.name, this.pieces);
  final String name;
  final List<ParcelPiece> pieces;

  List<int>? cellsAt(int piece, int anchor) {
    if (piece < 0 || piece >= pieces.length || anchor < 0 || anchor >= 9) {
      return null;
    }
    final x = anchor % 3, y = anchor ~/ 3;
    final result = <int>[];
    for (final offset in pieces[piece].cells) {
      final column = x + offset.$1, row = y + offset.$2;
      if (column < 0 || column >= 3 || row < 0 || row >= 3) return null;
      result.add(row * 3 + column);
    }
    return result;
  }
}

const _square = ParcelPiece('Чайный набор', [(0, 0), (1, 0), (0, 1), (1, 1)]);
const _vertical = ParcelPiece('Лунная лампа', [(0, 0), (0, 1), (0, 2)]);
const _horizontal = ParcelPiece('Книга', [(0, 0), (1, 0)]);
const parcels = [
  ParcelPuzzle('Чайный вечер', [_square, _vertical, _horizontal]),
  ParcelPuzzle('Садовая посылка', [
    ParcelPiece('Кашпо', [(0, 0), (1, 0), (0, 1), (1, 1)]),
    ParcelPiece('Семена', [(0, 0), (1, 0), (2, 0)]),
    ParcelPiece('Лейка', [(0, 0), (0, 1)]),
  ]),
  ParcelPuzzle('Полярный багаж', [
    ParcelPiece('Тёплый плед', [(0, 0), (1, 0), (0, 1), (1, 1)]),
    ParcelPiece('Телескоп', [(0, 0), (0, 1), (0, 2)]),
    ParcelPiece('Термос', [(0, 0), (1, 0)]),
  ]),
];

class ExpeditionStep {
  const ExpeditionStep(this.text, this.choices, this.results);
  final String text;
  final List<String> choices, results;
}

class ExpeditionRoute {
  const ExpeditionRoute(this.name, this.steps, this.keepsake);
  final String name, keepsake;
  final List<ExpeditionStep> steps;

  String result(List<int> moves) => moves.length == steps.length
      ? '${steps.last.results[moves.last]} $keepsake'
      : '';
}

const expeditions = [
  ExpeditionRoute('Жемчужный берег', [
    ExpeditionStep(
      'У берега три тропы. Куда отправимся?',
      ['Вдоль воды', 'К маяку', 'Через дюны'],
      [
        'На воде переливаются огоньки.',
        'Маяк показывает путь.',
        'Песок тихо светится.',
      ],
    ),
    ExpeditionStep(
      'На пути оказалась маленькая бухта.',
      ['Послушать море', 'Собрать ракушки', 'Нарисовать берег'],
      [
        'Волны складываются в мелодию.',
        'Нашлась жемчужная ракушка.',
        'Получился уютный пейзаж.',
      ],
    ),
    ExpeditionStep(
      'На закате пора возвращаться.',
      ['По светлой тропе', 'С остановкой у маяка', 'Через сад'],
      [
        'Светлая тропа привела домой.',
        'Маяк проводил мягким светом.',
        'Сад подарил аромат мяты.',
      ],
    ),
  ], 'Впечатление: тихий морской вечер.'),
  ExpeditionRoute('Мятная долина', [
    ExpeditionStep(
      'Долина встречает тремя дорожками.',
      ['К ручью', 'К оранжерее', 'На холм'],
      [
        'Ручей звенит под мостиком.',
        'Стеклянные листья сияют.',
        'С холма виден весь сад.',
      ],
    ),
    ExpeditionStep(
      'В долине есть место для привала.',
      ['Заварить чай', 'Посмотреть на облака', 'Послушать птиц'],
      [
        'Чай пахнет мятой.',
        'Облако похоже на Финору.',
        'Птицы устроили маленький концерт.',
      ],
    ),
    ExpeditionStep(
      'Вечерний свет зовёт домой.',
      ['По мосту', 'Среди фонариков', 'По цветочной аллее'],
      [
        'Мостик вывел к дому.',
        'Фонарики осветили путь.',
        'Цветы мягко светились всю дорогу.',
      ],
    ),
  ], 'Впечатление: прогулка в мятной долине.'),
  ExpeditionRoute('Полярное сияние', [
    ExpeditionStep(
      'Под звёздами начинаются три маршрута.',
      ['К обсерватории', 'К ледяному озеру', 'К тихой вершине'],
      [
        'Телескоп готов к наблюдению.',
        'Лёд отражает звёзды.',
        'Вершина укрыта мягким снегом.',
      ],
    ),
    ExpeditionStep(
      'В небе появляется сияние.',
      ['Найти созвездие', 'Сделать зарисовку', 'Устроить чаепитие'],
      [
        'Нашлась путеводная звезда.',
        'Рисунок сохранил переливы неба.',
        'Тёплый чай согрел ладони.',
      ],
    ),
    ExpeditionStep(
      'Пора выбрать обратный путь.',
      ['Вслед за звёздами', 'По световым вешкам', 'Вдоль озера'],
      [
        'Звёзды помогли вернуться.',
        'Огоньки привели прямо домой.',
        'Озеро проводило отражениями.',
      ],
    ),
  ], 'Впечатление: встреча с полярным сиянием.'),
];
