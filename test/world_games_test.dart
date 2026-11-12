import 'package:finora/domain/world_games.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1.55: the three small games were removed from the World; their moves in
/// older saves must still validate so those saves keep loading.
void main() {
  test('only supported finite game keys are accepted', () {
    for (final kind in WorldGames.kinds) {
      for (var level = 0; level < 3; level++) {
        expect(WorldGames.validKey('$kind:$level'), isTrue);
        expect(WorldGames.validate('$kind:$level', []), isTrue);
        expect(WorldGames.complete('$kind:$level', []), isFalse);
      }
    }
    for (final invalid in [
      'parcel:3',
      'parcel:-1',
      'parcel:00',
      '',
      'roulette:0',
    ]) {
      expect(WorldGames.validate(invalid, []), isFalse);
      expect(WorldGames.complete(invalid, []), isFalse);
    }
  });

  test('constellations require their exact pattern and legal prefixes', () {
    for (var level = 0; level < 3; level++) {
      final key = 'constellation:$level',
          pattern = constellations[level].pattern;
      for (var i = 0; i < pattern.length; i++) {
        expect(WorldGames.validate(key, pattern.take(i).toList()), isTrue);
        expect(WorldGames.complete(key, pattern.take(i).toList()), isFalse);
      }
      expect(WorldGames.complete(key, pattern), isTrue);
      expect(WorldGames.validate(key, [...pattern, 0]), isFalse);
      expect(WorldGames.validate(key, [-1]), isFalse);
      final wrong = [...pattern]..[0] = (pattern.first + 1) % pattern.length;
      expect(WorldGames.complete(key, wrong), isFalse);
    }
  });

  test(
    'parcel placements reject overlap, wrapping, duplicates and bad indices',
    () {
      expect(WorldGames.complete('parcel:0', [0, 102, 206]), isTrue);
      expect(WorldGames.complete('parcel:1', [0, 106, 202]), isTrue);
      expect(WorldGames.complete('parcel:2', [4, 100, 201]), isTrue);
      expect(WorldGames.validate('parcel:0', [0, 100]), isFalse);
      expect(
        WorldGames.validate('parcel:0', [2]),
        isFalse,
      ); // Square wraps edge.
      expect(WorldGames.validate('parcel:0', [0, 0]), isFalse);
      expect(WorldGames.validate('parcel:0', [300]), isFalse);
      expect(WorldGames.validate('parcel:0', [-1]), isFalse);
      expect(WorldGames.validate('parcel:0', [9]), isFalse);
      expect(WorldGames.validate('parcel:0', [0, 102]), isTrue);
      expect(WorldGames.complete('parcel:0', [0, 102]), isFalse);
    },
  );

  test('all expedition branches finish after exactly three valid choices', () {
    for (var route = 0; route < 3; route++) {
      for (var a = 0; a < 3; a++) {
        for (var b = 0; b < 3; b++) {
          for (var c = 0; c < 3; c++) {
            expect(WorldGames.complete('expedition:$route', [a, b, c]), isTrue);
            expect(expeditions[route].result([a, b, c]), isNotEmpty);
          }
        }
      }
      expect(WorldGames.complete('expedition:$route', [0, 1]), isFalse);
      expect(WorldGames.validate('expedition:$route', [0, 1, 3]), isFalse);
      expect(WorldGames.validate('expedition:$route', [0, 1, 2, 0]), isFalse);
    }
  });
}
