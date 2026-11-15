import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_orders.dart' show orderStatusName;

String stateName(MagWorld w, MagVehicle v) {
  final r = w.routes[v.routeId];
  final o = v.orderId == null ? null : w.orders.byId(v.orderId!);
  if (o != null) {
    return 'Заказ №${o.id}: ${orderStatusName(o.status).toLowerCase()}';
  }
  return switch (v.state) {
    MagVehicleState.idle =>
      v.auto ? 'Автопарк: ждёт заявку' : 'Свободен, ждёт заказ',
    MagVehicleState.garage => 'В гараже',
    MagVehicleState.noRoad =>
      v.spec.rail
          ? 'Ждёт свободный путь или станцию'
          : v.spec.water
          ? 'Нет водного пути до порта'
          : 'Нет дороги до остановки',
    MagVehicleState.driving =>
      'Едет: ${w.map.industry(r?.stops[v.stop % r.stops.length] ?? -1)?.name ?? ''}',
    MagVehicleState.atStop => v.load > 0 ? 'Загружается' : 'Ждёт груз',
  };
}

String upgradeName(MagUpgrade u, [bool horse = false]) => horse
    ? switch (u) {
        MagUpgrade.engine => 'Порода лошадей',
        MagUpgrade.body => 'Повозка побольше',
        MagUpgrade.economy => 'Корм и упряжь',
        MagUpgrade.reliability => 'Подковы и колёса',
      }
    : switch (u) {
        MagUpgrade.engine => 'Двигатель',
        MagUpgrade.body => 'Кузов',
        MagUpgrade.economy => 'Экономичность',
        MagUpgrade.reliability => 'Надёжность',
      };

IconData upgradeIcon(MagUpgrade u) => switch (u) {
  MagUpgrade.engine => Icons.speed_rounded,
  MagUpgrade.body => Icons.inventory_2_rounded,
  MagUpgrade.economy => Icons.local_gas_station_rounded,
  MagUpgrade.reliability => Icons.build_circle_rounded,
};
