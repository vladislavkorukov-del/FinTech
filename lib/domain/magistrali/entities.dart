import 'config.dart';

enum MagVehicleState {
  /// Bought, not on a route.
  garage,

  /// Driving to its next stop.
  driving,

  /// At a stop: unloading, loading or waiting for cargo.
  atStop,

  /// No road leads to the next stop; tries again soon.
  noRoad,

  /// On the map with nothing to do (after an order); waits for the next.
  idle,
}

/// How a warehouse keeps one cargo.
enum MagStockMode {
  /// Only what routes and the player bring and take.
  manual,

  /// Orders more when below the minimum, up to the target.
  autoSupply,

  /// Sends what is above the target to places that use it.
  distribute,
}

class MagStockRule {
  MagStockRule({
    this.mode = MagStockMode.manual,
    this.min = 0,
    this.target = 0,
    this.max,
    this.priority = 1,
  });
  final MagStockMode mode;
  final int min, target;

  /// Most of this cargo the warehouse holds (null: the whole warehouse).
  final int? max;

  /// 0 low, 1 normal, 2 high (passed to the orders it writes).
  final int priority;

  MagStockRule copyWith({
    MagStockMode? mode,
    int? min,
    int? target,
    int? max,
    bool clearMax = false,
    int? priority,
  }) => MagStockRule(
    mode: mode ?? this.mode,
    min: min ?? this.min,
    target: target ?? this.target,
    max: clearMax ? null : max ?? this.max,
    priority: priority ?? this.priority,
  );
}

class MagVehicle {
  MagVehicle({required this.id, required this.model, required this.name});
  final int id;
  final String model;
  String name;

  /// Levels of [MagUpgrade] lines, 0..[MagRules.maxUpgrade].
  final List<int> upgrades = [0, 0, 0, 0];

  /// Wear in percent (0 new, 100 worn out).
  double wear = 0;
  double odometer = 0;
  int income = 0, trips = 0;

  /// Credits spent on its upgrades (part of its value).
  int upgradeSpent = 0;

  int? routeId;

  /// The logistics order it carries out (never together with a route).
  int? orderId;

  /// In the automatic fleet: the dispatcher gives it orders (stage 3).
  bool auto = false;

  /// Index of the stop it drives to or stands at.
  int stop = 0;
  MagVehicleState state = MagVehicleState.garage;

  MagCargo? cargo;
  int load = 0;

  /// Where the cargo on board was loaded (pay distance, and where it goes
  /// back if the truck leaves its route).
  int? loadFrom;

  /// Cell it stands on or drives from (−1 in the garage).
  int cell = -1;
  List<int> path = const [];
  int pathIndex = 0;
  double progress = 0;

  /// Direction of travel (see MagDir).
  int dir = 1;

  /// Ticks at the stop, or until the next try when there is no road.
  int wait = 0;

  /// Running cost not yet charged (fractions of a credit).
  double unpaid = 0;

  /// Wagons behind a locomotive (stage S8; 0 for road vehicles).
  int wagons = 0;

  /// Ticks a train has waited for the track ahead to clear, and how many
  /// times it gave way head to head (a sign the line needs a second track).
  int blocked = 0, yields = 0;

  /// Money it has cost (fuel or feed, upkeep, repairs) and cells driven
  /// empty — for the finance centre.
  int costs = 0;
  double emptyCells = 0;

  MagTruckModel get spec => MagRules.truck(model)!;
  int level(MagUpgrade u) => upgrades[u.index];
  bool get onMap => cell >= 0;
}

class MagRoute {
  MagRoute({required this.id, required this.name, required this.stops});
  final int id;
  String name;

  /// Industry ids in order; the line runs round in a loop.
  final List<int> stops;

  /// Credits earned by its deliveries.
  int income = 0;
  int deliveries = 0;

  /// What its vehicles cost while on it (fuel or feed, upkeep, repairs),
  /// and cells they drove on it, empty and in all (ROUTE-11, ROUTE-14).
  int costs = 0;
  int cells = 0, emptyCells = 0;

  int get profit => income - costs;

  /// Share of the distance driven empty (null: not driven yet).
  double? get emptyShare => cells == 0 ? null : emptyCells / cells;
}

class MagContract {
  MagContract({
    required this.id,
    required this.cargo,
    required this.to,
    required this.amount,
    required this.reward,
    required this.xp,
    this.delivered = 0,
    this.deadline,
  });
  final int id;
  final MagCargo cargo;
  final int to;
  final int amount, reward, xp;
  int delivered;

  /// A city order: the tick by which it must be done (null: no deadline).
  final int? deadline;
  bool get done => delivered >= amount;
}

/// Money of one game month by category.
class MagMonth {
  MagMonth(this.index);
  final int index;
  final Map<String, int> income = {}, expense = {};
  int deliveries = 0;

  int get totalIncome => income.values.fold(0, (a, b) => a + b);
  int get totalExpense => expense.values.fold(0, (a, b) => a + b);
  int get profit => totalIncome - totalExpense;
}

/// A step of the guided start.
class MagTask {
  const MagTask(this.id, this.title, this.hint, this.reward, this.xp);
  final int id;
  final String title, hint;
  final int reward, xp;
}
