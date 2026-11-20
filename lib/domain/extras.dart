// Data of the Phase 8 money mechanics (stored with the ledger, in backups).
// Amounts are kopecks (int), dates local.

DateTime _date(Object? v) => DateTime.tryParse('$v') ?? DateTime(2000);
DateTime? _dateOrNull(Object? v) => v == null ? null : DateTime.tryParse('$v');
int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) => [
  for (final e in v as List? ?? const [])
    if (e is Map) f(Map<String, dynamic>.from(e)),
];

/// A balance check of one account: what the ledger said and what the person
/// saw in the bank. A difference is shown, never hidden; an adjustment is an
/// explicit operation the person chose to create.
class Reconciliation {
  const Reconciliation({
    required this.id,
    required this.accountId,
    required this.at,
    required this.bookMinor,
    required this.actualMinor,
    this.adjustmentEntryId,
    this.note = '',
  });
  final String id, accountId;
  final DateTime at;
  final int bookMinor, actualMinor;
  final String? adjustmentEntryId;
  final String note;
  int get differenceMinor => actualMinor - bookMinor;

  Reconciliation copyWith({String? adjustmentEntryId}) => Reconciliation(
    id: id,
    accountId: accountId,
    at: at,
    bookMinor: bookMinor,
    actualMinor: actualMinor,
    adjustmentEntryId: adjustmentEntryId ?? this.adjustmentEntryId,
    note: note,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'accountId': accountId,
    'at': at.toIso8601String(),
    'bookMinor': bookMinor,
    'actualMinor': actualMinor,
    'adjustmentEntryId': adjustmentEntryId,
    'note': note,
  };
  factory Reconciliation.fromJson(Map<String, dynamic> j) => Reconciliation(
    id: '${j['id']}',
    accountId: '${j['accountId']}',
    at: _date(j['at']),
    bookMinor: _int(j['bookMinor']),
    actualMinor: _int(j['actualMinor']),
    adjustmentEntryId: j['adjustmentEntryId'] as String?,
    note: j['note'] as String? ?? '',
  );
}

/// One person's part of a shared bill: a «Мне должны» debt in the existing
/// debt system ([ruleId]).
class SplitShare {
  const SplitShare({
    required this.name,
    required this.shareMinor,
    required this.ruleId,
  });
  final String name, ruleId;
  final int shareMinor;
  Map<String, Object?> toJson() => {
    'name': name,
    'shareMinor': shareMinor,
    'ruleId': ruleId,
  };
  factory SplitShare.fromJson(Map<String, dynamic> j) => SplitShare(
    name: '${j['name']}',
    shareMinor: _int(j['shareMinor']),
    ruleId: '${j['ruleId']}',
  );
}

/// «Я заплатил за всех»: an expense split between the person and others.
class BillSplit {
  const BillSplit({
    required this.id,
    required this.entryId,
    required this.ownShareMinor,
    required this.shares,
    required this.createdAt,
    this.method = 'equal',
  });
  final String id, entryId, method;
  final int ownShareMinor;
  final List<SplitShare> shares;
  final DateTime createdAt;
  int get othersMinor => shares.fold(0, (a, s) => a + s.shareMinor);

  Map<String, Object?> toJson() => {
    'id': id,
    'entryId': entryId,
    'ownShareMinor': ownShareMinor,
    'shares': [for (final s in shares) s.toJson()],
    'createdAt': createdAt.toIso8601String(),
    'method': method,
  };
  factory BillSplit.fromJson(Map<String, dynamic> j) => BillSplit(
    id: '${j['id']}',
    entryId: '${j['entryId']}',
    ownShareMinor: _int(j['ownShareMinor']),
    shares: _list(j['shares'], SplitShare.fromJson),
    createdAt: _date(j['createdAt']),
    method: j['method'] as String? ?? 'equal',
  );
}

/// How one goal is funded from the monthly goals budget.
class GoalPlan {
  const GoalPlan({
    required this.goalId,
    this.monthlyMinor = 0,
    this.priority = 0,
    this.protected = false,
  });
  final String goalId;

  /// Planned contribution per month (the share of the goals budget).
  final int monthlyMinor;

  /// Lower runs first when money is short.
  final int priority;

  /// Funded before the others whatever the priority.
  final bool protected;

