import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Stage S25 in the sheets: a container terminal in a port (PORT-01), a
/// signal on the track (SIG-01), an interchange on a road (JCT-01), a
/// town's mortgage (MORT-01), a night shift (NIGHT-01).

/// The port sheet: a container terminal.
List<Widget> terminalSection(MagistraliScreenState state, int cell) {
  final w = state.world;
  final built = w.terminals2.contains(cell);
  final why = w.containerTerminalBlocker(cell);
  return [
    const SizedBox(height: 10),
    Row(
      children: [
        const Icon(Icons.view_in_ar_rounded, color: MagPalette.teal),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Контейнерный терминал',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (built)
          const Text(
            'работает',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: MagPalette.teal,
            ),
          ),
      ],
    ),
    const Text(
      'Портальные краны грузят суда втрое быстрее. Контейнеровоз «Нева» ходит только между терминалами и получает за груз на 20% больше.',
      style: magMuted,
    ),
    if (!built) ...[
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('mag-cterminal-build'),
          style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
          onPressed: why != null
              ? null
              : () => state.report(
                  w.buildContainerTerminal(cell),
                  'Терминал построен',
                ),
          icon: const Icon(Icons.precision_manufacturing_rounded),
          label: Text(
            why ??
                'Построить терминал · ${magMoney(MagRules.containerTerminalPrice)} кр',
          ),
        ),
      ),
    ],
  ];
}

/// The rail sheet: a signal on the tapped cell.
List<Widget> signalSection(MagistraliScreenState state, int cell) {
  final w = state.world;
  final has = w.signals.contains(cell);
  final count = w.signals.length;
  return [
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('mag-signal'),
        icon: Icon(has ? Icons.traffic_outlined : Icons.traffic_rounded),
        onPressed: () => state.report(
          w.toggleSignal(cell),
          has ? 'Сигнал снят' : 'Сигнал поставлен',
        ),
        label: Text(
          has
              ? 'Снять сигнал'
              : w.signalsUnlocked
              ? 'Поставить сигнал · ${magMoney(MagRules.signalPrice)} кр'
              : 'Сигналы — после «Железнодорожной сигнализации»',
        ),
      ),
    ),
    Text(
      'Сигнал делит путь на блоки: поезд у красного сигнала ждёт, пока блок впереди освободится. Ставьте сигналы у разъездов — составы идут друг за другом и расходятся без лобовых встреч. Сигналов на карте: $count.',
      style: magMuted,
    ),
  ];
}

/// The road sheet: an interchange on a crossing.
List<Widget> interchangeSection(MagistraliScreenState state, int cell) {
  final w = state.world;
  if (w.interchanges.contains(cell)) {
    return [
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const ValueKey('mag-interchange-remove'),
          icon: const Icon(Icons.alt_route_outlined),
          onPressed: () =>
              state.report(w.removeInterchange(cell), 'Развязка снесена'),
          label: const Text('Развязка: снести'),
        ),
      ),
    ];
  }
  final why = w.interchangeBlocker(cell);
  return [
    const SizedBox(height: 8),
    SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('mag-interchange-build'),
        icon: const Icon(Icons.alt_route_rounded),
        onPressed: why != null
            ? null
            : () => state.report(w.buildInterchange(cell)),
        label: Text(
          why ??
              'Построить развязку · ${magMoney(MagRules.interchangePrice)} кр',
        ),
      ),
    ),
    const Text(
      'Развязка на перекрёстке или переезде: здесь и на соседних клетках пробок не бывает.',
      style: magMuted,
    ),
  ];
}

/// The town sheet: a mortgage programme.
List<Widget> mortgageSection(MagistraliScreenState state, MagIndustry i) {
  final w = state.world;
  final m = w.mortgageOf(i);
  return [
    const SizedBox(height: 10),
    Container(
      key: const ValueKey('mag-mortgage-card'),
      padding: const EdgeInsets.all(12),
      decoration: magCard(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.house_rounded, color: MagPalette.teal),
              SizedBox(width: 8),
              Text(
                'Ипотечная программа',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (m != null) ...[
            Text(
              'Идёт: население растёт в ${MagRules.mortgageGrowth.toStringAsFixed(1)} раза быстрее ещё ${((m.until - w.tick) / MagRules.ticksPerDay).ceil().clamp(0, 9999)} дн.',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: MagPalette.teal,
              ),
            ),
            magRow(
              'Возвращено',
              '${magMoney(m.returned)} из ${magMoney(m.total)} кр',
            ),
          ] else ...[
            Text(
              'Компания кредитует семьи: ${MagRules.mortgageDays ~/ MagRules.daysPerMonth} мес. город растёт в ${MagRules.mortgageGrowth.toStringAsFixed(1)} раза быстрее, а деньги возвращаются помесячно с наценкой ${((MagRules.mortgageReturn - 1) * 100).round()}%.',
              style: magMuted,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('mag-mortgage-start'),
                style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
                onPressed: w.mortgageUnlocked
                    ? () => state.report(
                        w.startMortgage(i.id),
                        'Ипотека запущена',
                      )
                    : null,
                icon: const Icon(Icons.key_rounded),
                label: Text(
                  w.mortgageUnlocked
                      ? 'Запустить · ${magMoney(w.mortgagePrice(i))} кр'
                      : 'Откроет технология «Ипотека»',
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  ];
}

/// The business sheet: a night shift.
List<Widget> nightShiftSection(MagistraliScreenState state, MagIndustry i) {
  final w = state.world;
  if (!i.owned || i.town != null || i.spec.stores) return const [];
  final on = w.nightShifts.contains(i.id);
  return [
    const SizedBox(height: 6),
    Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        key: const ValueKey('mag-night-shift'),
        contentPadding: EdgeInsets.zero,
        value: on,
        activeThumbColor: MagPalette.mint,
        title: const Text('Ночная смена'),
        subtitle: Text(
          w.nightUnlocked
              ? 'Выработка +${(MagRules.nightBonus * 100).round()}% · зарплата ${magMoney(w.nightWageOf(i))} кр в день'
              : 'Откроет технология «Ночные смены»',
          style: magMuted,
        ),
        onChanged: (v) => state.report(w.setNightShift(i.id, v)),
      ),
    ),
  ];
}
