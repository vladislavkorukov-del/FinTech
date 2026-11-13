/// The automatic dispatcher's rules: how it weighs a truck for an order in
/// each mode, and what it remembers of its choices. A plain, deterministic
/// score — no learning — so the same situation always gives the same pick.
library;

enum MagDispatchMode {
  /// Cheapest delivery: fuel and an empty run matter most.
  economy,

  /// Cost, time and a well-filled truck together.
  balanced,

  /// Soonest delivery: the fastest truck wins.
  fast,
}

/// Weights of one mode (lower score wins).
class MagDispatchWeights {
  const MagDispatchWeights(this.cost, this.time, this.waste);

  /// Per credit of running cost of the trip.
  final double cost;

  /// Per second the trip takes at 1×.
  final double time;

  /// Per unit of empty room left in the truck.
  final double waste;

  static MagDispatchWeights of(MagDispatchMode m) => switch (m) {
    MagDispatchMode.economy => const MagDispatchWeights(1, .15, .6),
    MagDispatchMode.balanced => const MagDispatchWeights(.6, .6, .35),
    MagDispatchMode.fast => const MagDispatchWeights(.05, 2, .02),
  };
}

/// One choice the dispatcher made, kept for the player to read.
class MagDispatchNote {
  const MagDispatchNote({
    required this.tick,
    required this.order,
    required this.vehicle,
    required this.reason,
  });
  final int tick, order, vehicle;
  final String reason;
}

abstract final class MagDispatch {
  /// How often the dispatcher looks at waiting orders (ticks).
  static const everyTicks = 10;

  /// A truck leaving the garage counts as this many cells of empty run.
  static const garageCells = 6;

  /// Score taken off per priority step and per day an order has waited.
  static const priorityBonus = 25.0, agePerDay = 4.0;

  /// Choices remembered.
  static const log = 12;
}