  GoalPlan copyWith({int? monthlyMinor, int? priority, bool? protected}) =>
      GoalPlan(
        goalId: goalId,
        monthlyMinor: monthlyMinor ?? this.monthlyMinor,
        priority: priority ?? this.priority,
        protected: protected ?? this.protected,
      );
  Map<String, Object?> toJson() => {
    'goalId': goalId,
    'monthlyMinor': monthlyMinor,
    'priority': priority,
    'protected': protected,
  };
  factory GoalPlan.fromJson(Map<String, dynamic> j) => GoalPlan(
    goalId: '${j['goalId']}',
    monthlyMinor: _int(j['monthlyMinor']),
    priority: _int(j['priority']),
    protected: j['protected'] == true,
  );
}

/// The money set aside for goals each month and how it is shared.
class GoalFunding {
  const GoalFunding({this.budgetMinor = 0, this.plans = const []});
  final int budgetMinor;
  final List<GoalPlan> plans;
  GoalPlan planFor(String goalId) =>
      plans.where((p) => p.goalId == goalId).firstOrNull ??
      GoalPlan(goalId: goalId);
  Map<String, Object?> toJson() => {
    'budgetMinor': budgetMinor,
    'plans': [for (final p in plans) p.toJson()],
  };
  factory GoalFunding.fromJson(Object? j) {
    if (j is! Map) return const GoalFunding();
    return GoalFunding(
      budgetMinor: _int(j['budgetMinor']),
      plans: _list(j['plans'], GoalPlan.fromJson),
    );
  }
}

/// Settings of the irregular-income plan.
class IncomePlanSettings {
  const IncomePlanSettings({this.reserveMinor = 0, this.horizonDays});
  final int reserveMinor;

  /// Chosen by the person when the next income date is unknown.
  final int? horizonDays;
  Map<String, Object?> toJson() => {
    'reserveMinor': reserveMinor,
    'horizonDays': horizonDays,
  };
  factory IncomePlanSettings.fromJson(Object? j) {
    if (j is! Map) return const IncomePlanSettings();
    return IncomePlanSettings(
      reserveMinor: _int(j['reserveMinor']),
      horizonDays: (j['horizonDays'] as num?)?.toInt(),
    );
  }
}

/// A change of a budget's room made by a rule (or by the person): for the
/// period that starts on [periodStart], the budget has [amountMinor] more.
class BudgetAdjustment {
  const BudgetAdjustment({
    required this.id,
    required this.budgetId,
    required this.periodStart,
    required this.amountMinor,
    required this.reason,
  });
  final String id, budgetId, reason;
  final DateTime periodStart;
  final int amountMinor;
  Map<String, Object?> toJson() => {
    'id': id,
    'budgetId': budgetId,
    'periodStart': periodStart.toIso8601String(),
    'amountMinor': amountMinor,
    'reason': reason,
  };
  factory BudgetAdjustment.fromJson(Map<String, dynamic> j) => BudgetAdjustment(
    id: '${j['id']}',
    budgetId: '${j['budgetId']}',
    periodStart: _date(j['periodStart']),
    amountMinor: _int(j['amountMinor']),
    reason: j['reason'] as String? ?? '',
  );
}

/// A personal «если → то» rule.
class PersonalRule {
  const PersonalRule({
    required this.id,
    required this.name,
    required this.trigger,
    this.enabled = true,
    this.priority = 0,
    this.conditions = const [],
    this.actions = const [],
    this.periodDays = 30,
  });
  final String id, name;

  /// income · refund · budgetThreshold · incomeDateChanged · goalFunded
  final String trigger;
  final bool enabled;
  final int priority;
  final List<Map<String, Object?>> conditions;
  final List<Map<String, Object?>> actions;

  /// «Один раз за период» for notifications.
  final int periodDays;

  PersonalRule copyWith({
    String? name,
    bool? enabled,
    int? priority,
    List<Map<String, Object?>>? conditions,
    List<Map<String, Object?>>? actions,
    int? periodDays,
  }) => PersonalRule(
    id: id,
    name: name ?? this.name,
    trigger: trigger,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    conditions: conditions ?? this.conditions,
    actions: actions ?? this.actions,
    periodDays: periodDays ?? this.periodDays,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'trigger': trigger,
    'enabled': enabled,
    'priority': priority,
    'conditions': conditions,
    'actions': actions,
    'periodDays': periodDays,
  };
  factory PersonalRule.fromJson(Map<String, dynamic> j) => PersonalRule(
    id: '${j['id']}',
    name: '${j['name']}',
    trigger: '${j['trigger']}',
    enabled: j['enabled'] != false,
    priority: _int(j['priority']),
    conditions: [
      for (final c in j['conditions'] as List? ?? const [])
        if (c is Map) Map<String, Object?>.from(c),
    ],
    actions: [
      for (final a in j['actions'] as List? ?? const [])
        if (a is Map) Map<String, Object?>.from(a),
    ],
    periodDays: _int(j['periodDays'], 30),
  );
}

