// Domain models contain no Flutter or persistence dependencies.
// Amounts are minor currency units (kopecks/cents), never floating point.
enum EntryKind { expense, income, transfer }

const _absent = Object();

class Account {
  final String id;
  final String name;
  final String type;
  final String currency;
  final String bank;
  final String lastFour;
  final int openingMinor;
  final int creditLimitMinor;
  final bool excluded;
  final bool archived;
  final int color;
  final int icon;

  const Account({
    required this.id,
    required this.name,
    this.type = 'bank',
    this.currency = 'RUB',
    this.bank = '',
    this.lastFour = '',
    this.openingMinor = 0,
    this.creditLimitMinor = 0,
    this.excluded = false,
    this.archived = false,
    this.color = 0xffc9f36f,
    this.icon = 0,
  });

  Account copyWith({
    String? id,
    String? name,
    String? type,
    String? currency,
    String? bank,
    String? lastFour,
    int? openingMinor,
    int? creditLimitMinor,
    bool? excluded,
    bool? archived,
    int? color,
    int? icon,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    bank: bank ?? this.bank,
    lastFour: lastFour ?? this.lastFour,
    openingMinor: openingMinor ?? this.openingMinor,
    creditLimitMinor: creditLimitMinor ?? this.creditLimitMinor,
    excluded: excluded ?? this.excluded,
    archived: archived ?? this.archived,
    color: color ?? this.color,
    icon: icon ?? this.icon,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'currency': currency,
    'bank': bank,
    'lastFour': lastFour,
    'openingMinor': openingMinor,
    'creditLimitMinor': creditLimitMinor,
    'excluded': excluded,
    'archived': archived,
    'color': color,
    'icon': icon,
  };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    name: json['name'] as String,
    type: json['type'] as String? ?? 'bank',
    currency: json['currency'] as String? ?? 'RUB',
    bank: json['bank'] as String? ?? '',
    lastFour: json['lastFour'] as String? ?? '',
    openingMinor: json['openingMinor'] as int? ?? 0,
    creditLimitMinor: json['creditLimitMinor'] as int? ?? 0,
    excluded: json['excluded'] as bool? ?? false,
    archived: json['archived'] as bool? ?? false,
    color: json['color'] as int? ?? 0xffc9f36f,
    icon: json['icon'] as int? ?? 0,
  );
}

class Category {
  final String id;
  final String name;
  final EntryKind kind;
  final int color;
  final int background;
  final int icon;
  final int order;
  final bool archived;
  final List<String> subcategories;

  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.color = 0xffc9f36f,
    this.background = 0xff273326,
    this.icon = 0,
    this.order = 0,
    this.archived = false,
    this.subcategories = const [],
  });

  Category copyWith({
    String? id,
    String? name,
    EntryKind? kind,
    int? color,
    int? background,
    int? icon,
    int? order,
    bool? archived,
    List<String>? subcategories,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    color: color ?? this.color,
    background: background ?? this.background,
    icon: icon ?? this.icon,
    order: order ?? this.order,
    archived: archived ?? this.archived,
    subcategories: subcategories ?? this.subcategories,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'color': color,
    'background': background,
    'icon': icon,
    'order': order,
    'archived': archived,
    'subcategories': subcategories,
  };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: EntryKind.values.byName(json['kind'] as String),
    color: json['color'] as int? ?? 0xffc9f36f,
    background: json['background'] as int? ?? 0xff273326,
    icon: json['icon'] as int? ?? 0,
    order: json['order'] as int? ?? 0,
    archived: json['archived'] as bool? ?? false,
    subcategories: (json['subcategories'] as List<dynamic>? ?? const [])
        .cast<String>(),
  );
}

class FinanceEntry {
  final String id;
  final EntryKind kind;
  final int amountMinor;
  final String currency;
  final String accountId;
  final String? toAccountId;
  final String? toGoalId;
  final String? categoryId;
  final String? subcategory;
  final String? attachmentPath;
  final String? serviceId;
  final String? serviceIconPath;
  final int? destinationMinor;
  final DateTime date;
  final String note;
  final String payee;
  final String status;
  final String recurrence;
  final String memberId;
  final List<String> tags;
  final double? latitude;
  final double? longitude;

