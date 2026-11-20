import '../domain/models.dart';
import '../domain/planning/bill_split.dart';
import '../domain/planning/data_health.dart';
import '../domain/planning/rules_engine.dart';
import 'controller.dart';

/// The Phase 8 money mechanics as controller actions: each one a single
/// save through [FinanceController.mutate] (journal, rules, backups
/// included).
extension Phase8Actions on FinanceController {
  FinanceExtras get extras => data.extras;

  Future<void> _extras(FinanceExtras Function(FinanceExtras) f) =>
      mutate((d) => d.copyWith(extras: f(d.extras)));

  // — Честная картина —

  /// Records a balance check; returns it. Nothing else changes.
  Future<Reconciliation> reconcile(String accountId, int actualMinor) async {
    final r = DataHealth.reconcile(
      data,
      id: id(),
      accountId: accountId,
      actualMinor: actualMinor,
    );
    await _extras(
      (x) => x.copyWith(reconciliations: [...x.reconciliations, r]),
    );
    return r;
  }

  /// The explicit correction the person chose for reconciliation [recId].
  Future<void> adjustBalance(String recId) => mutate((d) {
    final r = d.extras.reconciliations.firstWhere((r) => r.id == recId);
    if (r.differenceMinor == 0 || r.adjustmentEntryId != null) return d;
    final entry = DataHealth.adjustment(r, d, id: id());
    return d.copyWith(
      entries: [...d.entries, entry],
      extras: d.extras.copyWith(
        reconciliations: [
          for (final x in d.extras.reconciliations)
            x.id == recId ? x.copyWith(adjustmentEntryId: entry.id) : x,
        ],
      ),
    );
  });

  // — Я заплатил за всех —

  Future<void> splitEntry(
    FinanceEntry entry, {
    required int own,
    required List<String> names,
    required List<int> parts,
    String method = 'equal',
  }) => mutate(
    (d) => BillSplits.create(
      d,
      entry: entry,
      own: own,
      names: names,
      parts: parts,
      newId: id,
      method: method,
    ),
  );

  Future<void> repaySplit(
    SplitShare share, {
    required int amount,
    required String accountId,
    DateTime? date,
  }) => mutate(
    (d) => BillSplits.repay(
      d,
      share: share,
      amount: amount,
      accountId: accountId,
      date: date ?? DateTime.now(),
      uniqueSuffix: id(),
    ),
  );

  Future<void> cancelRepayment(String entryId) =>
      mutate((d) => BillSplits.cancelRepayment(d, entryId));

  Future<void> editSplit(BillSplit split, int own, List<int> parts) =>
      mutate((d) => BillSplits.edit(d, split: split, own: own, parts: parts));

  // — Цели —

  Future<void> saveGoalFunding(GoalFunding funding) =>
      _extras((x) => x.copyWith(goalFunding: funding));

  // — Доход —

  Future<void> saveIncomePlan(IncomePlanSettings settings) =>
      _extras((x) => x.copyWith(incomePlan: settings));

  /// An expected income has come: a planned operation is posted as it is
  /// (no second operation); a rule's date is confirmed through the
  /// existing payment flow.
  Future<void> confirmExpected({
    String? entryId,
    String? ruleId,
    int? amountMinor,
  }) async {
    if (entryId != null) {
      await mutate(
        (d) => d.copyWith(
          entries: [
            for (final e in d.entries)
              e.id == entryId
                  ? e.copyWith(
                      status: 'posted',
                      amountMinor: amountMinor ?? e.amountMinor,
                    )
                  : e,
          ],
        ),
      );
    } else if (ruleId != null) {
      await confirmPayment(ruleId, amountMinor: amountMinor);
    }
  }

  // — Покупки —

  Future<void> savePurchase(Purchase p) => _extras(
    (x) =>
        x.copyWith(purchases: [...x.purchases.where((y) => y.id != p.id), p]),
  );

  Future<void> deletePurchase(String purchaseId) => _extras(
    (x) => x.copyWith(
      purchases: x.purchases.where((y) => y.id != purchaseId).toList(),
    ),
  );

  Future<void> addPurchaseEvent(String purchaseId, PurchaseEvent e) => _extras(
    (x) => x.copyWith(
      purchases: [
        for (final p in x.purchases)
          p.id == purchaseId ? p.copyWith(events: [...p.events, e]) : p,
      ],
    ),
  );

  // — Цены —

  Future<void> saveProduct(Product p) => _extras(
    (x) => x.copyWith(products: [...x.products.where((y) => y.id != p.id), p]),
  );

  Future<void> deleteProduct(String productId) => _extras(
    (x) => x.copyWith(
      products: x.products.where((y) => y.id != productId).toList(),
    ),
  );

