import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/voice_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.24: dreams, accounts, budgets, categories and regular payments
/// created by voice.
void main() {
  final now = DateTime(2026, 11, 6);
  final categories = createDemoData(now).categories;
  const accounts = [
    Account(id: 'tb', name: 'Тинькофф Black'),
    Account(id: 'cash', name: 'Наличные'),
  ];
  VoiceCommand? parse(String phrase) => VoiceCommandParser.parse(
    [phrase],
    categories: categories,
    accounts: accounts,
    now: now,
  );
  String category(String? id) => categories.firstWhere((c) => c.id == id).name;

  test('dreams', () {
    final car = parse('Хочу машину за 2 млн')! as CreateGoalCommand;
    expect(car.name, 'Машина');
    expect(car.targetMinor, 200000000);
    expect(car.deadline, isNull);
    final flat =
        parse('я хочу новую квартиру за 12 миллионов к 2030 году')!
            as CreateGoalCommand;
    expect(flat.name, 'Новая квартира');
    expect(flat.targetMinor, 1200000000);
    expect(flat.deadline, DateTime(2030, 12, 31));
    final sea = parse('хочу на море за 150 тысяч к лету')! as CreateGoalCommand;
    expect(sea.name, 'Поездка на море');
    expect(sea.targetMinor, 15000000);
    expect(sea.deadline, DateTime(2027, 6, 30));
    final phone =
        parse('коплю на айфон 120 тысяч до декабря')! as CreateGoalCommand;
    expect(phone.name, 'Айфон');
    expect(phone.deadline, DateTime(2026, 12, 31));
    final japan =
        parse('добавь мечту поездку в Японию 500 тысяч через 2 года')!
            as CreateGoalCommand;
    expect(japan.name, 'Поездка в Японию');
    expect(japan.deadline, DateTime(2028, 11, 6));
    final bare = parse('хочу машину')! as CreateGoalCommand;
    expect(bare.targetMinor, isNull);
    // Not dreams.
    expect(parse('хочу посмотреть расходы за июнь'), isA<ShowEntriesCommand>());
    expect(parse('хочу зеленую тему'), isA<ThemeCommand>());
    expect(parse('мои цели'), isA<OpenScreenCommand>());
  });

  test('accounts', () {
    final sber =
        parse('добавь карту Сбер с балансом 15 тысяч')! as CreateAccountCommand;
    expect(sber.name, 'Сбербанк');
    expect(sber.bank, 'Сбербанк');
    expect(sber.type, 'debit');
    expect(sber.openingMinor, 1500000);
    final cash =
        parse('создай счет наличные 3000 рублей')! as CreateAccountCommand;
    expect(cash.name, 'Наличные');
    expect(cash.type, 'cash');
    expect(cash.openingMinor, 300000);
    final debt =
        parse('добавь кредитку Альфа минус 30 тысяч')! as CreateAccountCommand;
    expect(debt.type, 'credit');
    expect(debt.openingMinor, -3000000);
    final deposit =
        parse('открой новый вклад 500 тысяч')! as CreateAccountCommand;
    expect(deposit.name, 'Вклад');
    expect(deposit.type, 'deposit');
    // Navigation stays navigation.
    expect(parse('открой счета'), isA<OpenScreenCommand>());
  });

  test('budgets and categories', () {
    final food = parse('бюджет на продукты 20 тысяч')! as CreateBudgetCommand;
    expect(category(food.categoryId), 'Продукты');
    expect(food.limitMinor, 2000000);
    final all = parse('поставь лимит 60 тысяч в месяц')! as CreateBudgetCommand;
    expect(all.categoryId, isNull);
    expect(all.name, 'Бюджет месяца');
    expect(parse('открой бюджеты'), isA<OpenScreenCommand>());
    final sport = parse('добавь категорию Спорт')! as CreateCategoryCommand;
    expect(sport.name, 'Спорт');
    expect(sport.kind, isNull);
    final free =
        parse('создай категорию доходов фриланс')! as CreateCategoryCommand;
    expect(free.name, 'Фриланс');
    expect(free.kind, EntryKind.income);
    expect(parse('покажи категории'), isA<OpenScreenCommand>());
  });

  test('regular payments', () {
    final plus =
        parse('подписка Яндекс Плюс 399 в месяц')! as CreateRecurringCommand;
    expect(plus.amountMinor, 39900);
    expect(plus.frequency, 'monthly');
    expect(plus.paymentType, 'subscription');
    expect(plus.serviceId, isNotNull);
    expect(plus.nextDate, DateTime(2026, 12, 6));
    final salary =
        parse('зарплата 90 тысяч каждый месяц 10 числа')!
            as CreateRecurringCommand;
    expect(salary.kind, EntryKind.income);
    expect(salary.amountMinor, 9000000);
    expect(salary.nextDate, DateTime(2026, 11, 10));
    expect(category(salary.categoryId), 'Зарплата');
    final rent =
        parse('добавь регулярный платеж аренда 40 тысяч 1 числа')!
            as CreateRecurringCommand;
    expect(rent.name, 'Аренда');
    expect(rent.paymentType, 'mandatory');
    expect(rent.nextDate, DateTime(2026, 12, 1));
    final gym =
        parse('абонемент в зал 3000 в месяц с тинькофф')!
            as CreateRecurringCommand;
    expect(gym.accountId, 'tb');
    final yearly =
        parse('подписка айклауд 1490 в год')! as CreateRecurringCommand;
    expect(yearly.frequency, 'yearly');
    // Paying a subscription once is an operation.
    expect(parse('оплатил подписку нетфликс 799'), isNull);
    expect(parse('нетфликс 799'), isNull);
    expect(parse('покажи подписки'), isA<OpenScreenCommand>());
    expect(
      parse('сколько я трачу в месяц'),
      isNot(isA<CreateRecurringCommand>()),
    );
  });

  test('operations stay operations', () {
    for (final phrase in [
      'пятерочка 450 рублей',
      'запиши кофе 300',
      'добавь расход 500 на такси',
      'зарплата 90 тысяч',
      'перевод на накопительный 5000',
    ]) {
      expect(parse(phrase), isNull, reason: phrase);
    }
  });
}
