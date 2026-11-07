/// App languages (Finora 1.28). Russian is the source; other languages map
/// each Russian line to its translation, and anything not translated yet
/// stays in Russian. Voice commands and money tips are Russian-only for now.
abstract final class AppLanguage {
  static String code = 'ru';

  static const names = <String, String>{'ru': 'Русский', 'en': 'English'};

  static const _en = <String, String>{
    // Bottom bar and header.
    'Главная': 'Home',
    'Операции': 'Transactions',
    'Аналитика': 'Analytics',
    'Ещё': 'More',
    'Общий баланс': 'Total balance',
    'Настройки': 'Settings',
    'Моя семья': 'My family',
    // Main screen.
    'Доходы': 'Income',
    'Расходы': 'Expenses',
    'Счета': 'Accounts',
    'Все': 'All',
    'Обзор месяца': 'Month overview',
    'Календарь': 'Calendar',
    'Мечты и накопления': 'Dreams & savings',
    'Подписки': 'Subscriptions',
    'Обязательные платежи': 'Required payments',
    'Бюджеты': 'Budgets',
    'Последние операции': 'Recent transactions',
    'Ещё совет': 'Another tip',
    'ФИНАНСОВАЯ ГРАМОТНОСТЬ': 'MONEY BASICS',
    // More.
    'Деньги': 'Money',
    'Планирование': 'Planning',
    'Общее': 'General',
    'Карты, наличные и вклады': 'Cards, cash and deposits',
    'Мечты': 'Dreams',
    'Цели и накопления': 'Goals and savings',
    'Подписки и платежи': 'Subscriptions & payments',
    'Регулярные списания и доходы': 'Recurring charges and income',
    'Расходы в пределах плана': 'Spending within the plan',
    'Операции и платежи по датам': 'Transactions and payments by date',
    'Категории': 'Categories',
    'Доходы, расходы и иконки': 'Income, expenses and icons',
    'Семья': 'Family',
    'Участники общего бюджета': 'Members of the shared budget',
    'Вид, защита, копии и обучение': 'Look, security, backups and tour',
    // Settings.
    'Основное': 'Basics',
    'Внешний вид': 'Appearance',
    'Валюта и форматы': 'Currency & formats',
    'Уведомления': 'Notifications',
    'Защита': 'Security',
    'Данные': 'Data',
    'Резервные копии': 'Backups',
    'Сохранить и восстановить': 'Save and restore',
    'Перенести счета со скриншота': 'Import accounts from a screenshot',
    'Из другого приложения или банка': 'From another app or bank',
    'Финора': 'Finora',
    'Отзываться на «Финора»': 'Answer to «Finora»',
    'Пока приложение открыто на экране': 'While the app is open',
    'Финора в шторке': 'Finora in the shade',
    'Советы по финансам': 'Money tips',
    'Карточка Финоры на главной': 'Finora’s card on Home',
    'Тактильный отклик': 'Haptic feedback',
    'Лёгкая отдача на нажатия и реакции':
        'A light tap on touches and reactions',
    'Что умеет Finora': 'What Finora can do',
    'Короткое обучение': 'A short tour',
    'О приложении': 'About',
    'Сбросить все данные': 'Erase all data',
    'Язык': 'Language',
    'Имя, валюта, форматы': 'Name, currency, formats',
    'Ваше имя': 'Your name',
    'Основные': 'Basics',
    // Editor.
    'Расход': 'Expense',
    'Доход': 'Income',
    'Перевод': 'Transfer',
    'СУММА': 'AMOUNT',
    'Счёт': 'Account',
    'Откуда и куда': 'From and to',
    'Категория': 'Category',
    'Подробности': 'Details',
    'Получатель / магазин': 'Payee / store',
    'Сохранить операцию': 'Save transaction',
    'Дополнительные поля': 'More fields',
    'Комментарий': 'Note',
    'Изменить': 'Change',
    'Новая операция': 'New transaction',
    'Покупка или платёж': 'A purchase or payment',
    'Поступление на счёт': 'Money in',
    'Между своими счетами': 'Between your accounts',
    'Скриншот из банка': 'Bank screenshot',
    'Одна операция или список операций': 'One transaction or a list',
    'Открыть счета': 'Open accounts',
  };

  /// [ru] in the current language.
  static String t(String ru) => code == 'en' ? (_en[ru] ?? ru) : ru;
}

/// Shorthand for [AppLanguage.t].
String tr(String ru) => AppLanguage.t(ru);
