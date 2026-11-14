import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_finance.dart';
import 'mag_guide.dart';
import 'mag_art.dart';
import 'mag_build_panel.dart';
import 'mag_fleet.dart';
import 'mag_routes.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_tools.dart';
import 'mag_tech.dart';

/// Credits as people read them: 12 345.
String magMoney(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '−' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

BoxDecoration magCard([double r = 18]) => BoxDecoration(
  color: MagPalette.card,
  borderRadius: BorderRadius.circular(r),
  boxShadow: const [
    BoxShadow(color: Color(0x22203A36), blurRadius: 14, offset: Offset(0, 4)),
  ],
);

/// Balance, level and experience, game speed, settings; the current task.
class MagTopBar extends StatelessWidget {
  const MagTopBar({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: state.ticks,
      builder: (context, _, _) {
        final w = state.world;
        final lvl = w.level;
        final from = MagWorldProgress.xpFor(lvl);
        final to = MagWorldProgress.xpFor(lvl + 1);
        final task = w.currentTask;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _round(
                  'mag-back',
                  Icons.arrow_back_rounded,
                  () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: magCard(23),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            key: const ValueKey('mag-balance'),
                            onTap: () => unawaited(showFinanceSheet(state)),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.toll_rounded,
                                  size: 18,
                                  color: MagPalette.mint,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    magMoney(w.money),
                                    key: const ValueKey('mag-money'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: w.money < 0
                                          ? const Color(0xFFD64B5C)
                                          : MagPalette.ink,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          key: const ValueKey('mag-level'),
                          onTap: () => unawaited(showCompanySheet(state)),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: ((w.xp - from) / (to - from)).clamp(
                                    0,
                                    1,
                                  ),
                                  strokeWidth: 3,
                                  backgroundColor: const Color(0x222BB59A),
                                  color: MagPalette.mint,
                                ),
                                Text(
                                  '$lvl',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: MagPalette.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Speed(state: state),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _round(
                  'mag-settings',
                  Icons.settings_rounded,
                  () => unawaited(showSettingsSheet(state)),
                ),
              ],
            ),
            if (task != null && state.tool == MagTool.view) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => state.toggleTask(),
                child: Container(
                  key: ValueKey('mag-task-${task.id}'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                  decoration: magCard(16),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0x1F2BB59A),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${task.id}',
                          style: const TextStyle(
                            color: MagPalette.teal,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${task.title} · +${magMoney(task.reward)} кр',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: MagPalette.ink,
                              ),
                            ),
                            if (!state.taskFolded)
                              Text(
                                task.hint,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF52646A),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

Widget _round(String key, IconData icon, VoidCallback onTap) => Material(
  color: MagPalette.card,
  shape: const CircleBorder(),
  elevation: 2,
  shadowColor: const Color(0x33203A36),
  child: InkWell(
    key: ValueKey(key),
    customBorder: const CircleBorder(),
    onTap: onTap,
    child: SizedBox(
      width: 46,
      height: 46,
      child: Icon(icon, color: MagPalette.ink, size: 22),
    ),
  ),
);

class _Speed extends StatelessWidget {
  const _Speed({required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final w = state.world;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0x142BB59A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in const [0, 1, 2, 4])
            MagPulse(
              active: state.guideKey == 'mag-speed-$s',
              radius: 10,
              child: GestureDetector(
                key: ValueKey('mag-speed-$s'),
                onTap: () {
                  w.speed = s;
                  state.changed();
                },
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: w.speed == s ? MagPalette.mint : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: s == 0
                      ? Icon(
                          Icons.pause_rounded,
                          size: 16,
                          color: w.speed == s ? Colors.white : MagPalette.ink,
                        )
                      : Text(
                          '$s×',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: w.speed == s ? Colors.white : MagPalette.ink,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The build tools (when building), the confirm bar for a drawn road, and
/// the six sections of the game.
class MagBottomPanel extends StatelessWidget {
  const MagBottomPanel({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    final road = state.pendingRoad;
    final removing = state.pendingRemove;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, pad + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (road != null && road.cells.isNotEmpty ||
              removing.isNotEmpty ||
              state.pendingWarehouse != null ||
              state.pendingIndustry != null ||
              state.pendingStation != null ||
              state.pendingPort != null) ...[
            MagConfirmBar(state: state),
            const SizedBox(height: 8),
          ],
          if (state.tool != MagTool.view) ...[
            MagBuildPanel(state: state),
            const SizedBox(height: 8),
          ],
          Container(
            decoration: magCard(22),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                _nav(
                  'mag-tab-build',
                  Icons.add_road_rounded,
                  'Стройка',
                  state.tool != MagTool.view,
                  () => state.setTool(
                    state.tool == MagTool.view ? MagTool.road : MagTool.view,
                  ),
                ),
                _nav(
                  'mag-tab-fleet',
                  Icons.local_shipping_rounded,
                  'Транспорт',
                  false,
                  () => unawaited(showFleetSheet(state)),
                ),
                _nav(
                  'mag-tab-routes',
                  Icons.alt_route_rounded,
                  'Маршруты',
                  false,
                  () => unawaited(showRoutesSheet(state)),
                ),
                _nav(
                  'mag-tab-places',
                  Icons.factory_rounded,
                  'Объекты',
                  false,
                  () => unawaited(showIndustriesSheet(state)),
                ),
                _nav(
                  'mag-tab-upgrades',
                  Icons.rocket_launch_rounded,
                  'Развитие',
                  false,
                  () => unawaited(showTechSheet(state)),
                ),
                _nav(
                  'mag-tab-contracts',
                  Icons.assignment_rounded,
                  'Контракты',
                  false,
                  () => unawaited(showContractsSheet(state)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav(
    String key,
    IconData icon,
    String label,
    bool on,
    VoidCallback tap,
  ) => Expanded(
    child: MagPulse(
      active: state.guideKey == key,
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(14),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: on ? MagPalette.mint : MagPalette.ink,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  color: on ? MagPalette.teal : MagPalette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
