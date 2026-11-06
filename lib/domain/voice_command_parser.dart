import 'account_import_parser.dart';
import 'models.dart';
import 'service_catalog.dart';
import 'service_recognizer.dart';
import 'voice_entry_parser.dart';

/// A spoken command (Finance 1.23): navigation, a filtered list of
/// operations or a theme change. A phrase that is not a command («Пятёрочка
/// 450») is an operation and goes to the entry editor instead.
sealed class VoiceCommand {
  const VoiceCommand(this.heard);
  final String heard;
}

/// «Поменяй тему на зелёную», «сделай тёмную тему», «тема Сансет».
class ThemeCommand extends VoiceCommand {
  const ThemeCommand(
    super.heard, {
    this.mode,
    this.preset,
    this.hue,
    this.gray = false,
    this.color = '',
  });

  /// 'dark', 'light' or 'system'.
  final String? mode;

  /// A theme named outright («изумрудная», «Сансет»).
  final String? preset;

  /// The hue asked for in degrees («зелёная» → 125), matched against the
  /// accents of the themes.
  final double? hue;

  /// «Серая», «графитовая»: the least colorful accent.
  final bool gray;

  /// The color word as said, for the confirmation («зелёный»).
  final String color;

  /// Whether a color or a theme name was said.
  bool get hasColor => preset != null || hue != null || gray;

  /// Only «поменяй тему»: any other theme.
  bool get anyOther => mode == null && !hasColor;
}

/// «Покажи расходы за июнь», «доход за год», «траты на такси в мае».
class ShowEntriesCommand extends VoiceCommand {
  const ShowEntriesCommand(
    super.heard, {
    this.kind,
    this.start,
    this.end,
    this.categoryId,
    this.accountId,
    required this.title,
  });
  final EntryKind? kind;

  /// First and last day, both included; null for all time.
  final DateTime? start, end;
  final String? categoryId, accountId;

  /// «Расходы · июнь 2026».
  final String title;
}

enum VoiceScreen {
  home,
  operations,
  analytics,
  more,
  settings,
  accounts,
  goals,
  budgets,
  calendar,
  categories,
  members,
  recurring,
  importAccounts,
}

/// «Открой настройки», «покажи аналитику», «на главную».
class OpenScreenCommand extends VoiceCommand {
  const OpenScreenCommand(super.heard, this.screen);
  final VoiceScreen screen;
}

/// Sounded like a command («покажи …») but nothing in it was understood.
class UnknownCommand extends VoiceCommand {
  const UnknownCommand(super.heard);
}

/// «Хочу машину за 2 млн» → a dream (goal) to save for (1.24).
class CreateGoalCommand extends VoiceCommand {
  const CreateGoalCommand(
    super.heard, {
    required this.name,
    this.targetMinor,
    this.deadline,
  });
  final String name;

  /// Null when no price was heard: the person is asked for it.
  final int? targetMinor;
  final DateTime? deadline;
}

/// «Добавь карту Сбер с балансом 15 тысяч».
class CreateAccountCommand extends VoiceCommand {
  const CreateAccountCommand(
    super.heard, {
    required this.name,
    required this.type,
    this.openingMinor = 0,
    this.bank = '',
  });
  final String name, type, bank;
  final int openingMinor;
}

/// «Бюджет на продукты 20 тысяч».
class CreateBudgetCommand extends VoiceCommand {
  const CreateBudgetCommand(
    super.heard, {
    required this.name,
    required this.limitMinor,
    this.categoryId,
  });
  final String name;
  final int limitMinor;
  final String? categoryId;
}

/// «Добавь категорию Спорт», «новая категория доходов Фриланс».
class CreateCategoryCommand extends VoiceCommand {
  const CreateCategoryCommand(super.heard, {required this.name, this.kind});
  final String name;
  final EntryKind? kind;
}

/// «Подписка Яндекс Плюс 399 в месяц», «зарплата 90 тысяч каждый месяц
/// 10 числа».
class CreateRecurringCommand extends VoiceCommand {
  const CreateRecurringCommand(
    super.heard, {
    required this.name,
    this.amountMinor,
    this.kind = EntryKind.expense,
    this.frequency = 'monthly',
    this.paymentType = 'mandatory',
    this.serviceId,
    this.categoryId,
    this.accountId,
    required this.nextDate,
  });
  final String name, frequency, paymentType;
  final int? amountMinor;
  final EntryKind kind;
  final String? serviceId, categoryId, accountId;
  final DateTime nextDate;
}

