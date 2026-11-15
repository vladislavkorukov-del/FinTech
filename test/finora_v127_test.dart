import 'dart:ui';

import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/service_recognizer.dart';
import 'package:finora/presentation/finora_reactions.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora 1.27: emotions for events and proper names for Cyrillic ones.
void main() {
  final now = DateTime(2026, 11, 7);
  final demo = createDemoData(now);
  final start = DateTime(2026, 11);
  final end = DateTime(2026, 12);
  String id(String name) =>
      demo.categories.firstWhere((c) => c.name == name).id;

  FinanceEntry entry(
    EntryKind kind,
    int amount, {
    String? category,
    String payee = '',
    String? goal,
  }) => FinanceEntry(
    id: 'x',
    kind: kind,
    amountMinor: amount,
    currency: 'RUB',
    accountId: demo.accounts.first.id,
    categoryId: category,
    toGoalId: goal,
    payee: payee,
    date: now,
  );

  (bool, String?) mood(FinanceData data, FinanceEntry e) =>
      FinoraReactions.forEntry(
        data.copyWith(entries: [...data.entries, e]),
        e,
        start,
        end,
      );

  test('salary: a glad line, no alert', () {
    final clean = demo.copyWith(budgets: const []);
    final (m1, t1) = mood(
      clean,
      entry(EntryKind.income, 3000000, category: id('Зарплата')),
    );
    expect(m1, isFalse);
    expect(t1, startsWith('Зарплата пришла!'));
    final (m2, _) = mood(
      clean,
      entry(EntryKind.income, 9000000, category: id('Зарплата')),
    );
    expect(m2, isFalse);
  });

  test('a big expense gets a line, a small one none', () {
    final clean = demo.copyWith(budgets: const []);
    final (big, text) = mood(
      clean,
      entry(EntryKind.expense, 1250000, category: id('Покупки')),
    );
    expect(big, isFalse);
    expect(text, contains('Большая трата'));
    final (small, none) = mood(
      clean,
      entry(EntryKind.expense, 45000, category: id('Продукты')),
    );
    expect(small, isFalse);
    expect(none, isNull);
  });

  test('going over a budget is an alert', () {
    final data = demo.copyWith(
      entries: const [],
      budgets: [
        Budget(
          id: 'food',
          name: 'Продукты',
          categoryId: id('Продукты'),
          limitMinor: 100000,
        ),
      ],
    );
    final (m, text) = mood(
      data,
      entry(EntryKind.expense, 150000, category: id('Продукты')),
    );
    expect(m, isTrue);
    expect(text, contains('превышен'));
  });

  test('2.2: Finora paints as a sphere of light, at rest and lively', () {
    for (final e in [0.0, .5, 1.0]) {
      final recorder = PictureRecorder();
      FinoraOrbPainter(
        t: .3,
        energy: e,
      ).paint(Canvas(recorder), const Size.square(120));
      expect(recorder.endRecording(), isNotNull);
    }
  });

  test('Cyrillic names are replaced only when they are the whole text', () {
    expect(ServiceRecognizer.find('чат гпт', whole: true)?.name, 'ChatGPT');
    expect(ServiceRecognizer.find('нетфликс', whole: true)?.name, 'Netflix');
    expect(ServiceRecognizer.find('чат гпт за май', whole: true), isNull);
    expect(ServiceRecognizer.find('чат гпт за май')?.name, 'ChatGPT');
  });
}
