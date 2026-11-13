part of 'world.dart';

/// Logistics orders carried out by the existing trucks on the existing
/// roads: create (reserving cargo and room), assign a free truck, load,
/// carry, deliver (paid only then), finish; cancel or fail releases
/// everything. Route trucks are untouched, except that they no longer take
/// cargo reserved by an order.
extension MagWorldOrders on MagWorld {
  /// Stock a truck may still take (stock minus what orders hold).
  int availableOf(MagIndustry i, MagCargo c) =>
      (i.stock[c] ?? 0) - orders.reservedOut(i.id, c);

  /// Room left for [c] at [i] (null: it does not take it). Towns use up
  /// what they get, so they never fill; plants have an input store.
  int? roomOf(MagIndustry i, MagCargo c) {
    if (!i.spec.accepts.contains(c)) return null;
    if (i.spec.stores) return _warehouseRoom(i, c);
    if (!i.spec.converts.containsKey(c)) return 1 << 30;
    return MagRules.inputCap - (i.input[c] ?? 0) - orders.reservedIn(i.id, c);
  }

  /// A truck that may take an order: on no route and with no order.
  bool isFree(MagVehicle v) => v.routeId == null && v.orderId == null;

  /// Creates an order and reserves its cargo and room. Returns the error,
  /// or null (the order is then [MagOrderBook.orders].last).
  String? createOrder({
    required MagCargo cargo,
    required int from,
    required int to,
    required int amount,
    int priority = 1,
    String? tag,
  }) {
    final a = map.industry(from), b = map.industry(to);
    if (a == null || b == null) return 'Нет такого предприятия';
    if (from == to) return 'Поставщик и получатель совпадают';
    if (amount <= 0) return 'Количество должно быть больше нуля';
    if (priority < 0 || priority > 2) return 'Нет такого приоритета';
    if (!a.supplies.contains(cargo)) return '${a.name} не отгружает этот груз';
    final room = roomOf(b, cargo);
    if (room == null) return '${b.name} не принимает этот груз';
    if (amount > availableOf(a, cargo)) {
      return 'У поставщика свободно только ${math.max(0, availableOf(a, cargo))}';
    }
    if (amount > room) {
      return 'У получателя места только ${math.max(0, room)}';
    }
    if (tag != null && orders.hasDuplicate(tag, cargo, from, to)) {
      return 'Такая заявка уже есть';
    }
    orders.orders.add(
      MagOrder(
        id: nextId++,
        cargo: cargo,
        amount: amount,
        supplier: from,
        receiver: to,
        createdTick: tick,
        priority: priority,
        tag: tag,
      ),
    );
    return null;
  }

  /// Puts a free truck on a waiting order.
  String? assignOrder(int orderId, int vehicleId) {
    final o = orders.byId(orderId);
    final v = vehicles[vehicleId];
    if (o == null) return 'Нет такой заявки';
    if (v == null) return 'Нет такой машины';
    if (o.status != MagOrderStatus.pending) return 'Заявка уже в работе';
    if (!isFree(v)) return '${v.name} занят';
    if (capacityOf(v) < o.amount) {
      return '${v.name} возьмёт только ${capacityOf(v)} ед.';
    }
    o
      ..status = MagOrderStatus.assigned
      ..vehicle = v.id;
    v
      ..orderId = o.id
      ..state = MagVehicleState.noRoad
      ..wait = 0
      ..path = const []
      ..progress = 0;
    return null;
  }

  /// Cancels an order: cargo on board goes back to the supplier, the
  /// reservations end, the truck stops where it is.
  String? cancelOrder(int orderId) {
    final o = orders.byId(orderId);
    if (o == null) return 'Нет такой заявки';
    if (!o.status.active) return 'Заявка уже закрыта';
    if (o.status == MagOrderStatus.unloading) return 'Груз уже доставлен';
    _closeOrder(o, MagOrderStatus.cancelled);
    return null;
  }

