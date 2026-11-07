import 'dart:io';

import 'package:finora/domain/models.dart';
import 'package:finora/presentation/finora_outside.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceEntry at(DateTime d, [String id = '']) => FinanceEntry(
  id: 'e${d.toIso8601String()}$id',
  kind: EntryKind.expense,
  amountMinor: 100,
  currency: 'RUB',
  accountId: 'a',
  date: d,
);

void main() {
  final now = DateTime(2026, 11, 7, 15);
  test('серия дней подряд для виджета-напарника', () {
    expect(FinoraOutside.streak(const [], now: now), 0);
    expect(
      FinoraOutside.streak([
        at(DateTime(2026, 11, 7, 9)),
        at(DateTime(2026, 11, 7, 12), 'b'),
        at(DateTime(2026, 11, 6, 20)),
        at(DateTime(2026, 11, 5, 8)),
        at(DateTime(2026, 11, 3, 8)),
      ], now: now),
      3,
    );
    // Yesterday's streak is counted up to yesterday (the widget keeps it
    // alive until midnight).
    expect(
      FinoraOutside.streak([
        at(DateTime(2026, 11, 6, 9)),
        at(DateTime(2026, 11, 5, 9)),
      ], now: now),
      2,
    );
    // Future-dated records don't count.
    expect(FinoraOutside.streak([at(DateTime(2026, 11, 9))], now: now), 0);
  });

  test('«Что нового» в 1.39', () {
    expect(WhatsNew.items.first.$2, 'Финора-напарник на рабочем столе');
  });

  test('виджет описан в Android-ресурсах', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('.FinoraWidgetBuddy'));
    expect(
      File('android/app/src/main/res/layout/widget_buddy.xml').existsSync(),
      isTrue,
    );
    for (final m in ['happy', 'thinking', 'attention', 'angry', 'sleep']) {
      expect(
        File(
          'android/app/src/main/res/drawable/widget_mood_$m.xml',
        ).existsSync(),
        isTrue,
      );
    }
  });
}
