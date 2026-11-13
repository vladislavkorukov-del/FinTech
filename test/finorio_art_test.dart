import 'package:finora/domain/finorio/finorio.dart';
import 'package:finora/presentation/screens/world/finorio/finorio_sprites.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finorio's painted art: every sprite loads for every theme, and the
/// chosen landscape is kept by the save without touching the map.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every sprite and each terrain background loads', (tester) async {
    for (final theme in FinConfig.terrainThemes) {
      final bank = (await tester.runAsync(() => FinSpriteBank.load(theme)))!;
      expect(bank.background, isNotNull, reason: theme);
      if (theme == FinConfig.terrainThemes.first) {
        for (final art in FinSpriteBank.buildingArt.values) {
          expect(bank[art.$1], isNotNull, reason: art.$1);
          if (art.$2 != null) expect(bank[art.$2!], isNotNull, reason: art.$2);
        }
        for (final b in ['belt', 'fast_belt']) {
          for (final f in ['straight', 'corner', 'chevron']) {
            expect(bank['${b}_$f'], isNotNull, reason: '${b}_$f');
          }
        }
        for (final i in FinItem.values) {
          expect(bank.item(i), isNotNull, reason: '$i');
        }
        for (final t in FinTerrain.values) {
          for (var x = 0; x < 2; x++) {
            expect(bank.tile(t, x, 0, 1), isNotNull, reason: '$t');
          }
        }
      }
      bank.dispose();
    }
  });

  test('the landscape is saved as a view setting only', () {
    final w = FinWorld.start(7);
    expect(FinConfig.terrainThemes, contains(w.terrainTheme));
    w.terrainTheme = 'volcanic';
    final copy = finWorldFromJson(w.toJson());
    expect(copy.terrainTheme, 'volcanic');
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        expect(copy.terrain.at(x, y), w.terrain.at(x, y));
      }
    }
    final odd = w.toJson()..['settings'] = {'theme': 'nowhere'};
    expect(
      FinConfig.terrainThemes,
      contains(finWorldFromJson(odd).terrainTheme),
    );
  });
}
