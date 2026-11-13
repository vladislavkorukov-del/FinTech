import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';

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
    final String title;
    String? problem;
    if (road != null && road.cells.isNotEmpty) {
      final cost = road.cost;
      title =
          '${roadName(road.type)} · ${road.cells.length} кл. · ${magMoney(cost)} кр';
      problem =
          road.error ??
          (cost == 0
              ? 'Здесь уже есть такая дорога'
              : cost > w.money
              ? 'Не хватает ${magMoney(cost - w.money)} кр'
              : null);
    } else {
      title = 'Снести ${state.pendingRemove.length} кл. дороги';
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
                  backgroundColor: road == null
                      ? const Color(0xFFE0566B)
                      : MagPalette.mint,
                ),
                onPressed: problem == null ? state.confirmPending : null,
                child: Text(road == null ? 'Снести' : 'Построить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