  const FinanceEntry({
    required this.id,
    required this.kind,
    required this.amountMinor,
    required this.currency,
    required this.accountId,
    this.toAccountId,
    this.toGoalId,
    this.categoryId,
    this.subcategory,
    this.attachmentPath,
    this.serviceId,
    this.serviceIconPath,
    this.destinationMinor,
    required this.date,
    this.note = '',
    this.payee = '',
    this.status = 'posted',
    this.recurrence = 'none',
    this.memberId = 'me',
    this.tags = const [],
    this.latitude,
    this.longitude,
  });

  FinanceEntry copyWith({
    String? id,
    EntryKind? kind,
    int? amountMinor,
    String? currency,
    String? accountId,
    Object? toAccountId = _absent,
    Object? toGoalId = _absent,
    Object? categoryId = _absent,
    Object? subcategory = _absent,
    Object? attachmentPath = _absent,
    Object? serviceId = _absent,
    Object? serviceIconPath = _absent,
    Object? destinationMinor = _absent,
    DateTime? date,
    String? note,
    String? payee,
    String? status,
    String? recurrence,
    String? memberId,
    List<String>? tags,
    Object? latitude = _absent,
    Object? longitude = _absent,
  }) => FinanceEntry(
    id: id ?? this.id,
    serviceIconPath: identical(serviceIconPath, _absent)
        ? this.serviceIconPath
        : serviceIconPath as String?,
    serviceId: identical(serviceId, _absent)
        ? this.serviceId
        : serviceId as String?,
    kind: kind ?? this.kind,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    accountId: accountId ?? this.accountId,
    toAccountId: identical(toAccountId, _absent)
        ? this.toAccountId
        : toAccountId as String?,
    toGoalId: identical(toGoalId, _absent)
        ? this.toGoalId
        : toGoalId as String?,
    categoryId: identical(categoryId, _absent)
        ? this.categoryId
        : categoryId as String?,
    subcategory: identical(subcategory, _absent)
        ? this.subcategory
        : subcategory as String?,
    attachmentPath: identical(attachmentPath, _absent)
        ? this.attachmentPath
        : attachmentPath as String?,
    destinationMinor: identical(destinationMinor, _absent)
        ? this.destinationMinor
        : destinationMinor as int?,
    date: date ?? this.date,
    note: note ?? this.note,
    payee: payee ?? this.payee,
    status: status ?? this.status,
    recurrence: recurrence ?? this.recurrence,
    memberId: memberId ?? this.memberId,
    tags: tags ?? this.tags,
    latitude: identical(latitude, _absent)
        ? this.latitude
        : latitude as double?,
    longitude: identical(longitude, _absent)
        ? this.longitude
        : longitude as double?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'amountMinor': amountMinor,
    'currency': currency,
    'accountId': accountId,
    'toAccountId': toAccountId,
    'toGoalId': toGoalId,
    'categoryId': categoryId,
    'subcategory': subcategory,
    'attachmentPath': attachmentPath,
    'serviceId': serviceId,
    'serviceIconPath': serviceIconPath,
    'destinationMinor': destinationMinor,
    'date': date.toIso8601String(),
    'note': note,
    'payee': payee,
    'status': status,
    'recurrence': recurrence,
    'memberId': memberId,
    'tags': tags,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory FinanceEntry.fromJson(Map<String, dynamic> json) => FinanceEntry(
    id: json['id'] as String,
    kind: EntryKind.values.byName(json['kind'] as String),
    amountMinor: json['amountMinor'] as int,
    currency: json['currency'] as String,
    accountId: json['accountId'] as String,
    toAccountId: json['toAccountId'] as String?,
    toGoalId: json['toGoalId'] as String?,
    categoryId: json['categoryId'] as String?,
    subcategory: json['subcategory'] as String?,
    attachmentPath: json['attachmentPath'] as String?,
    serviceId: json['serviceId'] as String?,
    serviceIconPath: json['serviceIconPath'] as String?,
    destinationMinor: json['destinationMinor'] as int?,
    date: DateTime.parse(json['date'] as String),
    note: json['note'] as String? ?? '',
    payee: json['payee'] as String? ?? '',
    status: json['status'] as String? ?? 'posted',
    recurrence: json['recurrence'] as String? ?? 'none',
    memberId: json['memberId'] as String? ?? 'me',
    tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );
}

class Budget {
  final String id;
  final String name;
  final String currency;
  final String? categoryId;
  final int limitMinor;