  /// Moves a price that was matched to the wrong product.
  Future<void> movePrice(String priceId, String fromId, String toId) =>
      _extras((x) {
        final from = x.products.firstWhere((p) => p.id == fromId);
        final record = from.prices.firstWhere((r) => r.id == priceId);
        return x.copyWith(
          products: [
            for (final p in x.products)
              if (p.id == fromId)
                p.copyWith(
                  prices: p.prices.where((r) => r.id != priceId).toList(),
                )
              else if (p.id == toId)
                p.copyWith(prices: [...p.prices, record])
              else
                p,
          ],
        );
      });

  // — Правила —

  Future<void> saveRule(PersonalRule r) {
    final problems = RulesEngine.validate(r, data);
    if (problems.isNotEmpty) throw FormatException(problems.first);
    return _extras(
      (x) => x.copyWith(rules: [...x.rules.where((y) => y.id != r.id), r]),
    );
  }

  Future<void> deleteRule(String ruleId) => _extras(
    (x) => x.copyWith(rules: x.rules.where((r) => r.id != ruleId).toList()),
  );

  Future<void> addRuleTemplates() => _extras(
    (x) => x.copyWith(rules: [...x.rules, ...RulesEngine.templates(data, id)]),
  );

  /// Checks [rule] on the last 30 days of operations without saving.
  List<RuleOutcome> dryRun(PersonalRule rule) {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final recent = data.entries.where((e) => !e.date.isBefore(since)).toSet();
    final before = data.copyWith(
      entries: data.entries.where((e) => !recent.contains(e)).toList(),
    );
    final events = RulesEngine.events(before, data);
    return RulesEngine.process(
      data.copyWith(extras: data.extras.copyWith(ruleRuns: const [])),
      events,
      dryRun: true,
      only: [rule],
    ).$2;
  }

  Future<void> dismissNotice(String noticeId) => _extras(
    (x) => x.copyWith(
      notices: [
        for (final n in x.notices)
          n.id == noticeId ? n.copyWith(done: true) : n,
      ],
    ),
  );

  /// Accepts a rule's suggestion: an internal plan change (goal funding or
  /// a budget's room) or goal contributions — never a bank transfer.
  Future<void> applyNotice(RuleNotice n) => mutate((d) {
    var next = d;
    switch (n.kind) {
      case 'suggestGoals':
        final parts = Map<String, Object?>.from(
          n.payload['parts'] as Map? ?? {},
        );
        final source = d.entries
            .where((e) => e.id == n.payload['entryId'])
            .firstOrNull;
        if (source == null) break;
        // Set aside in the goals inside Finora (the goal's own balance).
        next = next.copyWith(
          entries: [
            ...next.entries,
            for (final e in parts.entries)
              if ((e.value as num).toInt() > 0)
                FinanceEntry(
                  id: id(),
                  kind: EntryKind.transfer,
                  amountMinor: (e.value as num).toInt(),
                  currency: source.currency,
                  accountId: source.accountId,
                  toGoalId: e.key,
                  destinationMinor: (e.value as num).toInt(),
                  date: DateTime.now(),
                  payee: 'По правилу: ${source.payee}',
                ),
          ],
        );
      case 'restoreBudget':
        next = next.copyWith(
          extras: next.extras.copyWith(
            budgetAdjustments: [
              ...next.extras.budgetAdjustments,
              BudgetAdjustment(
                id: id(),
                budgetId: '${n.payload['budgetId']}',
                periodStart: DateTime.parse('${n.payload['periodStart']}'),
                amountMinor: (n.payload['amountMinor'] as num).toInt(),
                reason: n.text,
              ),
            ],
          ),
        );
      case 'suggestNextGoal':
        final f = next.extras.goalFunding;
        final to = '${n.payload['to']}', from = '${n.payload['from']}';
        final add = (n.payload['monthlyMinor'] as num).toInt();
        final plans = {for (final p in f.plans) p.goalId: p};
        plans[to] = (plans[to] ?? GoalPlan(goalId: to)).copyWith(
          monthlyMinor: (plans[to]?.monthlyMinor ?? 0) + add,
        );
        plans[from] = (plans[from] ?? GoalPlan(goalId: from)).copyWith(
          monthlyMinor: 0,
        );
        next = next.copyWith(
          extras: next.extras.copyWith(
            goalFunding: GoalFunding(
              budgetMinor: f.budgetMinor,
              plans: plans.values.toList(),
            ),
          ),
        );
    }
    return next.copyWith(
      extras: next.extras.copyWith(
        notices: [
          for (final x in next.extras.notices)
            x.id == n.id ? x.copyWith(done: true) : x,
        ],
      ),
    );
  });
}
