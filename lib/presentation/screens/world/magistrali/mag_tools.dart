import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_lore.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

String roadName(MagRoad r) => switch (r) {
  MagRoad.dirt => 'Грунтовая',
  MagRoad.asphalt => 'Асфальт',
  MagRoad.highway => 'Шоссе',
  MagRoad.motorway => 'Магистраль',
  MagRoad.none => '',
};

Color roadColor(MagRoad r) => switch (r) {
  MagRoad.dirt => const Color(0xFFC49A62),
  MagRoad.asphalt => const Color(0xFF5E666C),
  MagRoad.highway => const Color(0xFFE0B83E),
  _ => const Color(0xFF3F464C),
};

class MagToolChip extends StatelessWidget {
  const MagToolChip({
    super.key,
    required this.label,
    required this.on,
    required this.color,
    required this.onTap,
    this.locked = false,
    this.lockLevel = 0,
    this.icon,
  });
  final String label;
  final bool on, locked;
  final int lockLevel;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? const Color(0x1F2BB59A) : const Color(0x0A233238),
          border: Border.all(
            color: on ? MagPalette.mint : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked)
              const Icon(Icons.lock_rounded, size: 14, color: Color(0xFF8A9599))
            else if (icon != null)
              Icon(icon, size: 16, color: color)
            else
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              locked ? '$label · ур. $lockLevel' : label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: locked ? const Color(0xFF8A9599) : MagPalette.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MagConfirmBar extends StatelessWidget {
  const MagConfirmBar({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final w = state.world;
    final road = state.pendingRoad;
    final wh = state.pendingWarehouse;
    final at = state.pendingIndustry, kind = state.buildKind;
    final st = state.pendingStation, place = state.pendingStationPlace;
    final removing =
        wh == null &&
        at == null &&
        st == null &&
        (road == null || road.cells.isEmpty);
    final String title;
    String? problem;
    if (st != null && place != null) {
      title =
          'Станция у «${w.map.industry(place)?.name ?? ''}» · ${magMoney(MagRules.stationPrice)} кр';
      problem =
          w.stationBlocker(st, place) ??
          (MagRules.stationPrice > w.money ? 'Не хватает кредитов' : null);
    } else if (at != null && kind != null) {
      title = '${kindName(kind)} · ${magMoney(w.buildPrice(kind))} кр';
      problem =
          w.buildBlocker(kind, w.cx(at), w.cy(at)) ??
          (w.buildPrice(kind) > w.money ? 'Не хватает кредитов' : null);
    } else if (wh != null) {
      title = 'Склад · ${magMoney(w.warehousePrice)} кр';
      problem =
          w.warehouseBlocker(w.cx(wh), w.cy(wh)) ??
          (w.warehousePrice > w.money ? 'Не хватает кредитов' : null);
    } else if (road != null && road.cells.isNotEmpty) {
      final cost = road.cost;
      title = road.type == MagRoad.none
          ? 'Ж/д путь · ${road.cells.length} кл. · ${magMoney(cost)} кр'
          : '${roadName(road.type)} · ${road.cells.length} кл. · ${magMoney(cost)} кр';
      problem =
          road.error ??
          (cost == 0
              ? 'Здесь уже есть такая дорога'
              : cost > w.money
              ? 'Не хватает ${magMoney(cost - w.money)} кр'
              : null);
    } else {
      title = 'Снести ${state.pendingRemove.length} кл.';
    }
    return Container(
      key: const ValueKey('mag-confirm'),
      decoration: magCard(),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: MagPalette.ink,
                ),
              ),
              if (problem != null)
                Text(
                  problem,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFD64B5C),
                  ),
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('mag-cancel'),
                onPressed: state.cancelPending,
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const ValueKey('mag-confirm-build'),
                style: FilledButton.styleFrom(
                  backgroundColor: removing
                      ? const Color(0xFFE0566B)
                      : MagPalette.mint,
                ),
                onPressed: problem == null ? state.confirmPending : null,
                child: Text(removing ? 'Снести' : 'Построить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showSettingsSheet(MagistraliScreenState state) => magSheet(
  state,
  'mag-settings',
  (context) {
    final w = state.world;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Настройки игры', style: magTitle),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: w.autoService,
          activeThumbColor: MagPalette.mint,
          title: const Text('Автоматический ремонт'),
          subtitle: const Text(
            'Машины с износом от 50% чинятся на остановках',
            style: magMuted,
          ),
          onChanged: (v) {
            w.autoService = v;
            state.changed();
          },
        ),
        const SizedBox(height: 6),
        const Text(
          'Игра сохраняется сама. Пока игра закрыта, компания не работает.',
          style: magMuted,
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const ValueKey('mag-new-game'),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Начать заново?'),
                content: const Text(
                  'Текущая компания будет удалена. Полученные искры останутся.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('Начать'),
                  ),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              Navigator.pop(context);
              await state.restart();
            }
          },
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Новая компания на новой карте'),
        ),
      ],
    );
  },
);

/// A short message over the map.
class MagToast extends StatelessWidget {
  const MagToast({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        key: const ValueKey('mag-message'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: MagPalette.ink.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    ),
  );
}

/// The line under the build tools: what the chosen tool does and costs.
String toolHint(MagistraliScreenState state) {
  final w = state.world;
  return switch (state.tool) {
    MagTool.road =>
      '${roadLore(state.roadType)} Проведите пальцем · ${MagRules.roads[state.roadType]!.cost} кр/кл.',
    MagTool.industry =>
      'Коснитесь клетки — там встанет ${state.buildKind == null ? 'предприятие' : kindName(state.buildKind!).toLowerCase()} (${state.buildKind == null ? '' : '${magMoney(w.buildPrice(state.buildKind!))} кр'})',
    MagTool.warehouse =>
      'Коснитесь клетки — там встанет склад 2×2 (${magMoney(w.warehousePrice)} кр, ${w.warehouses.length} из ${w.warehouseSlots})',
    MagTool.rail =>
      'Рельсы: проведите пальцем · ${MagRules.railCost} кр/кл. Можно пересекать дороги.',
    MagTool.station =>
      'Коснитесь пути рядом (до 2 клеток) с предприятием или поселением · ${magMoney(MagRules.stationPrice)} кр',
    _ => 'Проведите по дороге или пути, которые нужно снести',
  };
}

/// The railway tools (stage S8): track and station.
List<Widget> railChips(MagistraliScreenState state) {
  final w = state.world;
  return [
    MagToolChip(
      key: const ValueKey('mag-tool-rail'),
      label: 'Ж/д путь',
      locked: !w.railsUnlocked,
      lockLevel: 6,
      on: state.tool == MagTool.rail,
      color: const Color(0xFF6E4E35),
      icon: Icons.linear_scale_rounded,
      onTap: () => w.railsUnlocked
          ? state.setTool(MagTool.rail)
          : state.say('Железные дороги открывает технология «Паровая тяга»'),
    ),
    MagToolChip(
      key: const ValueKey('mag-tool-station'),
      label: 'Станция',
      locked: !w.railsUnlocked,
      lockLevel: 6,
      on: state.tool == MagTool.station,
      color: const Color(0xFF6E4E35),
      icon: Icons.train_rounded,
      onTap: () => w.railsUnlocked
          ? state.setTool(MagTool.station)
          : state.say('Станции открывает технология «Паровая тяга»'),
    ),
  ];
}