  const Budget({
    required this.id,
    required this.name,
    this.currency = 'RUB',
    this.categoryId,
    required this.limitMinor,
  });

  Budget copyWith({
    String? id,
    String? name,
    String? currency,
    Object? categoryId = _absent,
    int? limitMinor,
  }) => Budget(
    id: id ?? this.id,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    categoryId: identical(categoryId, _absent)
        ? this.categoryId
        : categoryId as String?,
    limitMinor: limitMinor ?? this.limitMinor,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'currency': currency,
    'categoryId': categoryId,
    'limitMinor': limitMinor,
  };

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
    id: json['id'] as String,
    name: json['name'] as String,
    currency: json['currency'] as String? ?? 'RUB',
    categoryId: json['categoryId'] as String?,
    limitMinor: json['limitMinor'] as int,
  );
}

class Goal {
  final String id;
  final String name;
  final String currency;
  final int targetMinor;
  final int savedMinor;
  final int color;
  final int icon;
  final DateTime? deadline;

  const Goal({
    required this.id,
    required this.name,
    this.currency = 'RUB',
    required this.targetMinor,
    this.savedMinor = 0,
    this.color = 0xffc9f36f,
    this.icon = 0,
    this.deadline,
  });

  Goal copyWith({
    String? id,
    String? name,
    String? currency,
    int? targetMinor,
    int? savedMinor,
    int? color,
    int? icon,
    Object? deadline = _absent,
  }) => Goal(
    id: id ?? this.id,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    targetMinor: targetMinor ?? this.targetMinor,
    savedMinor: savedMinor ?? this.savedMinor,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    deadline: identical(deadline, _absent)
        ? this.deadline
        : deadline as DateTime?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'currency': currency,
    'targetMinor': targetMinor,
    'savedMinor': savedMinor,
    'color': color,
    'icon': icon,
    'deadline': deadline?.toIso8601String(),
  };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String,
    name: json['name'] as String,
    currency: json['currency'] as String? ?? 'RUB',
    targetMinor: json['targetMinor'] as int,
    savedMinor: json['savedMinor'] as int? ?? 0,
    color: json['color'] as int? ?? 0xffc9f36f,
    icon: json['icon'] as int? ?? 0,
    deadline: json['deadline'] == null
        ? null
        : DateTime.parse(json['deadline'] as String),
  );
}

class RecurringRule {
  final String id;
  final String name;
  final String accountId;
  final String currency;
  final String? categoryId;
  final String? serviceId;
  final String? customIconPath;
  final EntryKind kind;
  final int amountMinor;
  final int interval;
  final String frequency;
  final String paymentType;
  final DateTime nextDate;

  /// Intended day of month, retained when February clamps the next date.
  final int anchorDay;
  final bool automatic;
  final bool reminderEnabled;
  final int reminderDaysBefore;
  final int reminderHour;
  final int reminderMinute;
  final bool enabled;

  RecurringRule({
    required this.id,
    required this.name,
    required this.accountId,
    this.currency = 'RUB',
    this.categoryId,
    this.serviceId,
    this.customIconPath,
    this.kind = EntryKind.expense,
    required this.amountMinor,
    this.interval = 1,
    this.frequency = 'monthly',
    this.paymentType = 'mandatory',
    required this.nextDate,
    int? anchorDay,
    this.automatic = false,
    this.reminderEnabled = false,
    this.reminderDaysBefore = 1,
    this.reminderHour = 10,
    this.reminderMinute = 0,
    this.enabled = true,
  }) : anchorDay = anchorDay ?? nextDate.day;