abstract final class VoiceCommandParser {
  /// The first hypothesis that is a command; null when the phrase is an
  /// operation to record.
  static VoiceCommand? parse(
    List<String> hypotheses, {
    List<Category> categories = const [],
    List<Account> accounts = const [],
    DateTime? now,
    int weekStart = 1,
  }) {
    final today = _day(now ?? DateTime.now());
    UnknownCommand? unknown;
    for (final heard in hypotheses) {
      final command = _one(heard, categories, accounts, today, weekStart);
      if (command is UnknownCommand) {
        unknown ??= command;
      } else if (command != null) {
        return command;
      }
    }
    return unknown;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^а-яa-z0-9 ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static final _showVerb = RegExp(
    r'^(?:а |ну |пожалуйста |слушай )*(?:покажи|показать|покажите|открой|'
    r'открыть|откройте|перейди|перейти|зайди|выведи|вывести|сколько|'
    r'отобрази|найди|давай|хочу посмотреть|посмотреть|посмотрим|какие|'
    r'какой|мои|вернись|иди|на главн\S*|на домашн\S*|домой)(?![а-яa-z0-9])',
  );
  static final _themeVerb = RegExp(
    r'(?<![а-яa-z0-9])(?:поменяй|поменять|смени|сменить|измени|изменить|включи|включить|'
    r'сделай|сделать|поставь|поставить|установи|переключи|переключись|'
    r'выбери|хочу|давай)(?![а-яa-z0-9])',
  );
  static final _themeWord = RegExp(
    r'(?<![а-яa-z0-9])(?:тем[аыуеой]|темку)(?![а-яa-z0-9])',
  );
  static final _colorWord = RegExp(
    r'(?<![а-яa-z0-9])(?:цвет\S*|оформлени\S*)(?![а-яa-z0-9])',
  );
  static final _modeWord = RegExp(
    r'(?<![а-яa-z0-9])(?:темн\S*|светл\S*|ночн\S*|дневн\S*|системн\S*)(?![а-яa-z0-9])',
  );

  /// Plural nouns that start a request without a verb: «расходы за июнь».
  static final _listStart = RegExp(
    r'^(?:все |мои )?(?:расходы|траты|доходы|поступления|переводы|операции)(?![а-яa-z0-9])',
  );

  static VoiceCommand? _one(
    String heard,
    List<Category> categories,
    List<Account> accounts,
    DateTime today,
    int weekStart,
  ) {
    // 1.26: «Финора, покажи расходы» — the name is a greeting, not a word.
    final t = _norm(heard).replaceFirst(
      RegExp(r'^(?:эй |слушай |привет |ну )?(?:финора|финор|finora) ?'),
      '',
    );
    if (t.isEmpty) return null;
    if (!_amount(t) &&
        (_themeWord.hasMatch(t) ||
            _themeVerb.hasMatch(t) &&
                (_modeWord.hasMatch(t) || _colorWord.hasMatch(t)))) {
      return _theme(heard, t);
    }
    final create = _create(heard, t, categories, accounts, today);
    if (create != null) return create;
    final verb = _showVerb.hasMatch(t);
    if (!verb && !(_listStart.hasMatch(t) && !_amount(t))) return null;
    return _show(heard, t, categories, accounts, today, weekStart);
  }

  /// Digits that are a sum, not a year («за 2025 год») or a count
  /// («последние 3 месяца»).
  static bool _amount(
    String t,
  ) => RegExp(r'\d+(?!\d)(?! ?(?:год|г(?![а-яa-z])|дн|день|недел|месяц))')
      .allMatches(t)
      .any(
        (m) => !RegExp(
          r'(?:январ|феврал|март|апрел|ма[йяе]|июн|июл|август|сентябр|октябр|'
          r'ноябр|декабр)\S* $',
        ).hasMatch(t.substring(0, m.start)),
      );

  // ── Theme ─────────────────────────────────────────────────────────────

  /// Color words and the hue they mean.
  static const _colors = <(String, double, String)>[
    ('салат', 85, 'салатовый'),
    ('лайм', 80, 'лаймовый'),
    ('изумруд', 140, 'изумрудный'),
    ('зелен', 125, 'зелёный'),
    ('бирюз', 172, 'бирюзовый'),
    ('мятн', 160, 'мятный'),
    ('голуб', 195, 'голубой'),
    ('морск', 195, 'морской'),
    ('син', 215, 'синий'),
    ('лаванд', 255, 'лавандовый'),
    ('сирен', 265, 'сиреневый'),
    ('фиолет', 272, 'фиолетовый'),
    ('пурпур', 300, 'пурпурный'),
    ('малин', 330, 'малиновый'),
    ('розов', 335, 'розовый'),
    ('бордов', 345, 'бордовый'),
    ('красн', 8, 'красный'),
    ('оранж', 30, 'оранжевый'),
    ('рыж', 28, 'рыжий'),
    ('коричн', 28, 'коричневый'),
    ('золот', 45, 'золотой'),
    ('желт', 55, 'жёлтый'),
  ];

  /// Theme names as people say them.
  static const _presets = <(String, String)>[
    ('кофе', 'coffee'),
    ('коф', 'coffee'),
    ('электрик', 'electric'),
    ('шалфе', 'sage'),
    ('сейдж', 'sage'),
    ('бумаж', 'paper'),
    ('бумаг', 'paper'),
    ('полноч', 'midnight'),
    ('миднайт', 'midnight'),
    ('харбор', 'harbor'),
    ('лесн', 'forest'),
    ('форест', 'forest'),
    ('вельвет', 'velvet'),
    ('аврор', 'aurora'),
    ('роял', 'royal'),
    ('нитро', 'royal'),
    ('сансет', 'sunset'),
    ('закат', 'sunset'),
    ('неон', 'neon'),
    ('кримсон', 'crimson'),
    ('даск', 'dusk'),
    ('сумереч', 'dusk'),
    ('тропи', 'tropic'),
    ('твайлайт', 'twilight'),
    ('пастел', 'twilight'),
    ('слив', 'plum'),
    ('плам', 'plum'),
    ('вин', 'wine'),
    ('медн', 'copper'),
    ('коппер', 'copper'),
    ('песоч', 'sand'),
    ('сэнд', 'sand'),
    ('абрикос', 'apricot'),
    ('холст', 'terracotta'),
    ('терракот', 'terracotta'),
  ];

  static ThemeCommand _theme(String heard, String t) {
    final words = t.split(' ');
    bool has(String stem) => words.any((w) => w.startsWith(stem));
    String? mode;
    if (has('темн') || has('ночн')) {
      mode = 'dark';
    } else if (has('светл') || has('дневн')) {
      mode = 'light';
    } else if (has('системн') || t.contains('как в системе')) {
      mode = 'system';
    }
    for (final (stem, id) in _presets) {
      if (has(stem)) return ThemeCommand(heard, mode: mode, preset: id);
    }
    if (has('сер') && !has('серд') || has('графит') || has('строг')) {
      return ThemeCommand(heard, mode: mode, gray: true, color: 'серый');
    }
    for (final (stem, hue, name) in _colors) {
      if (has(stem)) {
        return ThemeCommand(heard, mode: mode, hue: hue, color: name);
      }
    }
    return ThemeCommand(heard, mode: mode);
  }

  // ── Creating things ───────────────────────────────────────────────────

  static const _createVerbs = {
    'добавь',
    'добавить',
    'добавим',
    'создай',
    'создать',
    'создадим',
    'заведи',
    'завести',
    'новый',
    'новая',
    'новую',
    'новое',
    'запиши',
    'запомни',
    'поставь',
    'установи',
    'сделай',
    'открой',
  };

  static VoiceCommand? _create(
    String heard,
    String t,
    List<Category> categories,
    List<Account> accounts,
    DateTime today,
  ) {
    final words = t.split(' ');
    bool has(String stem) => words.any((w) => w.startsWith(stem));
    final verb = words.any(_createVerbs.contains);
    // «Открой счета» is navigation; «открой новый счёт» creates one.
    final opens = words.first == 'открой' && !has('нов');
    final looking = RegExp(
      r'(?:^| )(?:посмотреть|увидеть|узнать|открыть|глянуть)(?: |$)',
    ).hasMatch(t);

    // Dreams.
    final dream =
        RegExp(
          r'^(?:я )?(?:хочу|хотел бы|хотела бы|мечтаю)(?: |$)',
        ).hasMatch(t) ||
        RegExp(
          r'(?:^| )(?:коплю|накопить|копить|откладываю)(?: |$)',
        ).hasMatch(t) ||
        verb && !opens && (has('мечт') || has('цел'));
    if (dream && !looking) return _goal(heard, t, today);

    final frequency = _showVerb.hasMatch(t) ? null : _frequency(t);
    if ((verb && !opens || frequency != null) &&
        (has('подписк') ||
            has('регулярн') ||
            has('автоплат') ||
            has('абонемент') ||
            frequency != null && !has('бюджет') && !has('лимит'))) {
      return _recurring(heard, t, frequency, categories, accounts, today);
    }

    final money = VoiceEntryParser.amountIn(heard);
    if ((has('бюджет') || has('лимит')) && money != null && !has('кредитн')) {
      final category = _match(
        words,
        categories
            .where((c) => !c.archived && c.kind == EntryKind.expense)
            .map((c) => (c.id, c.name)),
      );
      final name = category == null
          ? 'Бюджет месяца'
          : categories.firstWhere((c) => c.id == category).name;
      return CreateBudgetCommand(
        heard,
        name: name,
        limitMinor: money.minor,
        categoryId: category,
      );
    }
    if (!verb || opens && !has('нов')) return null;

    if (has('категори')) {
      final kind = has('доход')
          ? EntryKind.income
          : has('расход')
          ? EntryKind.expense
          : null;
      final name = _name(heard, t, const {
        'категорию',
        'категория',
        'категории',
        'для',
        'доходов',
        'доходы',
        'доход',
        'расходов',
        'расходы',
        'расход',
        'под',
        'с',
        'названием',
        'назови',
        'называется',
        'по',
      });
      return name.isEmpty
          ? UnknownCommand(heard)
          : CreateCategoryCommand(heard, name: name, kind: kind);
    }

    if (has('счет') ||
        has('карт') ||
        has('кошел') ||
        has('вклад') ||
        has('наличн') ||
        has('копилк') ||
        has('кредитк')) {
      final debt = has('минус') || has('долг');
      final opening = (money?.minor ?? 0) * (debt ? -1 : 1);
      var name = _name(heard, money?.rest ?? t, const {
        'счет',
        'счета',
        'карту',
        'карта',
        'кошелек',
        'с',
        'со',
        'балансом',
        'баланс',
        'остатком',
        'остаток',
        'на',
        'нем',
        'ней',
        'в',
        'где',
        'лежит',
        'лежат',
        'есть',
        'и',
        'минус',
        'долг',
        'долгом',
        'названием',
        'под',
        'банке',
        'банк',
      });
      final kindName = has('кредитк') || has('кредитн')
          ? 'Кредитная карта'
          : has('налич')
          ? 'Наличные'
          : has('вклад')
          ? 'Вклад'
          : has('копилк')
          ? 'Копилка'
          : has('накопит')
          ? 'Накопительный счёт'
          : has('кошел')
          ? 'Кошелёк'
          : has('карт')
          ? 'Карта'
          : 'Счёт';
      final bank = name.isEmpty ? '' : AccountImportParser.bankFor(name);
      if (bank.isNotEmpty && !name.contains(' ')) name = bank;
      if (name.isEmpty) name = kindName;
      final type = AccountImportParser.typeFor('$kindName $name', opening, '');
      return CreateAccountCommand(
        heard,
        name: name,
        type: type,
        openingMinor: opening,
        bank: bank,
      );
    }
    return null;
  }

  /// 'weekly', 'monthly' or 'yearly' when the phrase says how often.
  static String? _frequency(String t) {
    if (RegExp(
      r'ежемесячн|каждый месяц|каждого месяца|в месяц|раз в месяц|помесячн',
    ).hasMatch(t)) {
      return 'monthly';
    }
    if (RegExp(r'ежегодн|каждый год|в год|раз в год').hasMatch(t)) {
      return 'yearly';
    }
    if (RegExp(r'еженедельн|каждую неделю|в неделю|раз в неделю').hasMatch(t)) {
      return 'weekly';
    }
    if (RegExp(r'ежедневн|каждый день|в день').hasMatch(t)) return 'daily';
    return null;
  }

  static CreateGoalCommand _goal(String heard, String t, DateTime today) {
    // A deadline is said with «к»/«до»/«через», never «за» (that is the
    // price): «к лету», «до декабря», «к 2028 году», «через 2 года».
    DateTime? deadline;
    var text = t;
    final by = RegExp(
      r'(?:^| )(?:к|до) (?:концу |конца )?(?:(20\d\d)(?: году| года| год)?|'
      r'([а-я]+)(?: (20\d\d))?(?: году| года)?)(?= |$)',
    );
    for (final m in by.allMatches(t)) {
      final year = int.tryParse(m.group(1) ?? m.group(3) ?? '');
      final word = m.group(2);
      DateTime? found;
      if (word == null && year != null) {
        found = DateTime(year, 12, 31);
      } else if (word != null) {
        final seasons = {'лет': 6, 'осен': 9, 'зим': 12, 'весн': 3};
        int? month;
        for (var i = 0; i < 12; i++) {
          if (i == 4
              ? RegExp(r'^ма[йяюе]$').hasMatch(word)
              : word.startsWith(_months[i])) {
            month = i + 1;
          }
        }
        for (final e in seasons.entries) {
          if (word.startsWith(e.key)) month = e.value;
        }
        if (word.startsWith('год') || word == 'новому') month = 12;
        if (month != null) {
          var yy = year ?? today.year;
          if (year == null && month < today.month) yy++;
          found = DateTime(yy, month + 1, 0);
        }
      }
      if (found != null) {
        deadline = found;
        text = text.replaceRange(m.start, m.end, ' ');
        break;
      }
    }
    final later = RegExp(
      r'через (?:(\d+|[а-я]+) )?(года|год|лет|месяцев|месяца|месяц)(?= |$)',
    ).firstMatch(text);
    if (deadline == null && later != null) {
      final raw = later.group(1);
      final n = raw == null ? 1 : int.tryParse(raw) ?? _counts[raw] ?? 1;
      final months = later.group(2)!.startsWith('месяц') ? n : 12 * n;
      deadline = DateTime(today.year, today.month + months, today.day);
      text = text.replaceRange(later.start, later.end, ' ');
    }
    text = text.replaceAllMapped(
      RegExp(r'(коплю|копить|накопить|откладываю|отложить) на(?= |$)'),
      (m) => m.group(1)!,
    );
    final money = VoiceEntryParser.amountIn(text);
    var name = _name(heard, money?.rest ?? text, const {
      'я',
      'хочу',
      'хотел',
      'хотела',
      'бы',
      'мечтаю',
      'мечта',
      'мечту',
      'мечты',
      'о',
      'об',
      'цель',
      'цели',
      'коплю',
      'накопить',
      'копить',
      'откладываю',
      'купить',
      'приобрести',
      'за',
      'стоимостью',
      'стоит',
      'ценой',
      'примерно',
      'около',
      'добавь',
      'создай',
      'поставь',
      'запиши',
    }, accusative: true);
    // «Хочу на море» → «Поездка на море».
    if (RegExp(r'^(?:в|во|на) ').hasMatch(name.toLowerCase())) {
      name = 'Поездка ${name[0].toLowerCase()}${name.substring(1)}';
    }
    return CreateGoalCommand(
      heard,
      name: name.isEmpty ? 'Мечта' : name,
      targetMinor: money?.minor,
      deadline: deadline,
    );
  }

  static CreateRecurringCommand _recurring(
    String heard,
    String t,
    String? frequency,
    List<Category> categories,
    List<Account> accounts,
    DateTime today,
  ) {
    final words = t.split(' ');
    bool has(String stem) => words.any((w) => w.startsWith(stem));
    final kind =
        has('зарплат') ||
            has('доход') ||
            has('поступлен') ||
            has('стипенд') ||
            has('пенси') ||
            has('аванс')
        ? EntryKind.income
        : EntryKind.expense;
    final every = frequency ?? 'monthly';
    // «10 числа», «каждое 10 число».
    var text = t;
    int? day;
    final dayMatch = RegExp(
      r'(?:каждое |кажд\S* )?(\d{1,2})(?:-?го)? (?:числа|число)',
    ).firstMatch(text);
    if (dayMatch != null) {
      day = int.parse(dayMatch.group(1)!);
      text = text.replaceRange(dayMatch.start, dayMatch.end, ' ');
    }
    text = text.replaceAll(
      RegExp(
        r'ежемесячн\S*|ежегодн\S*|еженедельн\S*|ежедневн\S*|'
        r'(?:раз |каждый |каждую |каждого )?(?:в )?(?:месяц\S*|год|неделю|день)'
        r'(?= |$)',
      ),
      ' ',
    );
    final money = VoiceEntryParser.amountIn(text);
    final rest = money?.rest ?? text;
    final account = _match(
      rest.split(' '),
      accounts.where((a) => !a.archived).map((a) => (a.id, a.name)),
    );
    final restWords = rest.split(' ').where((w) => w.isNotEmpty).toList();
    // A known service among the words («яндекс плюс», «netflix»).
    SubscriptionService? service = ServiceRecognizer.find(rest);
    if (service != null && ServiceCatalog.banks.contains(service)) {
      service = null;
    }
    for (var n = restWords.length; n >= 1 && service == null; n--) {
      for (var i = 0; i + n <= restWords.length && service == null; i++) {
        final s = ServiceCatalog.byName(restWords.sublist(i, i + n).join(' '));
        if (s != null && !ServiceCatalog.banks.contains(s)) service = s;
      }
    }
    var name =
        service?.name ??
        _name(heard, rest, const {
          'добавь',
          'создай',
          'новую',
          'новый',
          'новая',
          'запиши',
          'поставь',
          'подписку',
          'подписка',
          'регулярный',
          'регулярную',
          'регулярно',
          'платеж',
          'платежа',
          'автоплатеж',
          'по',
          'за',
          'на',
          'с',
          'со',
          'раз',
          'каждый',
          'каждую',
          'числа',
          'число',
        });
    if (name.isEmpty) {
      name = kind == EntryKind.income ? 'Регулярный доход' : 'Подписка';
    }
    final subscription =
        kind == EntryKind.expense && (has('подписк') || service != null);
    String? category = VoiceEntryParser.categoryFor(
      _norm(name),
      kind,
      categories,
    );
    if (category == null && subscription) {
      category = categories
          .where(
            (c) =>
                !c.archived &&
                c.kind == EntryKind.expense &&
                _norm(c.name).startsWith('подписк'),
          )
          .firstOrNull
          ?.id;
    }
    DateTime next;
    if (day != null && day >= 1 && day <= 31) {
      final thisMonth = DateTime(today.year, today.month, day);
      next = thisMonth.isBefore(today)
          ? DateTime(today.year, today.month + 1, day)
          : thisMonth;
    } else {
      // Said on the day it was paid: the next payment is one period on.
      next = switch (every) {
        'daily' => DateTime(today.year, today.month, today.day + 1),
        'weekly' => DateTime(today.year, today.month, today.day + 7),
        'yearly' => DateTime(today.year + 1, today.month, today.day),
        _ => DateTime(today.year, today.month + 1, today.day),
      };
    }
    return CreateRecurringCommand(
      heard,
      name: name,
      amountMinor: money?.minor,
      kind: kind,
      frequency: every,
      paymentType: subscription ? 'subscription' : 'mandatory',
      serviceId: kind == EntryKind.expense ? service?.id : null,
      categoryId: category,
      accountId: account,
      nextDate: next,
    );
  }

  static const _prepositions = {'в', 'во', 'на', 'до', 'по', 'для', 'с', 'к'};

  /// What is left of [rest] after [drop] words, written as the person said
  /// it (case from [heard]). With [accusative], words before the first
  /// preposition go back to the nominative: «машину» → «машина», «новую
  /// квартиру» → «новая квартира».
  static String _name(
    String heard,
    String rest,
    Set<String> drop, {
    bool accusative = false,
  }) {
    final original = <String, String>{};
    for (final w in heard.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))) {
      if (w.isEmpty) continue;
      original.putIfAbsent(w.toLowerCase().replaceAll('ё', 'е'), () => w);
    }
    final words = _norm(rest)
        .split(' ')
        .where(
          (w) =>
              w.isNotEmpty &&
              !drop.contains(w) &&
              !(_createVerbs.contains(w) &&
                  !(accusative && w.startsWith('нов'))),
        )
        .where((w) => !RegExp(r'^\d+$').hasMatch(w))
        .toList();
    // Leading prepositions left over («на телефон» after «копить»).
    if (!accusative) {
      while (words.isNotEmpty && _prepositions.contains(words.first)) {
        words.removeAt(0);
      }
    }
    final out = <String>[];
    var nominative = accusative;
    for (final w in words) {
      if (_prepositions.contains(w) && out.isNotEmpty) nominative = false;
      if (out.isEmpty && _prepositions.contains(w)) {
        // «Хочу на море»: kept for «Поездка на море».
        out.add(w);
        nominative = false;
        continue;
      }
      var word = original[w] ?? w;
      if (nominative && word.length > 3) {
        final lower = word.toLowerCase();
        if (lower.endsWith('ую')) {
          word = '${word.substring(0, word.length - 2)}ая';
        } else if (lower.endsWith('юю')) {
          word = '${word.substring(0, word.length - 2)}яя';
        } else if (lower.endsWith('у')) {
          word = '${word.substring(0, word.length - 1)}а';
        } else if (lower.endsWith('ю')) {
          word = '${word.substring(0, word.length - 1)}я';
        }
      }
      out.add(word);
    }
    final name = out.join(' ').trim();
    return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
  }

  // ── Lists and screens ─────────────────────────────────────────────────

  static VoiceCommand _show(
    String heard,
    String t,
    List<Category> categories,
    List<Account> accounts,
    DateTime today,
    int weekStart,
  ) {
    final words = t.split(' ');
    bool has(String stem) => words.any((w) => w.startsWith(stem));
    OpenScreenCommand open(VoiceScreen s) => OpenScreenCommand(heard, s);

    // Screens that are not lists of operations come first: «покажи
    // аналитику за июнь» opens analytics.
    if (has('аналити') || has('статисти') || has('отчет') || has('диаграм')) {
      return open(VoiceScreen.analytics);
    }
    if (has('настро') || has('параметр')) return open(VoiceScreen.settings);
    if (has('бюджет') || has('лимит')) return open(VoiceScreen.budgets);
    if (has('календар')) return open(VoiceScreen.calendar);
    if (has('категори')) return open(VoiceScreen.categories);
    if (has('подписк') || has('регулярн') || has('повторя')) {
      return open(VoiceScreen.recurring);
    }
    if (has('автоплат')) return open(VoiceScreen.recurring);
    if (has('участник') ||
        words.any((w) => RegExp(r'^семь[яиюе]').hasMatch(w))) {
      return open(VoiceScreen.members);
    }
    if (has('главн') || words.contains('домой') || has('домашн')) {
      return open(VoiceScreen.home);
    }
    if (has('цел') || has('мечт') || has('копилк') || has('накоплен')) {
      return open(VoiceScreen.goals);
    }
    if (has('перенос') || has('импорт')) {
      return open(VoiceScreen.importAccounts);
    }

    EntryKind? kind;
    if (has('расход') || has('трат') || has('потрат') || has('затрат')) {
      kind = EntryKind.expense;
    } else if (has('доход') ||
        has('заработ') ||
        has('поступлен') ||
        has('получил')) {
      kind = EntryKind.income;
    } else if (has('перевод')) {
      kind = EntryKind.transfer;
    }
    final allTime =
        t.contains('все время') ||
        t.contains('всю историю') ||
        t.contains('за всегда');
    final period = allTime ? null : _period(t, today, weekStart);
    final category = _match(
      words,
      categories
          .where((c) => !c.archived && (kind == null || c.kind == kind))
          .map((c) => (c.id, c.name)),
    );
    final account = _match(
      words,
      accounts.where((a) => !a.archived).map((a) => (a.id, a.name)),
    );
    if (category != null && kind == null) {
      kind = categories.firstWhere((c) => c.id == category).kind;
    }

    if (kind != null || period != null || category != null || allTime) {
      final what = switch (kind) {
        EntryKind.expense => 'Расходы',
        EntryKind.income => 'Доходы',
        EntryKind.transfer => 'Переводы',
        null => 'Операции',
      };
      final ({DateTime? start, DateTime? end, String? label}) p = allTime
          ? (start: null, end: null, label: 'всё время')
          : period ??
                // Without a period: this month, like the main screen.
                (
                  start: DateTime(today.year, today.month),
                  end: DateTime(today.year, today.month + 1, 0),
                  label: 'этот месяц',
                );
      final name = category == null
          ? null
          : categories.firstWhere((c) => c.id == category).name;
      return ShowEntriesCommand(
        heard,
        kind: kind,
        start: p.start,
        end: p.end,
        categoryId: category,
        accountId: account,
        title: [what, ?name, ?p.label].join(' · '),
      );
    }
    if (account != null) {
      final name = accounts.firstWhere((a) => a.id == account).name;
      return ShowEntriesCommand(
        heard,
        accountId: account,
        title: 'Операции · $name',
      );
    }
    if (has('операци') || has('истори') || has('транзакц')) {
      return open(VoiceScreen.operations);
    }
    if (has('счет') || has('счета') || has('карт') || has('кошел')) {
      return open(VoiceScreen.accounts);
    }
    if (has('начальн') || has('баланс')) {
      return open(VoiceScreen.home);
    }
    if (has('меню') || words.contains('еще')) return open(VoiceScreen.more);
    return UnknownCommand(heard);
  }

  /// Words too common to name a category or an account.
  static const _common = {
    'карта',
    'карты',
    'счет',
    'счета',
    'основной',
    'основная',
    'кредитная',
    'дебетовая',
    'другое',
    'прочее',
    'прочие',
    'разное',
    'расходы',
    'доходы',
    'покупки',
    'платежи',
    'перевод',
    'переводы',
    'мой',
    'моя',
  };

  /// The id whose name shares a word stem with the phrase.
  static String? _match(List<String> words, Iterable<(String, String)> items) {
    String? best;
    var bestLength = 0;
    for (final (id, name) in items) {
      for (final w in _norm(name).split(' ')) {
        if (w.length < 3 || _common.contains(w)) continue;
        final stem = w.length <= 4
            ? w
            : w.substring(0, w.length - (w.length > 6 ? 2 : 1));
        if (words.any((x) => x.startsWith(stem)) && stem.length > bestLength) {
          best = id;
          bestLength = stem.length;
        }
      }
    }
    return best;
  }

  // ── Periods ───────────────────────────────────────────────────────────

  static const _months = [
    'январ',
    'феврал',
    'март',
    'апрел',
    'ма',
    'июн',
    'июл',
    'август',
    'сентябр',
    'октябр',
    'ноябр',
    'декабр',
  ];
  static const _monthNames = [
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ];
  static const _counts = {
    'один': 1,
    'одну': 1,
    'два': 2,
    'две': 2,
    'пару': 2,
    'три': 3,
    'четыре': 4,
    'пять': 5,
    'шесть': 6,
    'семь': 7,
    'восемь': 8,
    'девять': 9,
    'десять': 10,
    'одиннадцать': 11,
    'двенадцать': 12,
  };

  static ({DateTime start, DateTime end, String? label})? _period(
    String t,
    DateTime today,
    int weekStart,
  ) {
    final words = t.split(' ');
    bool has(String stem) => words.any((w) => w.startsWith(stem));
    final last = has('прошл') || has('предыдущ');
    final y = today.year, m = today.month;

    if (has('позавчера')) {
      final d = DateTime(y, m, today.day - 2);
      return (start: d, end: d, label: 'позавчера');
    }
    if (has('вчера')) {
      final d = DateTime(y, m, today.day - 1);
      return (start: d, end: d, label: 'вчера');
    }
    if (has('сегодня')) return (start: today, end: today, label: 'сегодня');

    // «За последние 3 месяца», «за последнюю неделю».
    final recent = RegExp(
      r'последн\S* (?:(\d+|[а-я]+) )?(дн|день|недел|месяц|год|лет)',
    ).firstMatch(t);
    if (recent != null) {
      final raw = recent.group(1);
      final n = raw == null ? 1 : int.tryParse(raw) ?? _counts[raw] ?? 1;
      final unit = recent.group(2)!;
      final start = switch (unit) {
        'дн' || 'день' => DateTime(y, m, today.day - n + 1),
        'недел' => DateTime(y, m, today.day - 7 * n + 1),
        'месяц' => DateTime(y, m - n, today.day + 1),
        _ => DateTime(y - n, m, today.day + 1),
      };
      final what = switch (unit) {
        'дн' || 'день' => 'дн.',
        'недел' => 'нед.',
        'месяц' => 'мес.',
        _ => n == 1 ? 'год' : 'г.',
      };
      return (start: start, end: today, label: 'последние $n $what');
    }

    final yearMatch = RegExp(
      r'(?<![а-яa-z0-9])(20\d\d)(?![а-яa-z0-9])',
    ).firstMatch(t);
    final year = yearMatch == null ? null : int.parse(yearMatch.group(1)!);

    // A month by name, with a year or the latest one that has begun.
    for (var i = 0; i < 12; i++) {
      final stem = _months[i];
      final hit = i == 4
          ? words.any((w) => RegExp(r'^ма[йяе]$').hasMatch(w))
          : has(stem);
      if (!hit) continue;
      final month = i + 1;
      final yy = year ?? (month > m ? y - 1 : y);
      return (
        start: DateTime(yy, month),
        end: DateTime(yy, month + 1, 0),
        label: '${_monthNames[i]} $yy',
      );
    }
    if (year != null) {
      return (
        start: DateTime(year),
        end: DateTime(year, 12, 31),
        label: '$year год',
      );
    }
    if (has('недел')) {
      final shift = (today.weekday - weekStart) % 7;
      final start = DateTime(y, m, today.day - shift - (last ? 7 : 0));
      return (
        start: start,
        end: DateTime(start.year, start.month, start.day + 6),
        label: last ? 'прошлая неделя' : 'эта неделя',
      );
    }
    if (has('месяц') || has('месяч')) {
      final mm = last ? m - 1 : m;
      final start = DateTime(y, mm);
      return (
        start: start,
        end: DateTime(start.year, start.month + 1, 0),
        label: last ? 'прошлый месяц' : 'этот месяц',
      );
    }
    if (has('год') || has('году') || has('годов')) {
      final yy = last ? y - 1 : y;
      return (start: DateTime(yy), end: DateTime(yy, 12, 31), label: '$yy год');
    }
    return null;
  }
}
