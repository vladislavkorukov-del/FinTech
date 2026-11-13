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
  });
  final int id;
  final MagCargo cargo;
  final int to;
  final int amount, reward, xp;
  int delivered;
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