  RecurringRule copyWith({
    String? id,
    String? name,
    String? accountId,
    String? currency,
    Object? categoryId = _absent,
    Object? serviceId = _absent,
    Object? customIconPath = _absent,
    EntryKind? kind,
    int? amountMinor,
    int? interval,
    String? frequency,
    String? paymentType,
    DateTime? nextDate,
    int? anchorDay,
    bool? automatic,
    bool? reminderEnabled,
    int? reminderDaysBefore,
    int? reminderHour,
    int? reminderMinute,
    bool? enabled,
  }) => RecurringRule(
    id: id ?? this.id,
    customIconPath: identical(customIconPath, _absent)
        ? this.customIconPath
        : customIconPath as String?,
    serviceId: identical(serviceId, _absent)
        ? this.serviceId
        : serviceId as String?,
    name: name ?? this.name,
    accountId: accountId ?? this.accountId,
    currency: currency ?? this.currency,
    categoryId: identical(categoryId, _absent)
        ? this.categoryId
        : categoryId as String?,
    kind: kind ?? this.kind,
    amountMinor: amountMinor ?? this.amountMinor,
    interval: interval ?? this.interval,
    frequency: frequency ?? this.frequency,
    paymentType: paymentType ?? this.paymentType,
    nextDate: nextDate ?? this.nextDate,
    anchorDay: anchorDay ?? this.anchorDay,
    automatic: automatic ?? this.automatic,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'accountId': accountId,
    'currency': currency,
    'categoryId': categoryId,
    'serviceId': serviceId,
    'customIconPath': customIconPath,
    'kind': kind.name,
    'amountMinor': amountMinor,
    'interval': interval,
    'frequency': frequency,
    'paymentType': paymentType,
    'nextDate': nextDate.toIso8601String(),
    'anchorDay': anchorDay,
    'automatic': automatic,
    'reminderEnabled': reminderEnabled,
    'reminderDaysBefore': reminderDaysBefore,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'enabled': enabled,
  };

  /// Conservative migration of the old unclassified regular-payment list.
  /// Utilities, loans and all unrecognized names remain mandatory payments.
  static String classifyLegacyPaymentType(
    String name, [
    String categoryName = '',
  ]) {
    final text = '$name $categoryName'.toLowerCase();
    return RegExp(
          r'подпис|netflix|spotify|музык|youtube|яндекс плюс|yandex plus|icloud|subscription',
        ).hasMatch(text)
        ? 'subscription'
        : 'mandatory';
  }

  factory RecurringRule.fromJson(Map<String, dynamic> json) => RecurringRule(
    id: json['id'] as String,
    name: json['name'] as String,
    accountId: json['accountId'] as String,
    currency: json['currency'] as String? ?? 'RUB',
    categoryId: json['categoryId'] as String?,
    serviceId: json['serviceId'] as String?,
    customIconPath: json['customIconPath'] as String?,
    kind: EntryKind.values.byName(
      json['kind'] as String? ?? EntryKind.expense.name,
    ),
    amountMinor: json['amountMinor'] as int,
    interval: json['interval'] as int? ?? 1,
    frequency: json['frequency'] as String? ?? 'monthly',
    paymentType:
        json['paymentType'] as String? ??
        classifyLegacyPaymentType(json['name'] as String),
    nextDate: DateTime.parse(json['nextDate'] as String),
    anchorDay: json['anchorDay'] as int?,
    automatic: json['automatic'] as bool? ?? false,
    reminderEnabled: json['reminderEnabled'] as bool? ?? false,
    reminderDaysBefore: json['reminderDaysBefore'] as int? ?? 1,
    reminderHour: json['reminderHour'] as int? ?? 10,
    reminderMinute: json['reminderMinute'] as int? ?? 0,
    enabled: json['enabled'] as bool? ?? true,
  );
}