/// One processing of an event by a rule — kept so that the same event is
/// never processed twice, also after a restart.
class RuleRun {
  const RuleRun({
    required this.ruleId,
    required this.eventKey,
    required this.at,
    required this.fired,
    required this.explanation,
  });
  final String ruleId, eventKey, explanation;
  final DateTime at;
  final bool fired;
  Map<String, Object?> toJson() => {
    'ruleId': ruleId,
    'eventKey': eventKey,
    'at': at.toIso8601String(),
    'fired': fired,
    'explanation': explanation,
  };
  factory RuleRun.fromJson(Map<String, dynamic> j) => RuleRun(
    ruleId: '${j['ruleId']}',
    eventKey: '${j['eventKey']}',
    at: _date(j['at']),
    fired: j['fired'] == true,
    explanation: j['explanation'] as String? ?? '',
  );
}

/// A notification or suggestion a rule left for the person.
class RuleNotice {
  const RuleNotice({
    required this.id,
    required this.ruleId,
    required this.at,
    required this.kind,
    required this.text,
    this.payload = const {},
    this.done = false,
  });
  final String id, ruleId, kind, text;
  final DateTime at;
  final Map<String, Object?> payload;
  final bool done;
  RuleNotice copyWith({bool? done}) => RuleNotice(
    id: id,
    ruleId: ruleId,
    at: at,
    kind: kind,
    text: text,
    payload: payload,
    done: done ?? this.done,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'ruleId': ruleId,
    'at': at.toIso8601String(),
    'kind': kind,
    'text': text,
    'payload': payload,
    'done': done,
  };
  factory RuleNotice.fromJson(Map<String, dynamic> j) => RuleNotice(
    id: '${j['id']}',
    ruleId: '${j['ruleId']}',
    at: _date(j['at']),
    kind: '${j['kind']}',
    text: '${j['text']}',
    payload: Map<String, Object?>.from(j['payload'] as Map? ?? const {}),
    done: j['done'] == true,
  );
}

/// A use, a cost or a recovery of a purchase.
class PurchaseEvent {
  const PurchaseEvent({
    required this.id,
    required this.kind,
    required this.at,
    this.count = 0,
    this.amountMinor = 0,
    this.entryId,
    this.note = '',
  });
  final String id;

  /// use · service · repair · supplies · refund · sale
  final String kind;
  final DateTime at;
  final int count, amountMinor;
  final String? entryId;
  final String note;
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'at': at.toIso8601String(),
    'count': count,
    'amountMinor': amountMinor,
    'entryId': entryId,
    'note': note,
  };
  factory PurchaseEvent.fromJson(Map<String, dynamic> j) => PurchaseEvent(
    id: '${j['id']}',
    kind: '${j['kind']}',
    at: _date(j['at']),
    count: _int(j['count']),
    amountMinor: _int(j['amountMinor']),
    entryId: j['entryId'] as String?,
    note: j['note'] as String? ?? '',
  );
}

/// A purchase card: what was expected of a thing and what it really cost
/// and gave.
class Purchase {
  const Purchase({
    required this.id,
    required this.name,
    required this.date,
    required this.priceMinor,
    this.currency = 'RUB',
    this.categoryId,
    this.entryId,
    this.motive = 'necessity',
    this.expectedUsesPerMonth,
    this.expectedMonths,
    this.events = const [],
    this.satisfaction,
    this.again,
    this.note = '',
    this.planned = false,
    this.remindAt,
  });
  final String id, name, currency, motive, note;
  final DateTime date;
  final int priceMinor;
  final String? categoryId, entryId;
  final int? expectedUsesPerMonth, expectedMonths, satisfaction;
  final bool? again;
  final List<PurchaseEvent> events;

  /// Weighed before buying: no expense exists.
  final bool planned;
  final DateTime? remindAt;

