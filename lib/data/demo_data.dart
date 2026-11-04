import '../domain/models.dart';

/// A local demonstration ledger. Dates move with first launch, never with reload.
FinanceData createDemoData(DateTime now) {
  const expenseNames = [
    'Продукты',
    'Кафе и рестораны',
    'Транспорт',
    'Автомобиль',
    'Жильё',
    'Коммунальные',
    'Здоровье',
    'Аптека',
    'Развлечения',
    'Подписки',
    'Покупки',
    'Одежда',
    'Подарки',
    'Путешествия',
    'Образование',
    'Дети',
    'Животные',
    'Налоги',
    'Кредиты',
    'Прочее',
  ];
  const incomeNames = [
    'Зарплата',
    'Подработка',
    'Бизнес',
    'Проценты',
    'Инвестиции',
    'Возвраты',
    'Подарки',
    'Прочее',
  ];
  const colors = [
    0xffc9f36f,
    0xffddb994,
    0xff9fb3f0,
    0xfff0a4af,
    0xff91c8b2,
    0xffc6ace9,
    0xffe0cb89,
    0xff8fc9d2,
  ];
  final categories = [
    for (var i = 0; i < expenseNames.length; i++)
      Category(
        id: 'expense-$i',
        name: expenseNames[i],
        kind: EntryKind.expense,
        color: colors[i % colors.length],
        background: (colors[i % colors.length] & 0x00ffffff) | 0x20000000,
        icon: i,
        order: i,
        subcategories: i == 0 ? ['Супермаркет', 'Рынок'] : const [],
      ),
    for (var i = 0; i < incomeNames.length; i++)
      Category(
        id: 'income-$i',
        name: incomeNames[i],
        kind: EntryKind.income,
        color: colors[(i + 4) % colors.length],
        background: (colors[(i + 4) % colors.length] & 0x00ffffff) | 0x20000000,
        icon: 20 + i,
        order: 20 + i,
      ),
  ];
  final accounts = [
    const Account(
      id: 'card',
      name: 'Основная карта',
      type: 'debit',
      bank: 'Мой банк',
      lastFour: '4821',
      openingMinor: 6850000,
      color: 0xffc9f36f,
      icon: 18,
    ),
    const Account(
      id: 'cash',
      name: 'Наличные',
      type: 'cash',
      openingMinor: 1450000,
      color: 0xffddb994,
      icon: 26,
    ),
    const Account(
      id: 'savings',
      name: 'Накопительный',
      type: 'savings',
      openingMinor: 22000000,
      color: 0xff9fb3f0,
      icon: 27,
    ),
  ];
  final entries = <FinanceEntry>[];
  void expense(
    int index,
    int dayOffset,
    int amount,
    String payee, {
    bool previous = false,
  }) {
    var day = now.subtract(Duration(days: dayOffset));
    if (previous) {
      day = DateTime(now.year, now.month - 1, 5 + dayOffset, 12);
    }
    entries.add(
      FinanceEntry(
        id: 'demo-${entries.length}',
        kind: EntryKind.expense,
        amountMinor: amount,
        currency: 'RUB',
        accountId: index == 2 ? 'cash' : 'card',
        categoryId: 'expense-$index',
        date: day,
        payee: payee,
        memberId: entries.length.isEven ? 'me' : 'family',
        tags: index == 0 ? const ['Дом'] : const [],
      ),
    );
  }

  entries.add(
    FinanceEntry(
      id: 'salary-now',
      kind: EntryKind.income,
      amountMinor: 14500000,
      currency: 'RUB',
      accountId: 'card',
      categoryId: 'income-0',
      date: DateTime(now.year, now.month, 1, 10),
      payee: 'Зарплата',
      memberId: 'me',
    ),
  );
  entries.add(
    FinanceEntry(
      id: 'salary-previous',
      kind: EntryKind.income,
      amountMinor: 13200000,
      currency: 'RUB',
      accountId: 'card',
      categoryId: 'income-0',
      date: DateTime(now.year, now.month - 1, 1, 10),
      payee: 'Зарплата',
      memberId: 'me',
    ),
  );
  expense(0, 0, 384500, 'ВкусВилл');
  expense(1, 0, 129000, 'Кофейня «Утро»');
  expense(2, 1, 89000, 'Городской транспорт');
  expense(10, 1, 620000, 'Покупки для дома');
  expense(9, 2, 129900, 'Музыка и кино');
  expense(0, 3, 647800, 'Продукты на неделю');
  expense(6, 4, 280000, 'Клиника');
  expense(8, 5, 320000, 'Выходные с семьёй');
  expense(0, 5, 724000, 'Супермаркет', previous: true);
  expense(1, 7, 487000, 'Рестораны', previous: true);
  expense(2, 10, 239000, 'Транспорт', previous: true);
  expense(10, 12, 912000, 'Покупки', previous: true);
  expense(8, 15, 479000, 'Развлечения', previous: true);
  entries.add(
    FinanceEntry(
      id: 'demo-transfer',
      kind: EntryKind.transfer,
      amountMinor: 1000000,
      currency: 'RUB',
      accountId: 'card',
      toAccountId: 'savings',
      date: now.subtract(const Duration(days: 1)),
      note: 'В резерв',
      memberId: 'me',
    ),
  );
  return FinanceData(
    accounts: accounts,
    categories: categories,
    entries: entries,
    budgets: const [
      Budget(id: 'all', name: 'Бюджет месяца', limitMinor: 6000000),
      Budget(
        id: 'food',
        name: 'Продукты',
        categoryId: 'expense-0',
        limitMinor: 2000000,
      ),
      Budget(
        id: 'fun',
        name: 'Развлечения',
        categoryId: 'expense-8',
        limitMinor: 500000,
      ),
      Budget(
        id: 'transport',
        name: 'Транспорт',
        categoryId: 'expense-2',
        limitMinor: 800000,
      ),
    ],
    goals: [
      Goal(
        id: 'holiday',
        name: 'Путешествие к морю',
        targetMinor: 25000000,
        savedMinor: 18000000,
        color: 0xffddb994,
        icon: 13,
        deadline: DateTime(now.year + 1, 6, 1),
      ),
      const Goal(
        id: 'reserve',
        name: 'Подушка безопасности',
        targetMinor: 60000000,
        savedMinor: 22000000,
        color: 0xff9fb3f0,
        icon: 6,
      ),
    ],
    recurring: [
      RecurringRule(
        id: 'internet',
        paymentType: 'mandatory',
        name: 'Интернет',
        accountId: 'card',
        categoryId: 'expense-5',
        amountMinor: 75000,
        nextDate: DateTime(now.year, now.month, now.day + 1, 10),
      ),
      RecurringRule(
        id: 'subscription',
        paymentType: 'subscription',
        name: 'Музыка',
        accountId: 'card',
        categoryId: 'expense-9',
        amountMinor: 39900,
        nextDate: DateTime(now.year, now.month, now.day + 5, 10),
      ),
      RecurringRule(
        id: 'mortgage',
        name: 'Платёж по кредиту',
        accountId: 'card',
        categoryId: 'expense-18',
        paymentType: 'mandatory',
        amountMinor: 1450000,
        nextDate: DateTime(now.year, now.month, now.day + 8, 10),
      ),
    ],
    members: const [
      Member(id: 'me', name: 'Я'),
      Member(id: 'family', name: 'Семья'),
    ],
    preferences: const AppPreferences(),
    demo: true,
  );
}
