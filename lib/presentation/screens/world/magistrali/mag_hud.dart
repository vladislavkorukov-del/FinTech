import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_guide.dart';
import 'mag_route_map.dart';
import 'mag_art.dart';
import 'mag_build_panel.dart';
import 'mag_fleet.dart';
import 'mag_routes.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_tools.dart';
import 'mag_tech.dart';
import 'mag_topbar.dart';

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
  color: const Color(0xFFFFFFFF),
  borderRadius: BorderRadius.circular(r),
  boxShadow: const [
    BoxShadow(color: Color(0x0F10241C), spreadRadius: .5),
    BoxShadow(color: Color(0x14203A36), blurRadius: 18, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A203A36), blurRadius: 3, offset: Offset(0, 1)),
  ],
);

/// The build tools (when building), the confirm bar for a drawn road, and
/// the six sections of the game.
class MagBottomPanel extends StatelessWidget {
  const MagBottomPanel({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    final w = state.world;
    // Badges (S20+): idle vehicles, places with a problem, research the
    // company can afford now.
    final idle = w.vehicles.values
        .where((v) => v.routeId == null && v.orderId == null)
        .length;
    final problems = state.overlay.problems.length;
    final techs = MagTechTree.all
        .where(
          (t) =>
              !w.techs.contains(t.id) &&
              w.techBlocker(t) == null &&
              w.money >= w.techCost(t),
        )
        .length;
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
          if (state.tool == MagTool.route) ...[
            MagRouteBar(state: state),
            const SizedBox(height: 8),
          ] else if (state.tool != MagTool.view) ...[
            MagBuildPanel(state: state),
            const SizedBox(height: 8),
          ],
          magGlass(
            radius: 26,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                _nav(
                  'mag-tab-build',
                  Icons.add_road_rounded,
                  'Стройка',
                  state.tool != MagTool.view && state.tool != MagTool.route,
                  () => state.setTool(
                    state.tool == MagTool.view || state.tool == MagTool.route
                        ? MagTool.road
                        : MagTool.view,
                  ),
                ),
                _nav(
                  'mag-tab-fleet',
                  Icons.local_shipping_rounded,
                  'Транспорт',
                  false,
                  () => unawaited(showFleetSheet(state)),
                  badge: idle,
                ),
                _nav(
                  'mag-tab-routes',
                  Icons.alt_route_rounded,
                  'Маршруты',
                  state.tool == MagTool.route,
                  () => unawaited(showRoutesSheet(state)),
                ),
                _nav(
                  'mag-tab-places',
                  Icons.factory_rounded,
                  'Объекты',
                  false,
                  () => unawaited(showIndustriesSheet(state)),
                  badge: problems,
                ),
                _nav(
                  'mag-tab-upgrades',
                  Icons.rocket_launch_rounded,
                  'Развитие',
                  false,
                  () => unawaited(showTechSheet(state)),
                  badge: techs,
                  dot: true,
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
    VoidCallback tap, {
    int badge = 0,
    bool dot = false,
  }) => Expanded(
    child: MagPulse(
      active: state.guideKey == key,
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          state.sound.play('click', volume: .6);
          tap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: 44,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: on
                          ? const LinearGradient(
                              colors: [MagPalette.mint, MagPalette.teal],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      size: 21,
                      color: on ? Colors.white : MagPalette.ink,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: dot ? 4 : -2,
                      top: dot ? 1 : -4,
                      child: Container(
                        key: ValueKey('$key-badge'),
                        constraints: BoxConstraints(
                          minWidth: dot ? 9 : 17,
                          minHeight: dot ? 9 : 17,
                        ),
                        padding: dot
                            ? EdgeInsets.zero
                            : const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5484D),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: dot
                            ? null
                            : Text(
                                badge > 9 ? '9+' : '$badge',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  height: 1.1,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: on ? FontWeight.w900 : FontWeight.w600,
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
