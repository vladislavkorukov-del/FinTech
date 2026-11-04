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
  final List<String> subcategories;

  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.color = 0xffc9f36f,
    this.background = 0xff273326,
    this.icon = 0,
    this.order = 0,
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
    List<String>? subcategories,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    color: color ?? this.color,
    background: background ?? this.background,
    icon: icon ?? this.icon,
    order: order ?? this.order,
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
  final EntryKind kind;
  final int amountMinor;
  final int interval;
  final String frequency;
  final String paymentType;
  final DateTime nextDate;

  /// Intended day of month, retained when February clamps the next date.
  final int anchorDay;
  final bool automatic;
  final bool enabled;

  RecurringRule({
    required this.id,
    required this.name,
    required this.accountId,
    this.currency = 'RUB',
    this.categoryId,
    this.kind = EntryKind.expense,
    required this.amountMinor,
    this.interval = 1,
    this.frequency = 'monthly',
    this.paymentType = 'mandatory',
    required this.nextDate,
    int? anchorDay,
    this.automatic = false,
    this.enabled = true,
  }) : anchorDay = anchorDay ?? nextDate.day;

  RecurringRule copyWith({
    String? id,
    String? name,
    String? accountId,
    String? currency,
    Object? categoryId = _absent,
    EntryKind? kind,
    int? amountMinor,
    int? interval,
    String? frequency,
    String? paymentType,
    DateTime? nextDate,
    int? anchorDay,
    bool? automatic,
    bool? enabled,
  }) => RecurringRule(
    id: id ?? this.id,
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
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'accountId': accountId,
    'currency': currency,
    'categoryId': categoryId,
    'kind': kind.name,
    'amountMinor': amountMinor,
    'interval': interval,
    'frequency': frequency,
    'paymentType': paymentType,
    'nextDate': nextDate.toIso8601String(),
    'anchorDay': anchorDay,
    'automatic': automatic,
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
  final bool hideAmounts;
  final bool notifications;

  const AppPreferences({
    this.theme = 'system',
    this.accent = 'lime',
    this.baseCurrency = 'RUB',
    this.numberFormat = 'space_comma',
    this.dateFormat = 'dd.MM.yyyy',
    this.weekStart = 1,
    this.monthStart = 1,
    this.lockMinutes = 5,
    this.hideAmounts = false,
    this.notifications = true,
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
    bool? hideAmounts,
    bool? notifications,
  }) => AppPreferences(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    numberFormat: numberFormat ?? this.numberFormat,
    dateFormat: dateFormat ?? this.dateFormat,
    weekStart: weekStart ?? this.weekStart,
    monthStart: monthStart ?? this.monthStart,
    lockMinutes: lockMinutes ?? this.lockMinutes,
    hideAmounts: hideAmounts ?? this.hideAmounts,
    notifications: notifications ?? this.notifications,
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
    'hideAmounts': hideAmounts,
    'notifications': notifications,
  };

  factory AppPreferences.fromJson(Map<String, dynamic> json) => AppPreferences(
    theme: json['theme'] as String? ?? 'system',
    accent: json['accent'] as String? ?? 'lime',
    baseCurrency: json['baseCurrency'] as String? ?? 'RUB',
    numberFormat: json['numberFormat'] as String? ?? 'space_comma',
    dateFormat: json['dateFormat'] as String? ?? 'dd.MM.yyyy',
    weekStart: json['weekStart'] as int? ?? 1,
    monthStart: json['monthStart'] as int? ?? 1,
    lockMinutes: json['lockMinutes'] as int? ?? 5,
    hideAmounts: json['hideAmounts'] as bool? ?? false,
    notifications: json['notifications'] as bool? ?? true,
  );
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
