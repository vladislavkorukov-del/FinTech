part of 'world.dart';

/// The state the later stages added to a world (S12 onwards), kept apart
/// so the world's own file stays short.
mixin _MagWorldLater {
  /// The one road cell each place (not a settlement) is entered by (S12).
  final entrances = <int, int>{};

  /// Achievements reached (id → tick), the chronicle, the debt (S15).
  final achieved = <String, int>{};
  final chronicle = <(int, String)>[];
  int debt = 0;

  /// Terminals by settlements (cell → town) and the start scenario (S17).
  final terminals = <int, int>{};
  MagScenario scenario = MagScenario.classic;

  /// Special contracts, first inputs, depots, order merging (S16).
  final deals = <MagDeal>[];
  final firstInput = <int, MagCargo>{};
  final depots = <int>{};
  bool autoMerge = true;

  /// Vehicles that entered each road cell yesterday and today (ROAD-08).
  final traffic = <int, int>{}, trafficToday = <int, int>{};
}