class Member {
  final String id;
  final String name;

  const Member({required this.id, required this.name});

  Member copyWith({String? id, String? name}) =>
      Member(id: id ?? this.id, name: name ?? this.name);

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory Member.fromJson(Map<String, dynamic> json) =>
      Member(id: json['id'] as String, name: json['name'] as String);
}

class AppPreferences {
  final String theme;
  final String accent;
  final String baseCurrency;
  final String numberFormat;
  final String dateFormat;
  final int weekStart;
  final int monthStart;
  final int lockMinutes;
  final String? lastExpenseCategoryId;
  final String? lastIncomeCategoryId;
  final bool notifications;

  /// Order the person dragged things into (1.14): main screen blocks,
  /// accounts and goals, as ids. Empty means the default order; ids that no
  /// longer exist are ignored and new ones go last.
  final List<String> dashboardOrder;
  final List<String> accountOrder;
  final List<String> goalOrder;

  /// The person's name from the welcome screens (1.21); empty if skipped.
  final String userName;

  /// Whether the welcome screens were completed. Settings saved by earlier
  /// versions have no such field and count as completed; only a brand-new
  /// install starts with false.
  final bool onboarded;

  /// Accounts that show their bank's logo (1.22.1). Off by default: the
  /// person turns it on per account in the account editor.
  final List<String> bankLogos;

  /// Finora 1.27: a light tap under the finger (on by default), Finora
  /// waking on her name (off until the person turns it on and allows the
  /// microphone) and her controls in the notification shade (off).
  final bool haptics;
  final bool wakeWord;
  final bool shadeControls;

  /// 1.28: the money tips card on the main screen (can be swiped away).
  final bool tips;

  /// 1.28: the currency the header and month tiles are shown in ('' — the
  /// base currency) and the person's own rates: rubles per one unit.
  final String displayCurrency;
  final Map<String, double> rates;

  /// 1.28: the app language, 'ru' or 'en'.
  final String language;

  /// Rough starting rates (rubles per unit). Finora never goes online, so the
  /// person corrects them in the currency sheet.
  static const defaultRates = <String, double>{
    'RUB': 1,
    'USD': 90,
    'EUR': 98,
    'CNY': 12.5,
    'TRY': 2.3,
    'GEL': 33,
    'GBP': 115,
    'AED': 24.5,
    'KZT': .18,
    'CHF': 102,
  };

  /// Rubles per one unit of [currency].
  double rubles(String currency) =>
      rates[currency] ?? defaultRates[currency] ?? 1;

  /// [minor] of the base currency in the display currency (minor units).
  int toDisplay(int minor) {
    final to = displayCurrency.isEmpty ? baseCurrency : displayCurrency;
    if (to == baseCurrency) return minor;
    return (minor * rubles(baseCurrency) / rubles(to)).round();
  }

  String get shownCurrency =>
      displayCurrency.isEmpty ? baseCurrency : displayCurrency;

  const AppPreferences({
    this.theme = 'dark',
    this.accent = 'coffee',
    this.baseCurrency = 'RUB',
    this.numberFormat = 'space_comma',
    this.dateFormat = 'dd.MM.yyyy',
    this.weekStart = 1,
    this.monthStart = 1,
    this.lockMinutes = 5,
    this.lastExpenseCategoryId,
    this.lastIncomeCategoryId,
    this.notifications = false,
    this.dashboardOrder = const [],
    this.accountOrder = const [],
    this.goalOrder = const [],
    this.userName = '',
    this.onboarded = true,
    this.bankLogos = const [],
    this.haptics = true,
    this.wakeWord = false,
    this.shadeControls = false,
    this.tips = true,
    this.displayCurrency = '',
    this.rates = const {},
    this.language = 'ru',
  });

