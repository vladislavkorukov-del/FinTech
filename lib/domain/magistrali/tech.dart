/// The company's technology tree. Every node changes a real number of the
/// game: [MagTech.effects] adds to a named bonus that the simulation reads
/// (see `MagWorldTech.bonus`). Nodes are bought with credits once the
/// company level, the earlier nodes and the delivery record allow — no
/// timers.
library;

import 'tech_nodes.dart';

enum MagBranch { fleet, roads, storage, economy }

/// Bonus keys the simulation reads. Fractions add up (+.05 = +5 %);
/// counts add as numbers.
abstract final class MagBonus {
  static const speed = 'speed', capacity = 'capacity', fuel = 'fuel';
  static const wear = 'wear', service = 'service', upkeep = 'upkeep';
  static const roadCost = 'roadCost', bridge = 'bridge';
  static const roadSpeed = 'roadSpeed', roadUpkeep = 'roadUpkeep';
  static const pay = 'pay', contract = 'contract', xp = 'xp';
  static const handling = 'handling';

  /// Warehouses: how many may stand, extra room in each, modes.
  static const warehouses = 'warehouses', storage = 'storage';
  static const autoSupply = 'autoSupply', distribute = 'distribute';

  /// Horses: their own pace and load (motor bonuses do not apply), and
  /// motor vehicles themselves (era III) in new games.
  static const horseSpeed = 'horseSpeed', horseCapacity = 'horseCapacity';
  static const motors = 'motors';

  /// The automatic dispatcher (stage 3).
  static const dispatcher = 'dispatcher';

  /// Logistics centres the company may build (stage S7).
  static const logistics = 'logistics';
}

class MagTech {
  const MagTech({
    required this.id,
    required this.branch,
    required this.title,
    required this.lore,
    required this.effect,
    required this.effects,
    required this.cost,
    required this.level,
    this.requires = const [],
    this.deliveries = 0,
  });

  final String id;
  final MagBranch branch;
  final String title;

  /// A line about what it is, for the player.
  final String lore;

  /// What it changes, in words.
  final String effect;
  final Map<String, double> effects;
  final int cost;

  /// Company level needed.
  final int level;

  /// Earlier nodes needed.
  final List<String> requires;

  /// Deliveries the company must have made.
  final int deliveries;
}

abstract final class MagTechTree {
  static MagTech? byId(String id) => all.where((t) => t.id == id).firstOrNull;

  static Iterable<MagTech> of(MagBranch b) => all.where((t) => t.branch == b);

  static const all = magTechNodes;
}