  Purchase copyWith({
    String? name,
    DateTime? date,
    int? priceMinor,
    Object? categoryId = _keep,
    Object? entryId = _keep,
    String? motive,
    Object? expectedUsesPerMonth = _keep,
    Object? expectedMonths = _keep,
    List<PurchaseEvent>? events,
    Object? satisfaction = _keep,
    Object? again = _keep,
    String? note,
    bool? planned,
    Object? remindAt = _keep,
  }) => Purchase(
    id: id,
    name: name ?? this.name,
    date: date ?? this.date,
    priceMinor: priceMinor ?? this.priceMinor,
    currency: currency,
    categoryId: identical(categoryId, _keep)
        ? this.categoryId
        : categoryId as String?,
    entryId: identical(entryId, _keep) ? this.entryId : entryId as String?,
    motive: motive ?? this.motive,
    expectedUsesPerMonth: identical(expectedUsesPerMonth, _keep)
        ? this.expectedUsesPerMonth
        : expectedUsesPerMonth as int?,
    expectedMonths: identical(expectedMonths, _keep)
        ? this.expectedMonths
        : expectedMonths as int?,
    events: events ?? this.events,
    satisfaction: identical(satisfaction, _keep)
        ? this.satisfaction
        : satisfaction as int?,
    again: identical(again, _keep) ? this.again : again as bool?,
    note: note ?? this.note,
    planned: planned ?? this.planned,
    remindAt: identical(remindAt, _keep)
        ? this.remindAt
        : remindAt as DateTime?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'date': date.toIso8601String(),
    'priceMinor': priceMinor,
    'currency': currency,
    'categoryId': categoryId,
    'entryId': entryId,
    'motive': motive,
    'expectedUsesPerMonth': expectedUsesPerMonth,
    'expectedMonths': expectedMonths,
    'events': [for (final e in events) e.toJson()],
    'satisfaction': satisfaction,
    'again': again,
    'note': note,
    'planned': planned,
    'remindAt': remindAt?.toIso8601String(),
  };
  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
    id: '${j['id']}',
    name: '${j['name']}',
    date: _date(j['date']),
    priceMinor: _int(j['priceMinor']),
    currency: j['currency'] as String? ?? 'RUB',
    categoryId: j['categoryId'] as String?,
    entryId: j['entryId'] as String?,
    motive: j['motive'] as String? ?? 'necessity',
    expectedUsesPerMonth: (j['expectedUsesPerMonth'] as num?)?.toInt(),
    expectedMonths: (j['expectedMonths'] as num?)?.toInt(),
    events: _list(j['events'], PurchaseEvent.fromJson),
    satisfaction: (j['satisfaction'] as num?)?.toInt(),
    again: j['again'] as bool?,
    note: j['note'] as String? ?? '',
    planned: j['planned'] == true,
    remindAt: _dateOrNull(j['remindAt']),
  );
}

const _keep = Object();

/// One price paid for a product.
class PriceRecord {
  const PriceRecord({
    required this.id,
    required this.date,
    required this.store,
    required this.priceMinor,
    required this.sizeMilli,
    this.currency = 'RUB',
    this.packs = 1,
    this.promo = false,
    this.entryId,
  });
  final String id, store, currency;
  final DateTime date;

  /// The price of [packs] packs together.
  final int priceMinor, packs;

  /// Size of one pack in thousandths of the product's unit: 900 = 0.9 l,
  /// 1000 = 1 kg, 6000 = 6 pcs.
  final int sizeMilli;
  final bool promo;
  final String? entryId;
  Map<String, Object?> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'store': store,
    'priceMinor': priceMinor,
    'sizeMilli': sizeMilli,
    'currency': currency,
    'packs': packs,
    'promo': promo,
    'entryId': entryId,
  };
  factory PriceRecord.fromJson(Map<String, dynamic> j) => PriceRecord(
    id: '${j['id']}',
    date: _date(j['date']),
    store: '${j['store']}',
    priceMinor: _int(j['priceMinor']),
    sizeMilli: _int(j['sizeMilli'], 1000),
    currency: j['currency'] as String? ?? 'RUB',
    packs: _int(j['packs'], 1),
    promo: j['promo'] == true,
    entryId: j['entryId'] as String?,
  );
}

/// A product the person buys, with its own price history.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.unit,
    this.brand = '',
    this.variant = '',
    this.barcode,
    this.prices = const [],
  });
  final String id, name, brand, variant;

  /// kg · l · pcs
  final String unit;
  final String? barcode;
  final List<PriceRecord> prices;
  Product copyWith({
    String? name,
    String? brand,
    String? variant,
    String? unit,
    Object? barcode = _keep,
    List<PriceRecord>? prices,
  }) => Product(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    brand: brand ?? this.brand,
    variant: variant ?? this.variant,
    barcode: identical(barcode, _keep) ? this.barcode : barcode as String?,
    prices: prices ?? this.prices,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'brand': brand,
    'variant': variant,
    'barcode': barcode,
    'prices': [for (final p in prices) p.toJson()],
  };
  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: '${j['id']}',
    name: '${j['name']}',
    unit: j['unit'] as String? ?? 'pcs',
    brand: j['brand'] as String? ?? '',
    variant: j['variant'] as String? ?? '',
    barcode: j['barcode'] as String?,
    prices: _list(j['prices'], PriceRecord.fromJson),
  );
}

