import '../models.dart';

/// The cost of owning a purchase, with what it consists of.
class PurchaseCost {
  const PurchaseCost({
    required this.priceMinor,
    required this.upkeepMinor,
    required this.recoveredMinor,
    required this.uses,
    required this.expectedUses,
    required this.months,
  });
  final int priceMinor;

  /// Service, repair and supplies within the period.
  final int upkeepMinor;

  /// Money back: a refund or a sale.
  final int recoveredMinor;

  /// Real uses the person recorded.
  final int uses;

  /// Uses expected for the same period from the person's own estimate (null
  /// without one).
  final int? expectedUses;

  /// Months owned within the period.
  final int months;

  int get totalMinor => priceMinor + upkeepMinor;
  int get netMinor => totalMinor - recoveredMinor;

  /// Per real use; null when there were no uses (never divided by zero).
  int? get perUseMinor => uses == 0 ? null : (netMinor + uses ~/ 2) ~/ uses;

  /// Per use as expected over the whole planned ownership (price only);
  /// null without an estimate.
  int? perExpectedUseMinor(Purchase p) {
    final u = p.expectedUsesPerMonth, m = p.expectedMonths;
    if (u == null || m == null || u <= 0 || m <= 0) return null;
    final all = u * m;
    return (p.priceMinor + all ~/ 2) ~/ all;
  }
}

/// «Полезность покупки» (Phase 8): price plus upkeep minus money back,
/// per real use and per expected use. Uses are counted by the person (no
/// automatic observation). An upkeep cost linked to an operation is counted
/// from that operation once; an unlinked one by its own amount.
abstract final class PurchaseMath {
  static const motives = {
    'necessity': 'Необходимость',
    'convenience': 'Удобство',
    'work': 'Работа',
    'pleasure': 'Удовольствие',
    'impulse': 'Импульс',
    'other': 'Другое',
  };
  static const costKinds = {
    'service': 'Обслуживание',
    'repair': 'Ремонт',
    'supplies': 'Расходники',
  };

  static PurchaseCost cost(
    Purchase p,
    FinanceData data, {
    DateTime? from,
    DateTime? until,
  }) {
    final start = from ?? p.date;
    final end = until ?? DateTime.now();
    bool inside(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
    final linked = <String>{};
    var upkeep = 0, recovered = 0, uses = 0;
    for (final e in p.events) {
      if (!inside(e.at)) continue;
      switch (e.kind) {
        case 'use':
          uses += e.count;
        case 'service' || 'repair' || 'supplies':
          if (e.entryId != null) {
            if (!linked.add(e.entryId!)) continue;
            final entry = data.entries
                .where((x) => x.id == e.entryId)
                .firstOrNull;
            upkeep += entry?.amountMinor ?? e.amountMinor;
          } else {
            upkeep += e.amountMinor;
          }
        case 'refund' || 'sale':
          recovered += e.amountMinor;
      }
    }
    // The price: from the linked expense when there is one (not counted
    // twice), else the card's own price.
    final entry = p.entryId == null
        ? null
        : data.entries.where((x) => x.id == p.entryId).firstOrNull;
    final price = p.planned
        ? p.priceMinor
        : (entry?.amountMinor ?? p.priceMinor);
    var months = (end.year - start.year) * 12 + end.month - start.month;
    if (end.day < start.day) months--;
    if (months < 1) months = 1;
    final perMonth = p.expectedUsesPerMonth;
    return PurchaseCost(
      priceMinor: price,
      upkeepMinor: upkeep,
      recoveredMinor: recovered,
      uses: uses,
      expectedUses: perMonth == null ? null : perMonth * months,
      months: months,
    );
  }

  /// Average satisfaction and «купил бы снова» by motive or category, from
  /// the person's own answers.
  static Map<String, ({int count, double? satisfaction, int again})> byMotive(
    List<Purchase> purchases,
  ) {
    final out = <String, ({int count, double? satisfaction, int again})>{};
    for (final m in motives.keys) {
      final list = purchases.where((p) => p.motive == m && !p.planned).toList();
      if (list.isEmpty) continue;
      final rated = list.where((p) => p.satisfaction != null).toList();
      out[m] = (
        count: list.length,
        satisfaction: rated.isEmpty
            ? null
            : rated.fold<int>(0, (a, p) => a + p.satisfaction!) / rated.length,
        again: list.where((p) => p.again == true).length,
      );
    }
    return out;
  }
}

/// A price brought to one unit: per kg, litre or piece.
class UnitPrice {
  const UnitPrice(this.record, this.perUnitMinor);
  final PriceRecord record;

