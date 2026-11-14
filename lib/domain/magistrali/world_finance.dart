part of 'world.dart';

/// Figures of one period for the finance centre.
class MagPeriod {
  MagPeriod(this.title);
  final String title;
  int revenue = 0, opex = 0, capex = 0, assetSales = 0;

  /// Revenue minus running costs (investments are not costs).
  int get operating => revenue - opex;

  /// All money in minus all money out.
  int get cashFlow => revenue + assetSales - opex - capex;

  /// Operating profit as a share of revenue (0 when nothing was earned).
  double get margin => revenue == 0 ? 0 : operating / revenue;
}

/// A vehicle's business figures.
class MagVehicleFigures {
  const MagVehicleFigures(this.vehicle, this.profit, this.loaded);
  final MagVehicle vehicle;
  final int profit;

  /// Share of the distance driven with cargo (null: not driven yet).
  final double? loaded;
}

/// An owned business with its figures.
class MagIndustryFigures {
  const MagIndustryFigures(this.industry, this.profit, this.paybackDays);
  final MagIndustry industry;
  final int profit;

  /// Days its outlay takes to come back at the profit so far (null: it
  /// makes no profit yet, or its age is not known).
  final int? paybackDays;
}

/// The finance centre of the company: real figures from the journal, the
/// months and the places — nothing estimated twice, own transfers are not
/// revenue, investments are kept apart from costs. It never touches the
/// player's own Finora accounting.
extension MagWorldFinance on MagWorld {
  /// A month's figures split by kind (from its categories).
  MagPeriod periodOf(MagMonth m, String title) {
    final p = MagPeriod(title);
    for (final e in m.income.entries) {
      if (MagJournal.kindOf(e.key, income: true) == MagEntryKind.assetSale) {
        p.assetSales += e.value;
      } else {
        p.revenue += e.value;
      }
    }
    for (final e in m.expense.entries) {
      if (MagJournal.kindOf(e.key, income: false) == MagEntryKind.capex) {
        p.capex += e.value;
      } else {
        p.opex += e.value;
      }
    }
    return p;
  }

  /// This month, the last one, and all kept months together.
  List<MagPeriod> get periods {
    final out = [periodOf(month, 'Этот месяц')];
    if (months.length > 1) {
      out.add(periodOf(months[months.length - 2], 'Прошлый месяц'));
    }
    final all = MagPeriod('${months.length} мес.');
    for (final m in months) {
      final p = periodOf(m, '');
      all
        ..revenue += p.revenue
        ..opex += p.opex
        ..capex += p.capex
        ..assetSales += p.assetSales;
    }
    out.add(all);
    return out;
  }

  /// Revenue by category over the kept months (largest first).
  List<MapEntry<String, int>> get revenueMix {
    final sum = <String, int>{};
    for (final m in months) {
      for (final e in m.income.entries) {
        if (MagJournal.kindOf(e.key, income: true) != MagEntryKind.revenue) {
          continue;
        }
        sum[e.key] = (sum[e.key] ?? 0) + e.value;
      }
    }
    return sum.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Vehicles with their profit, most profitable first.
  List<MagVehicleFigures> get vehicleFigures {
    final out = [
      for (final v in vehicles.values)
        MagVehicleFigures(
          v,
          v.income - v.costs,
          v.odometer <= 0 ? null : 1 - (v.emptyCells / v.odometer).clamp(0, 1),
        ),
    ];
    out.sort((a, b) => b.profit.compareTo(a.profit));
    return out;
  }

  /// Owned businesses with their figures, best first.
  List<MagIndustryFigures> get industryFigures {
    final out = <MagIndustryFigures>[];
    for (final i in map.industries) {
      if (!i.owned) continue;
      final profit = i.revenue - i.costs;
      final since = i.since;
      int? payback;
      if (since != null && profit > 0 && tick > since) {
        final perDay = profit / ((tick - since) / MagRules.ticksPerDay);
        if (perDay > 0) payback = (i.invested / perDay).ceil();
      }
      out.add(MagIndustryFigures(i, profit, payback));
    }
    out.sort((a, b) => b.profit.compareTo(a.profit));
    return out;
  }

  /// Settlements the company serves (any revenue), largest first.
  List<MagIndustry> get servedTowns =>
      settlements.where((i) => i.town!.revenue > 0).toList()
        ..sort((a, b) => b.town!.revenue.compareTo(a.town!.revenue));

  /// What the company owns besides money.
  int get fleetValue => vehicles.values.fold(0, (s, v) => s + valueOf(v));

  int get roadsValue {
    var n = 0;
    for (final r in roads) {
      if (r != 0) n += MagRules.roads[MagRoad.values[r]]!.cost ~/ 2;
    }
    return n;
  }

  int get warehousesValue => warehouses.fold(
    0,
    (s, w) => s + ((MagRules.warehousePrice + w.invested) * .5).round(),
  );
}