/// Everything of the Phase 8 mechanics that lives with the ledger.
class FinanceExtras {
  const FinanceExtras({
    this.reconciliations = const [],
    this.splits = const [],
    this.goalFunding = const GoalFunding(),
    this.incomePlan = const IncomePlanSettings(),
    this.budgetAdjustments = const [],
    this.rules = const [],
    this.ruleRuns = const [],
    this.notices = const [],
    this.purchases = const [],
    this.products = const [],
  });
  final List<Reconciliation> reconciliations;
  final List<BillSplit> splits;
  final GoalFunding goalFunding;
  final IncomePlanSettings incomePlan;
  final List<BudgetAdjustment> budgetAdjustments;
  final List<PersonalRule> rules;
  final List<RuleRun> ruleRuns;
  final List<RuleNotice> notices;
  final List<Purchase> purchases;
  final List<Product> products;

  FinanceExtras copyWith({
    List<Reconciliation>? reconciliations,
    List<BillSplit>? splits,
    GoalFunding? goalFunding,
    IncomePlanSettings? incomePlan,
    List<BudgetAdjustment>? budgetAdjustments,
    List<PersonalRule>? rules,
    List<RuleRun>? ruleRuns,
    List<RuleNotice>? notices,
    List<Purchase>? purchases,
    List<Product>? products,
  }) => FinanceExtras(
    reconciliations: reconciliations ?? this.reconciliations,
    splits: splits ?? this.splits,
    goalFunding: goalFunding ?? this.goalFunding,
    incomePlan: incomePlan ?? this.incomePlan,
    budgetAdjustments: budgetAdjustments ?? this.budgetAdjustments,
    rules: rules ?? this.rules,
    ruleRuns: ruleRuns ?? this.ruleRuns,
    notices: notices ?? this.notices,
    purchases: purchases ?? this.purchases,
    products: products ?? this.products,
  );

  Map<String, Object?> toJson() => {
    'reconciliations': [for (final r in reconciliations) r.toJson()],
    'splits': [for (final s in splits) s.toJson()],
    'goalFunding': goalFunding.toJson(),
    'incomePlan': incomePlan.toJson(),
    'budgetAdjustments': [for (final b in budgetAdjustments) b.toJson()],
    'rules': [for (final r in rules) r.toJson()],
    'ruleRuns': [for (final r in ruleRuns) r.toJson()],
    'notices': [for (final n in notices) n.toJson()],
    'purchases': [for (final p in purchases) p.toJson()],
    'products': [for (final p in products) p.toJson()],
  };

  factory FinanceExtras.fromJson(Object? j) {
    if (j is! Map) return const FinanceExtras();
    return FinanceExtras(
      reconciliations: _list(j['reconciliations'], Reconciliation.fromJson),
      splits: _list(j['splits'], BillSplit.fromJson),
      goalFunding: GoalFunding.fromJson(j['goalFunding']),
      incomePlan: IncomePlanSettings.fromJson(j['incomePlan']),
      budgetAdjustments: _list(
        j['budgetAdjustments'],
        BudgetAdjustment.fromJson,
      ),
      rules: _list(j['rules'], PersonalRule.fromJson),
      ruleRuns: _list(j['ruleRuns'], RuleRun.fromJson),
      notices: _list(j['notices'], RuleNotice.fromJson),
      purchases: _list(j['purchases'], Purchase.fromJson),
      products: _list(j['products'], Product.fromJson),
    );
  }
}

/// One record of the time machine's journal: a change the person made
/// (`entry`, `goal`, `budget`, `rule`, `account`, `goalFunding`,
/// `reconciliation`) or a saved plan state (`snapshot`).
class HistoryEvent {
  const HistoryEvent({
    required this.id,
    required this.at,
    required this.kind,
    required this.payload,
  });
  final String id, kind;

  /// When the app recorded it.
  final DateTime at;
  final Map<String, Object?> payload;
  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'kind': kind,
    'payload': payload,
  };
  factory HistoryEvent.fromJson(Map<String, dynamic> j) => HistoryEvent(
    id: '${j['id']}',
    at: _date(j['at']),
    kind: '${j['kind']}',
    payload: Map<String, Object?>.from(j['payload'] as Map? ?? const {}),
  );
}
