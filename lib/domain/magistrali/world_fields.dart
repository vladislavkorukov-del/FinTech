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

  /// S21: biomes on (new companies), their cache, subsidies, unique
  /// orders already offered.
  bool biomesOn = false;

  /// S22: airports (cell → place); a living world (seasons, weather,
  /// events, the campaign), its events and chapter.
  final airports = <int, int>{};
  bool livingWorld = false;
  final events = <MagEvent>[];
  int chapterIndex = 0;

  /// S23: broken road cells (cell → tick mended), the company's own
  /// shares, stakes in rivals, the share price by day.
  final damaged = <int, int>{};
  int ownShares = MagRules.shares;
  final rivalStakes = <String, int>{};
  final priceHistory = <int>[];

  /// S24: bonds issued, insurance.
  final bonds = <MagBond>[];
  bool insured = false;

  /// S25: container terminals (port cells), rail signals, road
  /// interchanges, night shifts (place ids), town mortgages.
  final terminals2 = <int>{};
  final signals = <int>{};
  final interchanges = <int>{};
  final nightShifts = <int>{};
  final mortgages = <MagMortgage>[];
  final _biomes = <int, MagBiome>{};
  final subsidies = <MagSubsidy>[];
  final uniqueOffered = <String>{};

  /// Day and night on the map (S20+; a player's choice, saved).
  bool dayNight = true;

  /// Music and sound effects (S21; the player's choice, saved).
  bool musicOn = true, soundOn = true;
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
