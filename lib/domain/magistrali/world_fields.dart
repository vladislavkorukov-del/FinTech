part of 'world.dart';

/// The state the later stages added to a world (S12 onwards), kept apart
/// so the world's own file stays short.
mixin _MagWorldLater {
  /// Connected pieces of the road network and what they were built from
  /// (S20, not saved).
  Int32List? _roadComp;
  int _roadCompKey = -1;
  final _pathCache = <String, List<int>>{};

  /// S20: the journal of simulation errors (tick, text), the map editor's
  /// changes (cell → terrain), own places exporting surplus; mountain
  /// ranges worked out from the map (not saved).
  final simErrors = <(int, String)>[];
  final terrainEdits = <int, int>{};
  final autoExport = <int>{};

  /// Day and night on the map (S20+; a player's choice, saved).
  bool dayNight = true;
  List<MagMountain>? _mountains;
  Int32List? _mountainComp;
  int _mountainKey = -1;

  /// The one road cell each place (not a settlement) is entered by (S12).
  final entrances = <int, int>{};

  /// Achievements reached (id → tick), the chronicle, the debt (S15).
  final achieved = <String, int>{};
  final chronicle = <(int, String)>[];
  int debt = 0;

  /// Rivals, megalopolis stars, the vehicle collection, days in the
  /// minus (S19).
  final rivals = <MagRival>[];
  bool rivalsMet = false;
  final stars = <int, int>{}, starDays = <int, int>{};
  final collection = <String>{};
  int collectionPaid = 0, negativeDays = 0;

  /// The auction lot, historical contracts offered, regions (S18).
  MagAuction? auction;
  final historicOffered = <String>{};
  bool regionsLocked = false;
  final openRegions = <int>{};

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
