import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_center.dart';
import 'mag_fleet.dart';
import 'mag_hud.dart';
import 'mag_routes.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_town.dart';
import 'mag_warehouse.dart';

/// Opens the sheet of a place, whatever it is.
Future<void> showPlaceSheet(MagistraliScreenState state, MagIndustry i) {
  state.centerOn(i.centerX, i.centerY);
  state.overlay.industry = i.id;
  return i.town != null
      ? showTownSheet(state, i.id)
      : i.spec.stores
      ? showWarehouseSheet(state, i.id)
      : i.kind == MagIndustryKind.logisticsCenter
      ? showCenterSheet(state, i.id)
      : showIndustrySheet(state, i.id);
}

IconData _icon(MagAdviceKind k) => switch (k) {
  MagAdviceKind.lossBusiness => Icons.trending_down_rounded,
  MagAdviceKind.noInput => Icons.hourglass_empty_rounded,
  MagAdviceKind.stockFull => Icons.inventory_2_rounded,
  MagAdviceKind.idleVehicle => Icons.local_parking_rounded,
  MagAdviceKind.lossRoute => Icons.money_off_rounded,
  MagAdviceKind.emptyRoute => Icons.swap_horiz_rounded,
  MagAdviceKind.warehouseFull => Icons.warehouse_rounded,
  MagAdviceKind.centerIdle => Icons.hub_rounded,
  MagAdviceKind.cityDemand => Icons.trending_up_rounded,
};

/// The finance centre's «Советы» tab: problems first, then chances.
List<Widget> adviceCards(MagistraliScreenState state, BuildContext context) {
  final w = state.world;
  final list = w.advice;
  if (list.isEmpty) {
    return const [
      Text(
        'Проблем не видно: машины заняты, склады не переполнены, предприятия в плюсе.',
        style: magMuted,
      ),
    ];
  }
  return [
    const Text(
      'Советы основаны на фактических показателях компании и не гарантируют прибыль. Коснитесь совета, чтобы перейти к объекту.',
      style: magMuted,
    ),
    const SizedBox(height: 8),
    for (final (k, a) in list.indexed)
      InkWell(
        key: ValueKey('mag-advice-$k'),
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pop(context);
          if (a.place != null) {
            final i = w.map.industry(a.place!);
            if (i != null) unawaited(showPlaceSheet(state, i));
          } else if (a.vehicle != null) {
            unawaited(showVehicleSheet(state, a.vehicle!));
          } else if (a.route != null) {
            unawaited(showRoutesSheet(state));
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: magCard(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _icon(a.kind),
                color: a.kind == MagAdviceKind.cityDemand
                    ? MagPalette.teal
                    : const Color(0xFFD64B5C),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(a.detail, style: magMuted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
  ];
}
