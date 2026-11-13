import 'config.dart';

/// Life of a logistics order, in order.
enum MagOrderStatus {
  /// Created; cargo and room are reserved, no truck yet.
  pending,

  /// A truck is chosen.
  assigned,

  /// The truck drives to the supplier.
  toPickup,

  /// Loading at the supplier.
  loading,

  /// Driving to the receiver.
  inTransit,

  /// Unloading at the receiver (already delivered and paid).
  unloading,

  /// Done.
  done,

  /// Cancelled by the player; everything reserved was released.
  cancelled,

  /// Could not be carried out (no road for too long, a place vanished).
  failed,
}

extension MagOrderStatusX on MagOrderStatus {
  bool get active =>
      this != MagOrderStatus.done &&
      this != MagOrderStatus.cancelled &&
      this != MagOrderStatus.failed;

  /// Still holds cargo in the supplier's stock (not loaded yet).
  bool get holdsSupply =>
      this == MagOrderStatus.pending ||
      this == MagOrderStatus.assigned ||
      this == MagOrderStatus.toPickup;

  /// Still holds room at the receiver (not delivered yet).
  bool get holdsRoom => active && this != MagOrderStatus.unloading;

  /// Cargo is on the truck.
  bool get onBoard =>
      this == MagOrderStatus.loading || this == MagOrderStatus.inTransit;
}

/// A request to carry [amount] of [cargo] from [supplier] to [receiver].
class MagOrder {
  MagOrder({
    required this.id,
    required this.cargo,
    required this.amount,
    required this.supplier,
    required this.receiver,
    required this.createdTick,
    this.priority = 1,
    this.tag,
    this.status = MagOrderStatus.pending,
  });

  final int id;
  final MagCargo cargo;
  final int amount;

  /// Industry ids.
  final int supplier, receiver;

  /// 0 low, 1 normal, 2 high.
  final int priority;
  final int createdTick;

  /// Who made it (e.g. a warehouse rule); two active orders with the same
  /// tag, cargo and places are refused.
  final String? tag;

  MagOrderStatus status;

  /// The truck carrying it out.
  int? vehicle;
  int? finishedTick;

  /// Why it failed.
  String? error;

  /// Ticks spent without a road (it fails after a while).
  int noRoadTicks = 0;

  /// Credits its delivery earned.
  int income = 0;

  /// Units of the supplier's stock it holds now.
  int get reserved => status.holdsSupply ? amount : 0;

  /// Units of room at the receiver it holds now.
  int get reservedRoom => status.holdsRoom ? amount : 0;
}

/// All orders and what they hold. Reservations are never stored on their
/// own: they are always summed from the orders, so they cannot drift from
/// what the orders say.
class MagOrderBook {
  final orders = <MagOrder>[];

  /// Finished orders kept for the history.
  static const history = 30;

  Iterable<MagOrder> get active => orders.where((o) => o.status.active);

  MagOrder? byId(int id) => orders.where((o) => o.id == id).firstOrNull;

  MagOrder? ofVehicle(int vehicle) =>
      active.where((o) => o.vehicle == vehicle).firstOrNull;

  /// Stock of [industry] held by orders not loaded yet.
  int reservedOut(int industry, MagCargo c) {
    var n = 0;
    for (final o in orders) {
      if (o.supplier == industry && o.cargo == c) n += o.reserved;
    }
    return n;
  }

  /// Room at [industry] held by orders not delivered yet (also cargo on
  /// its way there).
  int reservedIn(int industry, MagCargo c) {
    var n = 0;
    for (final o in orders) {
      if (o.receiver == industry && o.cargo == c) n += o.reservedRoom;
    }
    return n;
  }

  bool hasDuplicate(String tag, MagCargo c, int supplier, int receiver) =>
      active.any(
        (o) =>
            o.tag == tag &&
            o.cargo == c &&
            o.supplier == supplier &&
            o.receiver == receiver,
      );

  /// Drops the oldest finished orders beyond [history].
  void prune() {
    final finished = orders.where((o) => !o.status.active).toList();
    if (finished.length <= history) return;
    finished.sort(
      (a, b) => (a.finishedTick ?? 0).compareTo(b.finishedTick ?? 0),
    );
    for (final o in finished.take(finished.length - history)) {
      orders.remove(o);
    }
  }
}