  AppPreferences copyWith({
    String? theme,
    String? accent,
    String? baseCurrency,
    String? numberFormat,
    String? dateFormat,
    int? weekStart,
    int? monthStart,
    int? lockMinutes,
    Object? lastExpenseCategoryId = _absent,
    Object? lastIncomeCategoryId = _absent,
    bool? notifications,
    List<String>? dashboardOrder,
    List<String>? accountOrder,
    List<String>? goalOrder,
    String? userName,
    bool? onboarded,
    List<String>? bankLogos,
    bool? haptics,
    bool? wakeWord,
    bool? shadeControls,
    bool? tips,
    String? displayCurrency,
    Map<String, double>? rates,
    String? language,
  }) => AppPreferences(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    numberFormat: numberFormat ?? this.numberFormat,
    dateFormat: dateFormat ?? this.dateFormat,
    weekStart: weekStart ?? this.weekStart,
    monthStart: monthStart ?? this.monthStart,
    lockMinutes: lockMinutes ?? this.lockMinutes,
    lastExpenseCategoryId: identical(lastExpenseCategoryId, _absent)
        ? this.lastExpenseCategoryId
        : lastExpenseCategoryId as String?,
    lastIncomeCategoryId: identical(lastIncomeCategoryId, _absent)
        ? this.lastIncomeCategoryId
        : lastIncomeCategoryId as String?,
    notifications: notifications ?? this.notifications,
    dashboardOrder: dashboardOrder ?? this.dashboardOrder,
    accountOrder: accountOrder ?? this.accountOrder,
    goalOrder: goalOrder ?? this.goalOrder,
    userName: userName ?? this.userName,
    onboarded: onboarded ?? this.onboarded,
    bankLogos: bankLogos ?? this.bankLogos,
    haptics: haptics ?? this.haptics,
    wakeWord: wakeWord ?? this.wakeWord,
    shadeControls: shadeControls ?? this.shadeControls,
    tips: tips ?? this.tips,
    displayCurrency: displayCurrency ?? this.displayCurrency,
    rates: rates ?? this.rates,
    language: language ?? this.language,
  );

  Map<String, Object?> toJson() => {
    'theme': theme,
    'accent': accent,
    'baseCurrency': baseCurrency,
    'numberFormat': numberFormat,
    'dateFormat': dateFormat,
    'weekStart': weekStart,
    'monthStart': monthStart,
    'lockMinutes': lockMinutes,
    'lastExpenseCategoryId': lastExpenseCategoryId,
    'lastIncomeCategoryId': lastIncomeCategoryId,
    'notifications': notifications,
    'dashboardOrder': dashboardOrder,
    'accountOrder': accountOrder,
    'goalOrder': goalOrder,
    'userName': userName,
    'onboarded': onboarded,
    'bankLogos': bankLogos,
    'haptics': haptics,
    'wakeWord': wakeWord,
    'shadeControls': shadeControls,
    'tips': tips,
    'displayCurrency': displayCurrency,
    'rates': rates,
    'language': language,
  };

  static List<String> _ids(Object? value) =>
      value is List ? List.unmodifiable(value.whereType<String>()) : const [];

  factory AppPreferences.fromJson(Map<String, dynamic> json) => AppPreferences(
    theme: json['theme'] as String? ?? 'dark',
    accent: json['accent'] as String? ?? 'coffee',
    baseCurrency: json['baseCurrency'] as String? ?? 'RUB',
    numberFormat: json['numberFormat'] as String? ?? 'space_comma',
    dateFormat: json['dateFormat'] as String? ?? 'dd.MM.yyyy',
    weekStart: json['weekStart'] as int? ?? 1,
    monthStart: json['monthStart'] as int? ?? 1,
    lockMinutes: json['lockMinutes'] as int? ?? 5,
    lastExpenseCategoryId: json['lastExpenseCategoryId'] as String?,
    lastIncomeCategoryId: json['lastIncomeCategoryId'] as String?,
    notifications: json['notifications'] as bool? ?? false,
    dashboardOrder: _ids(json['dashboardOrder']),
    accountOrder: _ids(json['accountOrder']),
    goalOrder: _ids(json['goalOrder']),
    userName: json['userName'] as String? ?? '',
    onboarded: json['onboarded'] as bool? ?? true,
    bankLogos: _ids(json['bankLogos']),
    haptics: json['haptics'] as bool? ?? true,
    wakeWord: json['wakeWord'] as bool? ?? false,
    shadeControls: json['shadeControls'] as bool? ?? false,
    tips: json['tips'] as bool? ?? true,
    displayCurrency: json['displayCurrency'] as String? ?? '',
    language: json['language'] as String? ?? 'ru',
    rates: {
      if (json['rates'] is Map)
        for (final e in (json['rates'] as Map).entries)
          if (e.key is String && e.value is num && (e.value as num) > 0)
            e.key as String: (e.value as num).toDouble(),
    },
  );

