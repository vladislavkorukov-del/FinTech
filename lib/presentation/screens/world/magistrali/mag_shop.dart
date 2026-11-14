import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_lore.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// A model in the transport shop: what it is, its numbers, and buying it
/// (or why not yet).
Widget shopCard(MagistraliScreenState state, MagTruckModel m) {
  final w = state.world;
  final open =
      w.level >= m.level &&
      (m.water
          ? w.shippingUnlocked && (m.id != 'freighter' || w.shipyardUnlocked)
          : m.rail
          ? w.railsUnlocked && (m.id != 'diesel' || w.dieselUnlocked)
          : m.horse || w.motorUnlocked) &&
      (m.tech == null || w.techs.contains(m.tech));
  return Container(
    key: ValueKey('mag-shop-${m.id}'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: magCard(16),
    child: Row(
      children: [
        Icon(
          m.water
              ? Icons.directions_boat_rounded
              : m.rail
              ? Icons.train_rounded
              : m.passengers
              ? Icons.directions_bus_rounded
              : m.horse
              ? Icons.agriculture_rounded
              : Icons.local_shipping_rounded,
          size: 34,
          color: open ? Color(m.color) : const Color(0xFFB6BEC1),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                m.rail
                    ? 'Скорость ${m.speed.toStringAsFixed(2)} · вагон ${m.wagonCapacity} ед., до ${m.maxWagons} вагонов · расход ${m.runningCost}/кл. + ${MagRules.wagonRunning} за вагон'
                    : 'Скорость ${m.speed.toStringAsFixed(2)} · груз ${m.capacity} · ${m.horse ? 'корм' : 'расход'} ${m.runningCost}/кл.',
                style: magMuted,
              ),
              const SizedBox(height: 2),
              if (m.tech != null && !w.techs.contains(m.tech))
                Text(
                  'Нужна технология «${MagTechTree.byId(m.tech!)?.title}»',
                  style: magMuted.copyWith(color: const Color(0xFFD64B5C)),
                ),
              Text(
                truckLore(m.id),
                style: magMuted.copyWith(
                  fontStyle: FontStyle.italic,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        FilledButton(
          key: ValueKey('mag-buy-${m.id}'),
          style: FilledButton.styleFrom(
            backgroundColor: MagPalette.mint,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: open
              ? () => state.report(
                  w.buyTruck(m.id),
                  'Куплен ${m.name} — назначьте его на маршрут',
                )
              : null,
          child: Text(
            open
                ? magMoney(m.price + m.wagonPrice)
                : w.level < m.level
                ? 'ур. ${m.level}'
                : m.rail || m.water || m.tech != null
                ? 'техн.'
                : 'мотор',
          ),
        ),
      ],
    ),
  );
}
