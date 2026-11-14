/// The company's journal of money: every credit that comes or goes is one
/// entry with its own id, kind and source — the basis of the financial
/// centre. Revenue, operating costs and investments are kept apart, and
/// moving the company's own goods between its own places is recorded as
/// an internal transfer, never as a sale.
library;

import 'config.dart';

enum MagEntryKind {
  /// A real deal or a paid service: freight, sales to outside buyers,
  /// contracts, task rewards.
  revenue,

  /// Running costs: fuel and feed, upkeep, repairs, buying raw goods from
  /// independent producers, processing.
  opex,

  /// Investments: vehicles, roads, buildings, upgrades, research.
  capex,

  /// Own goods moved between own places (no money; a management record).
  transfer,

  /// Money from selling a vehicle or a business (changes assets, not
  /// profit).
  assetSale,
}

class MagEntry {
  const MagEntry({
    required this.id,
    required this.tick,
    required this.kind,
    required this.category,
    required this.amount,
    this.source,
    this.sourceId,
    this.cargo,
    this.units = 0,
  });

  final int id, tick;
  final MagEntryKind kind;
  final String category;

  /// Credits: positive in, negative out, 0 for a transfer.
  final int amount;

  /// What it belongs to: 'vehicle', 'industry', 'route', 'settlement'.
  final String? source;
  final int? sourceId;
  final MagCargo? cargo;
  final int units;
}

/// The journal: a growing sequence of ids and the latest entries.
class MagJournal {
  /// Entries kept (older ones are summed in the monthly statistics).
  static const keep = 400;

  final entries = <MagEntry>[];

  /// Next entry id (never reused).
  int seq = 1;

  /// Totals per kind since the journal began (kept even when old entries
  /// are dropped).
  final sums = <MagEntryKind, int>{};

  /// Which kind a money category belongs to.
  static MagEntryKind kindOf(String category, {required bool income}) {
    if (income) {
      return const {
            'sales',
            'industry_sale',
            'warehouse_sale',
          }.contains(category)
          ? MagEntryKind.assetSale
          : MagEntryKind.revenue;
    }
    return const {
          'vehicles',
          'roads',
          'rails',
          'stations',
          'ports',
          'megaprojects',
          'upgrades',
          'warehouses',
          'warehouse_upgrade',
          'research',
          'industry_buy',
          'industry_build',
          'industry_upgrade',
        }.contains(category)
        ? MagEntryKind.capex
        : MagEntryKind.opex;
  }

  MagEntry add({
    required int tick,
    required MagEntryKind kind,
    required String category,
    required int amount,
    String? source,
    int? sourceId,
    MagCargo? cargo,
    int units = 0,
  }) {
    final e = MagEntry(
      id: seq++,
      tick: tick,
      kind: kind,
      category: category,
      amount: amount,
      source: source,
      sourceId: sourceId,
      cargo: cargo,
      units: units,
    );
    entries.add(e);
    sums[kind] = (sums[kind] ?? 0) + amount;
    if (entries.length > keep) entries.removeRange(0, entries.length - keep);
    return e;
  }

  /// Total of [kind] since the journal began, or since [fromTick] over the
  /// entries still kept.
  int total(MagEntryKind kind, {int? fromTick}) {
    if (fromTick == null) return sums[kind] ?? 0;
    var n = 0;
    for (final e in entries) {
      if (e.kind == kind && e.tick >= fromTick) n += e.amount;
    }
    return n;
  }
}
