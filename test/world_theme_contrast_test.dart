import 'dart:math' as math;
import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/flow_screens.dart';
import 'package:finora/presentation/screens/world/world_art.dart';
import 'package:finora/presentation/screens/world/world_customization.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _QuietNotifications extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

double _contrast(Color foreground, Color background) {
  final visible = Color.alphaBlend(foreground, background);
  final a = visible.computeLuminance(), b = background.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

Color _textColor(WidgetTester tester, String label) => tester
    .widget<RichText>(
      find
          .descendant(of: find.text(label), matching: find.byType(RichText))
          .first,
    )
    .text
    .style!
    .color!;

Color _chipFill(WidgetTester tester, String key) => tester
    .widgetList<Ink>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Ink),
      ),
    )
    .map((ink) => (ink.decoration as ShapeDecoration?)?.color)
    .firstWhere((color) => color != null && color.a > 0)!;

void main() {
  testWidgets('real decor and flow routes retain readable controls', (
    tester,
  ) async {
    sqfliteFfiInit();
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('world-theme-regression-'),
    );
    final repository = await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${directory!.path}/db',
      ),
    );
    final controller = FinanceController(
      repository!,
      _QuietNotifications(),
      const FinanceData(),
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
      await directory!.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> mount(Widget page) async {
      await tester.pumpWidget(
        FinanceScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark, 'coffee'),
            home: WorldTheme(child: page),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await mount(const WorldDecorScreen());
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      final label = (chip.label as Text).data!;
      final fill = _chipFill(tester, (chip.key! as ValueKey<String>).value);
      expect(
        _contrast(_textColor(tester, label), fill),
        greaterThanOrEqualTo(4.5),
      );
    }
    final decorator = tester.widget<InputDecorator>(
      find.byType(InputDecorator).first,
    );
    final theme = Theme.of(tester.element(find.byType(InputDecorator).first));
    final fill =
        decorator.decoration.fillColor ?? theme.inputDecorationTheme.fillColor!;
    expect(fill.computeLuminance(), greaterThan(.8));
    expect(
      _contrast(_textColor(tester, 'Свободно'), fill),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);

    await mount(const FlowMapScreen());
    for (
      var attempt = 0;
      attempt < 100 &&
          find.byKey(const ValueKey('flow-level-1')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final id in [1, 2]) {
      final tile = find.byKey(ValueKey('flow-level-$id'));
      expect(tile, findsOneWidget);
      final rich = tester
          .widgetList<RichText>(
            find.descendant(of: tile, matching: find.byType(RichText)),
          )
          .firstWhere((w) => w.text.toPlainText() == '$id');
      expect(
        _contrast(rich.text.style!.color!, worldPearl),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'world controls keep readable pearl colors under every financial preset',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final brightness in Brightness.values) {
        for (final preset in AppTheme.presetNames.keys) {
          final finance = AppTheme.build(brightness, preset);
          ThemeData? outer, inner;
          await tester.pumpWidget(
            MaterialApp(
              theme: finance,
              home: Builder(
                builder: (context) {
                  outer = Theme.of(context);
                  return WorldTheme(
                    child: Builder(
                      builder: (context) {
                        inner = Theme.of(context);
                        return Scaffold(
                          body: ListView(
                            children: [
                              const ListTile(
                                title: Text('Открытый уровень'),
                                subtitle: Text('Девять ходов'),
                              ),
                              const ListTile(
                                enabled: false,
                                title: Text('Закрытый уровень'),
                                subtitle: Text('Пройдите предыдущий'),
                              ),
                              ChoiceChip(
                                key: const ValueKey('plain'),
                                label: const Text('Мятный атриум'),
                                selected: false,
                                onSelected: (_) {},
                              ),
                              ChoiceChip(
                                key: const ValueKey('selected'),
                                label: const Text('Чайная комната'),
                                selected: true,
                                onSelected: (_) {},
                              ),
                              const ChoiceChip(
                                key: ValueKey('disabled'),
                                label: Text('Северное сияние'),
                                selected: false,
                              ),
                              DropdownButtonFormField<String>(
                                key: const ValueKey('decor'),
                                initialValue: '',
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Левая подставка',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text('Свободно'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'tea',
                                    child: Text('Чашка'),
                                  ),
                                ],
                                onChanged: (_) {},
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final contextLabel = '$brightness/$preset';
          expect(outer!.brightness, brightness, reason: contextLabel);
          expect(
            outer!.inputDecorationTheme.fillColor,
            finance.inputDecorationTheme.fillColor,
            reason: 'finance unchanged',
          );
          expect(inner!.brightness, Brightness.light, reason: contextLabel);
          for (final label in ['Открытый уровень', 'Девять ходов']) {
            expect(
              _contrast(
                _textColor(tester, label),
                inner!.scaffoldBackgroundColor,
              ),
              greaterThanOrEqualTo(4.5),
              reason: '$contextLabel/$label',
            );
          }
          expect(
            _contrast(
              _textColor(tester, 'Закрытый уровень'),
              inner!.scaffoldBackgroundColor,
            ),
            greaterThanOrEqualTo(3),
            reason: contextLabel,
          );
          for (final item in [
            ('plain', 'Мятный атриум'),
            ('selected', 'Чайная комната'),
            ('disabled', 'Северное сияние'),
          ]) {
            final fill = _chipFill(tester, item.$1);
            expect(
              fill.computeLuminance(),
              greaterThan(.55),
              reason: '$contextLabel/${item.$1}',
            );
            expect(
              _contrast(_textColor(tester, item.$2), fill),
              greaterThanOrEqualTo(item.$1 == 'disabled' ? 3 : 4.5),
              reason: '$contextLabel/${item.$1}',
            );
          }
          final decorator = tester.widget<InputDecorator>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('decor')),
                  matching: find.byType(InputDecorator),
                )
                .first,
          );
          final fill =
              decorator.decoration.fillColor ??
              inner!.inputDecorationTheme.fillColor!;
          expect(
            fill.computeLuminance(),
            greaterThan(.8),
            reason: contextLabel,
          );
          expect(
            _contrast(_textColor(tester, 'Свободно'), fill),
            greaterThanOrEqualTo(4.5),
            reason: contextLabel,
          );
          expect(tester.takeException(), isNull, reason: contextLabel);
        }
      }
    },
  );
}
