import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_company.dart';
import 'mag_finance.dart';
import 'mag_guide.dart';
import 'mag_art.dart';
import 'mag_screen.dart';
import 'mag_tools.dart';

import 'mag_hud.dart';

/// Frosted glass under the HUD (S20+): the map shows through, softly.
Widget magGlass({
  required Widget child,
  double radius = 22,
  EdgeInsets padding = EdgeInsets.zero,
  Key? key,
}) => ClipRRect(
  key: key,
  borderRadius: BorderRadius.circular(radius),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xD9FFFFFF),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x99FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F10241C),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    ),
  ),
);

/// Balance (counted up as it changes) with the day's result, the day and
/// the level, game speed, settings; under it the task as a slim pill and
/// the latest message (S20+).
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
        final dayOfMonth = w.day % MagRules.daysPerMonth + 1;
        final perDay = (w.month.totalIncome / dayOfMonth).round();
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
                  child: magGlass(
                    radius: 24,
                    padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            key: const ValueKey('mag-balance'),
                            onTap: () => unawaited(showFinanceSheet(state)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const _Coin(),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(end: w.money.toDouble()),
                                        duration: const Duration(
                                          milliseconds: 450,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, v, _) => Text(
                                          magMoney(w.money),
                                          key: const ValueKey('mag-money'),
                                          semanticsLabel: magMoney(w.money),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            height: 1.1,
                                            fontWeight: FontWeight.w900,
                                            color: w.money < 0
                                                ? const Color(0xFFD64B5C)
                                                : Color.lerp(
                                                    MagPalette.ink,
                                                    MagPalette.mint,
                                                    ((w.money - v).abs() / 400)
                                                        .clamp(0, .8),
                                                  ),
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '+${magMoney(perDay)} / день',
                                  key: const ValueKey('mag-per-day'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: MagPalette.teal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          key: const ValueKey('mag-level'),
                          onTap: () => unawaited(showCompanySheet(state)),
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(
                                    end: ((w.xp - from) / (to - from))
                                        .clamp(0, 1)
                                        .toDouble(),
                                  ),
                                  duration: const Duration(milliseconds: 600),
                                  builder: (context, v, _) =>
                                      CircularProgressIndicator(
                                        value: v,
                                        strokeWidth: 3.4,
                                        strokeCap: StrokeCap.round,
                                        backgroundColor: const Color(
                                          0x222BB59A,
                                        ),
                                        color: MagPalette.mint,
                                      ),
                                ),
                                Text(
                                  '$lvl',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
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
            if (state.tool == MagTool.view &&
                (task != null || w.livingWorld)) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (task != null)
                    Flexible(
                      child: GestureDetector(
                        onTap: () => state.toggleTask(),
                        child: magGlass(
                          key: ValueKey('mag-task-${task.id}'),
                          radius: 18,
                          padding: const EdgeInsets.fromLTRB(6, 5, 12, 6),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        MagPalette.mint,
                                        MagPalette.teal,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.flag_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${task.title} · +${magMoney(task.reward)}',
                                        maxLines: state.taskFolded ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
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
                      ),
                    ),
                  // S22: the season and today's weather.
                  if (w.livingWorld) ...[
                    const SizedBox(width: 6),
                    magGlass(
                      key: const ValueKey('mag-weather'),
                      radius: 18,
                      padding: const EdgeInsets.fromLTRB(9, 6, 11, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            switch (w.weather) {
                              MagWeather.clear =>
                                w.season == MagSeason.winter
                                    ? Icons.ac_unit_rounded
                                    : Icons.wb_sunny_rounded,
                              MagWeather.rain => Icons.water_drop_rounded,
                              MagWeather.snow => Icons.ac_unit_rounded,
                              MagWeather.fog => Icons.foggy,
                              MagWeather.storm => Icons.thunderstorm_rounded,
                            },
                            size: 15,
                            color: MagPalette.teal,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${MagWorldSeasons.seasonName(w.season)} · ${MagWorldSeasons.weatherName(w.weather)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: MagPalette.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
            // Messages slide in under the bar, never over the middle of
            // the map; while building they go to the build panel.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, -.4),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: state.message != null && state.tool == MagTool.view
                  ? Padding(
                      key: ValueKey(state.message),
                      padding: const EdgeInsets.only(top: 6),
                      child: MagToast(text: state.message!),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

/// A gold coin: the game's money.
class _Coin extends StatelessWidget {
  const _Coin();

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE08A), Color(0xFFE2A82E)],
      ),
      boxShadow: [BoxShadow(color: Color(0x40B8860B), blurRadius: 4)],
    ),
    child: const Icon(Icons.toll_rounded, size: 12, color: Color(0xFF9A6B10)),
  );
}

Widget _round(String key, IconData icon, VoidCallback onTap) => magGlass(
  radius: 24,
  child: Material(
    type: MaterialType.transparency,
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
                  width: 25,
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