  /// [items] in the person's [order] (by [id]); unknown items keep their
  /// relative order after the known ones.
  static List<T> arrange<T>(
    List<T> items,
    List<String> order,
    String Function(T) id,
  ) {
    final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    indexed.sort((a, b) {
      final ra = rank[id(a.$2)] ?? order.length + a.$1;
      final rb = rank[id(b.$2)] ?? order.length + b.$1;
      return ra.compareTo(rb);
    });
    return [for (final item in indexed) item.$2];
  }
}

class FinanceData {
  final List<Account> accounts;
  final List<Category> categories;
  final List<FinanceEntry> entries;
  final List<Budget> budgets;
  final List<Goal> goals;
  final List<RecurringRule> recurring;
  final List<Member> members;
  final AppPreferences preferences;
  final bool demo;

  const FinanceData({
    this.accounts = const [],
    this.categories = const [],
    this.entries = const [],
    this.budgets = const [],
    this.goals = const [],
    this.recurring = const [],
    this.members = const [],
    this.preferences = const AppPreferences(),
    this.demo = false,
  });

  factory FinanceData.empty() => const FinanceData();

  FinanceData copyWith({
    List<Account>? accounts,
    List<Category>? categories,
    List<FinanceEntry>? entries,
    List<Budget>? budgets,
    List<Goal>? goals,
    List<RecurringRule>? recurring,
    List<Member>? members,
    AppPreferences? preferences,
    bool? demo,
  }) => FinanceData(
    accounts: accounts ?? this.accounts,
    categories: categories ?? this.categories,
    entries: entries ?? this.entries,
    budgets: budgets ?? this.budgets,
    goals: goals ?? this.goals,
    recurring: recurring ?? this.recurring,
    members: members ?? this.members,
    preferences: preferences ?? this.preferences,
    demo: demo ?? this.demo,
  );

  Map<String, Object?> toJson() => {
    'accounts': accounts.map((item) => item.toJson()).toList(),
    'categories': categories.map((item) => item.toJson()).toList(),
    'entries': entries.map((item) => item.toJson()).toList(),
    'budgets': budgets.map((item) => item.toJson()).toList(),
    'goals': goals.map((item) => item.toJson()).toList(),
    'recurring': recurring.map((item) => item.toJson()).toList(),
    'members': members.map((item) => item.toJson()).toList(),
    'preferences': preferences.toJson(),
    'demo': demo,
  };

  factory FinanceData.fromJson(Map<String, dynamic> json) => FinanceData(
    accounts: (json['accounts'] as List<dynamic>? ?? const [])
        .map((item) => Account.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(),
    categories: (json['categories'] as List<dynamic>? ?? const [])
        .map(
          (item) => Category.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    entries: (json['entries'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              FinanceEntry.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    budgets: (json['budgets'] as List<dynamic>? ?? const [])
        .map((item) => Budget.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(),
    goals: (json['goals'] as List<dynamic>? ?? const [])
        .map((item) => Goal.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(),
    recurring: (json['recurring'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              RecurringRule.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    members: (json['members'] as List<dynamic>? ?? const [])
        .map((item) => Member.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(),
    preferences: json['preferences'] == null
        ? const AppPreferences()
        : AppPreferences.fromJson(
            Map<String, dynamic>.from(json['preferences'] as Map),
          ),
    demo: json['demo'] as bool? ?? false,
  );
}