  /// Kopecks per whole unit (kg, l, pcs), rounded.
  final int perUnitMinor;
}

/// A pack shrinking at the same price.
class Shrink {
  const Shrink(this.before, this.after, this.percent);
  final PriceRecord before, after;

  /// How much dearer per unit, in hundredths of a percent (1110 = 11.1 %).
  final int percent;
}

/// «Личная история цен» (Phase 8): prices of one product per unit, by
/// store, and shrinking packs. Only the person's own purchases are compared;
/// different units or currencies are never mixed.
abstract final class PriceMath {
  static const units = {'kg': 'кг', 'l': 'л', 'pcs': 'шт.'};

  /// Per whole unit: price of one pack × 1000 / size in thousandths.
  static int perUnit(PriceRecord r) {
    final packs = r.packs <= 0 ? 1 : r.packs;
    final size = r.sizeMilli <= 0 ? 1000 : r.sizeMilli;
    // price × 1000 / (packs × size), rounded half up, in whole numbers.
    final d = packs * size;
    return (r.priceMinor * 1000 * 2 + d) ~/ (2 * d);
  }

  static List<UnitPrice> history(Product p, {String? currency}) {
    final cur = currency ?? p.prices.firstOrNull?.currency ?? 'RUB';
    return [
      for (final r in [...p.prices]..sort((a, b) => a.date.compareTo(b.date)))
        if (r.currency == cur) UnitPrice(r, perUnit(r)),
    ];
  }

  /// The lowest unit price seen in each store (promotions marked in the
  /// record), cheapest first.
  static List<UnitPrice> byStore(Product p, {String? currency}) {
    final best = <String, UnitPrice>{};
    for (final u in history(p, currency: currency)) {
      final key = u.record.store.trim().toLowerCase();
      final was = best[key];
      if (was == null || u.perUnitMinor < was.perUnitMinor) best[key] = u;
    }
    return best.values.toList()
      ..sort((a, b) => a.perUnitMinor.compareTo(b.perUnitMinor));
  }

  /// Packs that got smaller while the price per pack stayed (or fell less
  /// than the size): consecutive purchases, same currency.
  static List<Shrink> shrinks(Product p) {
    final list = history(p);
    final out = <Shrink>[];
    for (var i = 1; i < list.length; i++) {
      final a = list[i - 1].record, b = list[i].record;
      if (b.sizeMilli >= a.sizeMilli) continue;
      final pa = a.priceMinor * 1000 ~/ (a.packs <= 0 ? 1 : a.packs);
      final pb = b.priceMinor * 1000 ~/ (b.packs <= 0 ? 1 : b.packs);
      if (pb < pa) continue;
      final ua = list[i - 1].perUnitMinor, ub = list[i].perUnitMinor;
      if (ua <= 0 || ub <= ua) continue;
      out.add(Shrink(a, b, ((ub - ua) * 10000 / ua).round()));
    }
    return out;
  }

  /// «1 л», «0,9 л», «6 шт.».
  static String size(int milli, String unit) {
    final whole = milli ~/ 1000, frac = milli % 1000;
    var s = frac == 0
        ? '$whole'
        : '$whole,${frac.toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '')}';
    if (whole == 0 && frac != 0 && unit != 'pcs') {
      // 0,25 кг reads better as 250 г / 250 мл.
      s = '$frac';
      return '$s ${unit == 'kg' ? 'г' : 'мл'}';
    }
    return '$s ${units[unit] ?? unit}';
  }
}
