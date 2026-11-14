import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_sheets.dart';

/// The city part of a settlement's sheet: its specialization and what it
/// pays more for, the demand of the week, its order. Before level 4: what
/// it will become, judging by what the company brings.
List<Widget> cityInfo(MagWorld w, MagIndustry i) {
  final t = i.town!;
  final spec = MagTowns.specializationName(t.specialization).toLowerCase();
  String names(Iterable<MagCargo> list) =>
      list.map((c) => cargoName(c).toLowerCase()).join(', ');
  if (!w.isCity(i)) {
    final next = MagTowns.specializationFor(t.received);
    return [
      const SizedBox(height: 10),
      const Text(
        'Будущий город',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      Text(
        next == null
            ? 'На ${MagTowns.cityLevel} уровне поселение станет городом и выберет специализацию по тому, что вы привозите чаще всего.'
            : 'На ${MagTowns.cityLevel} уровне станет городом. Сейчас больше всего привозят то, что ценит ${MagTowns.specializationName(next).toLowerCase()} город (${names(MagTowns.favoured(next))}).',
        key: const ValueKey('mag-town-future'),
        style: magMuted,
      ),
    ];
  }
  final demand = w.weeklyDemand(i);
  final order = w.cityOrders.where((c) => c.to == i.id).firstOrNull;
  final wait = ((t.orderAt - w.tick) / MagRules.ticksPerDay).ceil();
  return [
    const SizedBox(height: 10),
    Text(
      'Специализация: $spec город',
      key: const ValueKey('mag-town-specialization'),
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    Text(
      'Платит на ${(MagTowns.favouredBonus * 100).round()}% больше за: ${names(MagTowns.favoured(t.specialization))}'
      '${t.specialization == MagSpecialization.trade ? ' и на ${(MagTowns.tradeBonus * 100).round()}% больше за всё' : ''}.',
      style: magMuted,
    ),
    if (demand != null)
      magRow(
        'Спрос недели: ${cargoName(demand)}',
        '+${(MagTowns.weeklyBonus * 100).round()}% · ещё ${w.weekDaysLeft} дн.',
        color: MagPalette.teal,
      ),
    if (order != null)
      magRow(
        'Городской заказ: ${cargoName(order.cargo)} ${order.delivered}/${order.amount}',
        '+${magMoney(order.reward)} кр · ${((order.deadline! - w.tick) / MagRules.ticksPerDay).ceil()} дн.',
        color: MagPalette.teal,
      )
    else
      magRow(
        'Городской заказ',
        wait > 0 ? 'новый через $wait дн.' : 'появится завтра',
      ),
  ];
}
