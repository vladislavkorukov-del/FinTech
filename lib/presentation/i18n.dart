import 'l10n_table.dart';

/// App languages (Finora 1.28). Russian is the source; other languages map
/// each Russian line to its translation, and anything not translated yet
/// stays in Russian. Voice commands and money tips are Russian-only for now.
abstract final class AppLanguage {
  static String code = 'ru';

  static const names = <String, String>{
    'ru': 'Русский',
    'en': 'English',
    'es': 'Español',
    'pt': 'Português',
    'fr': 'Français',
    'de': 'Deutsch',
    'zh': '中文',
    'hi': 'हिन्दी',
    'ar': 'العربية',
  };

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
    'Платежи и подписки': 'Payments & subscriptions',
    'Кредиты, аренда, подписки, доходы': 'Loans, rent, subscriptions, income',
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

  /// The `intl` locale for dates and months.
  static String get intl => code;

  /// RTL languages.
  static bool get rtl => code == 'ar';

  static Map<String, String>? _exactFor;
  static String? _exactCode;
  static List<(RegExp, String)> _patterns = const [];

  static Map<String, String> _exact() {
    if (_exactCode == code && _exactFor != null) return _exactFor!;
    final i = l10nLanguages.indexOf(code);
    final map = <String, String>{if (code == 'en') ..._en};
    final patterns = <(RegExp, String, int)>[];
    if (i >= 0) {
      for (final e in l10nTable.entries) {
        final value = e.value[i];
        if (e.key.contains('{1}')) {
          final literal = e.key.replaceAll(RegExp(r'\{\d\}'), '');
          final source = e.key
              .split(RegExp(r'(\{\d\})'))
              .map(RegExp.escape)
              .join('(.+?)');
          // Keep which placeholder each group is.
          final order = RegExp(
            r'\{(\d)\}',
          ).allMatches(e.key).map((m) => m[1]).join(',');
          patterns.add((
            RegExp('^$source\$', dotAll: true),
            '$order|$value',
            literal.length,
          ));
        } else {
          map[e.key] = value;
        }
      }
    }
    // The most specific patterns first.
    patterns.sort((x, y) => y.$3.compareTo(x.$3));
    _patterns = [for (final p in patterns) (p.$1, p.$2)];
    _exactFor = map;
    _exactCode = code;
    return map;
  }

  static final _cyrillic = RegExp('[А-Яа-яЁё]');

  /// [ru] in the current language (1.37: nine languages). Lines with values
  /// inside («Осталось 5 000 ₽») are matched by their patterns.
  static String t(String ru) {
    if (code == 'ru' || ru.isEmpty) return ru;
    final exact = _exact();
    final hit = exact[ru];
    if (hit != null) return hit;
    if (!_cyrillic.hasMatch(ru)) return ru;
    for (final (re, template) in _patterns) {
      final m = re.firstMatch(ru);
      if (m == null) continue;
      final bar = template.indexOf('|');
      final order = template.substring(0, bar).split(',');
      var out = template.substring(bar + 1);
      for (var g = 0; g < order.length; g++) {
        final value = m.group(g + 1)!;
        out = out.replaceAll('{${order[g]}}', exact[value] ?? value);
      }
      return out;
    }
    return ru;
  }
}

/// Shorthand for [AppLanguage.t].
String tr(String ru) => AppLanguage.t(ru);