  void _closeOrder(MagOrder o, MagOrderStatus status, [String? error]) {
    final v = o.vehicle == null ? null : vehicles[o.vehicle];
    if (v != null && v.orderId == o.id) {
      if (o.status.onBoard && v.load > 0) {
        final from = map.industry(o.supplier);
        if (from != null) {
          from.stock[v.cargo!] = (from.stock[v.cargo!] ?? 0) + v.load;
        } else {
          destroyed[v.cargo!] = (destroyed[v.cargo!] ?? 0) + v.load;
        }
        v
          ..load = 0
          ..cargo = null
          ..loadFrom = null;
      }
      v
        ..orderId = null
        ..path = const []
        ..pathIndex = 0
        ..progress = 0
        ..wait = 0
        ..state = v.onMap ? MagVehicleState.idle : MagVehicleState.garage;
    }
    o
      ..status = status
      ..error = error
      ..finishedTick = tick;
    orders.prune();
  }

  MagOrder? _orderOf(MagVehicle v) =>
      v.orderId == null ? null : orders.byId(v.orderId!);

  /// Where an order truck drives now.
  MagIndustry? _orderTarget(MagVehicle v) {
    final o = _orderOf(v);
    if (o == null || !o.status.active) return null;
    return map.industry(
      o.status == MagOrderStatus.inTransit ||
              o.status == MagOrderStatus.unloading
          ? o.receiver
          : o.supplier,
    );
  }

  /// Stop cells of every place next to [cell]: a truck standing at a
  /// place may leave by any road reaching it.
  List<int> _yardAround(int cell) {
    final out = <int>[];
    final x = cx(cell), y = cy(cell);
    for (var d = 0; d < 4; d++) {
      final i = map.industryAt(x + MagDir.dx[d], y + MagDir.dy[d]);
      if (i != null) out.addAll(accessCells(i));
    }
    return out;
  }

  /// Called when an order truck finds no road; fails after a few days.
  void _orderNoRoad(MagVehicle v) {
    final o = _orderOf(v);
    if (o == null) return;
    o.noRoadTicks += MagRules.retryTicks;
    if (o.noRoadTicks > MagRules.orderNoRoadDays * MagRules.ticksPerDay) {
      _closeOrder(o, MagOrderStatus.failed, 'Нет дороги');
    }
  }

  void _orderStarted(MagVehicle v) {
    final o = _orderOf(v);
    if (o != null && o.status == MagOrderStatus.assigned) {
      o.status = MagOrderStatus.toPickup;
    }
  }

  /// At the supplier: load the reserved cargo. At the receiver: deliver.
  void _orderArrive(MagVehicle v, MagIndustry here) {
    final o = _orderOf(v)!;
    v
      ..state = MagVehicleState.atStop
      ..wait = 0
      ..path = const []
      ..progress = 0;
    if (o.status.holdsSupply && here.id == o.supplier) {
      // Reserved stock moves onto the truck in one piece.
      here.stock[o.cargo] = (here.stock[o.cargo] ?? 0) - o.amount;
      v
        ..cargo = o.cargo
        ..load = o.amount
        ..loadFrom = here.id;
      o.status = MagOrderStatus.loading;
    } else if (o.status == MagOrderStatus.inTransit && here.id == o.receiver) {
      final before = v.income;
      _deliver(v, here);
      o
        ..income = v.income - before
        ..status = MagOrderStatus.unloading;
    }
  }

  void _orderAtStop(MagVehicle v) {
    final o = _orderOf(v);
    if (o == null) return;
    v.wait++;
    final dwell = math.max(
      MagRules.minStopTicks,
      (o.amount / handleRate).ceil(),
    );
    if (v.wait < dwell) return;
    if (o.status == MagOrderStatus.loading) {
      o.status = MagOrderStatus.inTransit;
      _plan(v);
    } else if (o.status == MagOrderStatus.unloading) {
      _closeOrder(o, MagOrderStatus.done);
    }
  }
}
