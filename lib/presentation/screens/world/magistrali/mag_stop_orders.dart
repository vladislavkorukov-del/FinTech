import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_sheets.dart';

/// What to do at one stop of a line (S13): load only [pick], load nothing,
/// keep the load. All off: the stop works by itself.
class StopOrder {
  const StopOrder({this.pick, this.noPick = false, this.noDrop = false});
  final MagCargo? pick;
  final bool noPick, noDrop;

  bool get auto => pick == null && !noPick && !noDrop;

  static StopOrder of(MagRoute r, int k) => StopOrder(
    pick: r.pickAt[k],
    noPick: r.noPick.contains(k),
    noDrop: r.noDrop.contains(k),
  );
}

/// The steps of a line in words: at each stop, what is unloaded and what
/// is loaded — «1. Лесозаготовка: забрать древесину», «2. Лесопилка:
/// выгрузить древесину, забрать доски».
List<String> routeSteps(MagWorld w, List<int> stops, List<StopOrder> orders) {
  StopOrder at(int k) => k < orders.length ? orders[k] : const StopOrder();
  final picks = <int, Set<MagCargo>>{};
  for (var k = 0; k < stops.length; k++) {
    final here = w.map.industry(stops[k])!;
    final o = at(k);
    final wanted = <MagCargo>{
      for (var j = 0; j < stops.length; j++)
        if (stops[j] != here.id && !at(j).noDrop)
          ...w.map.industry(stops[j])!.accepts,
    };
    picks[k] = o.noPick
        ? {}
        : {
            for (final c in here.supplies)
              if (wanted.contains(c) && (o.pick == null || o.pick == c)) c,
          };
  }
  final carried = {for (final s in picks.values) ...s};
  String names(Iterable<MagCargo> list) =>
      list.map((c) => cargoName(c).toLowerCase()).join(', ');
  return [
    for (var k = 0; k < stops.length; k++)
      () {
        final here = w.map.industry(stops[k])!;
        final drop = at(k).noDrop
            ? const <MagCargo>[]
            : [
                for (final c in carried)
                  if (here.accepts.contains(c) && !picks[k]!.contains(c)) c,
              ];
        final parts = [
          if (drop.isNotEmpty) 'выгрузить ${names(drop)}',
          if (picks[k]!.isNotEmpty) 'забрать ${names(picks[k]!)}',
        ];
        return '${k + 1}. ${here.name.split(' «').first}: '
            '${parts.isEmpty ? 'проезд' : parts.join(', ')}';
      }(),
  ];
}

/// Picks the order for a stop: automatic, only one cargo, nothing to load;
/// and whether to keep the load here.
Future<StopOrder?> pickStopOrder(
  BuildContext context,
  MagIndustry here,
  StopOrder now,
) {
  var pick = now.pick;
  var noPick = now.noPick, noDrop = now.noDrop;
  return showModalBottomSheet<StopOrder>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF7FAF8),
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        Widget choice(String key, String label, bool on, VoidCallback tap) =>
            ListTile(
              key: ValueKey(key),
              dense: true,
              leading: Icon(
                on ? Icons.radio_button_checked : Icons.radio_button_off,
                color: on ? MagPalette.mint : MagPalette.ink,
              ),
              title: Text(label),
              onTap: () => set(tap),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(here.name, style: magTitle),
                const Text('Что забирать здесь', style: magMuted),
                choice(
                  'mag-order-auto',
                  'Само: что нужно другим остановкам',
                  pick == null && !noPick,
                  () {
                    pick = null;
                    noPick = false;
                  },
                ),
                for (final c in here.supplies)
                  choice(
                    'mag-order-pick-${c.name}',
                    'Только: ${cargoName(c).toLowerCase()}',
                    pick == c && !noPick,
                    () {
                      pick = c;
                      noPick = false;
                    },
                  ),
                choice('mag-order-nopick', 'Ничего не забирать', noPick, () {
                  pick = null;
                  noPick = true;
                }),
                SwitchListTile(
                  key: const ValueKey('mag-order-nodrop'),
                  contentPadding: EdgeInsets.zero,
                  value: noDrop,
                  activeThumbColor: MagPalette.mint,
                  title: const Text('Не выгружать здесь'),
                  subtitle: const Text(
                    'Груз едет дальше, к следующим остановкам',
                    style: magMuted,
                  ),
                  onChanged: (v) => set(() => noDrop = v),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('mag-order-save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MagPalette.mint,
                    ),
                    onPressed: () => Navigator.pop(
                      context,
                      StopOrder(pick: pick, noPick: noPick, noDrop: noDrop),
                    ),
                    child: const Text('Готово'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
