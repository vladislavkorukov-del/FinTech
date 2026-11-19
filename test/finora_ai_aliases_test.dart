import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/actions/ai_actions.dart';
import 'package:finora/features/finora_ai/memory/personal_memory.dart';
import 'package:finora/features/finora_ai/personalization/payee_aliases.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora AI remembers the person's short names for places: «кб» is
/// «Красное&Белое».
void main() {
  test('what counts as a short name', () {
    expect(PayeeAliases.looksLikeShortFor('кб', 'Красное&Белое'), isTrue);
    expect(PayeeAliases.looksLikeShortFor('КБ', 'Красное и Белое'), isTrue);
    expect(PayeeAliases.looksLikeShortFor('пят', 'Пятёрочка'), isTrue);
    expect(PayeeAliases.looksLikeShortFor('вв', 'ВкусВилл'), isTrue);
    // A different shop or a fixed typo is not a short name.
    expect(PayeeAliases.looksLikeShortFor('Магнит', 'Пятёрочка'), isFalse);
    expect(PayeeAliases.looksLikeShortFor('Пятерчка', 'Пятёрочка'), isFalse);
    expect(PayeeAliases.looksLikeShortFor('Такси', 'Яндекс Go'), isFalse);
    expect(PayeeAliases.looksLikeShortFor('', 'Пятёрочка'), isFalse);
  });

  test('teaching phrases in the chat', () {
    expect(PayeeAliases.parseTeaching('кб — это Красное и Белое'), (
      'кб',
      'Красное и Белое',
    ));
    expect(PayeeAliases.parseTeaching('кб это красное и белое'), (
      'кб',
      'красное и белое',
    ));
    expect(PayeeAliases.parseTeaching('Запомни: дом значит Леруа Мерлен'), (
      'дом',
      'Леруа Мерлен',
    ));
    expect(PayeeAliases.parseTeaching('КБ = Красное&Белое'), (
      'КБ',
      'Красное&Белое',
    ));
    // Questions, sums and sentences about other things are not teaching.
    expect(PayeeAliases.parseTeaching('кб это что?'), isNull);
    expect(PayeeAliases.parseTeaching('расход это 500'), isNull);
    expect(PayeeAliases.parseTeaching('дом это важно'), isNull);
    expect(PayeeAliases.parseTeaching('добавь расход кб 500'), isNull);
  });

  test('learned names are kept in memory and written with the brand', () {
    final memory = PersonalMemory();
    expect(
      PayeeAliases.learn(memory, 'Кб', 'красное и белое'),
      'Красное&Белое',
    );
    expect(PayeeAliases.resolve(memory, 'кб'), 'Красное&Белое');
    expect(PayeeAliases.resolve(memory, 'КБ.'), 'Красное&Белое');
    expect(PayeeAliases.resolve(memory, 'Пятёрочка'), isNull);
    // Survives the memory file.
    final again = PersonalMemory.fromJson(memory.toJson());
    expect(again.aliases, {'кб': 'Красное&Белое'});
    expect(memory.toJson()['version'], 5);
    // A version 4 file (before short names) still opens.
    final old = PersonalMemory.fromJson({'version': 4});
    expect(old.aliases, isEmpty);
    expect(PayeeAliases.forget(memory, 'КБ'), isTrue);
    expect(memory.aliases, isEmpty);
  });

  test('a chat draft writes the short name in full and its usual category', () {
    const data = FinanceData(
      accounts: [Account(id: 'card', name: 'Основная карта')],
      categories: [
        Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
        Category(id: 'alco', name: 'Напитки', kind: EntryKind.expense),
      ],
    );
    final memory = PersonalMemory();
    PayeeAliases.learn(memory, 'кб', 'Красное&Белое');
    final session = AiActionSession()
      ..payeeResolver = ((p) => PayeeAliases.resolve(memory, p) ?? p)
      ..rememberedCategory = ((p, kind) =>
          PayeeAliases.resolve(memory, p) == 'Красное&Белое' ? 'alco' : null);
    final r = session.resolveDeterministic(
      'Добавь расход кб 500 рублей с основной карты',
      data: data,
      now: DateTime(2026, 11, 18, 12),
      requestId: 'alias-1',
    );
    final draft = r!.pending?.entry;
    expect(draft, isNotNull, reason: r.message);
    expect(draft!.payee, 'Красное&Белое');
    expect(draft.categoryId, 'alco');
    expect(draft.amountMinor, 50000);
    expect(r.message, contains('Красное&Белое'));
  });
}
