import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

String dispatchModeName(MagDispatchMode m) => switch (m) {
  MagDispatchMode.economy => 'Экономный',
  MagDispatchMode.balanced => 'Сбалансированный',
  MagDispatchMode.fast => 'Быстрый',
};

String dispatchModeLore(MagDispatchMode m) => switch (m) {
  MagDispatchMode.economy =>
    'Диспетчер считает каждый литр: едет машина, которой дешевле всего '
        'добраться и довезти, и чей кузов заполнится плотнее.',
  MagDispatchMode.balanced =>
    'Золотая середина: стоимость рейса, время в пути и заполнение кузова '
        'весят примерно одинаково.',
  MagDispatchMode.fast =>
    'Скорость прежде всего: едет та машина, что доставит раньше всех, даже '
        'если это тягач ради десятка мешков.',
};

/// The automatic fleet: how many trucks, the dispatcher's mode, and its
/// latest choices with their reasons.
class MagDispatchPanel extends StatelessWidget {
  const MagDispatchPanel({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final w = state.world;
    if (!w.dispatcherUnlocked) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: magCard(16),
        child: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: Color(0xFF9AA6AA)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Автопарк и диспетчер откроет технология «Диспетчерская» '
                '(ветка «Склады и логистика»).',
                style: magMuted,
              ),
            ),
          ],
        ),
      );
    }
    final fleet = w.autoFleet.toList();
    final busy = fleet.where((v) => v.orderId != null).length;
    final waiting = w.orders.active
        .where((o) => o.status == MagOrderStatus.pending)
        .length;
    return Container(
      key: const ValueKey('mag-dispatch'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hub_rounded, color: MagPalette.teal),
              SizedBox(width: 8),
              Text(
                'Автопарк и диспетчер',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'В автопарке ${fleet.length} · в работе $busy · заявок ждёт $waiting',
            style: magMuted,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final m in MagDispatchMode.values)
                ChoiceChip(
                  key: ValueKey('mag-dispatch-${m.name}'),
                  label: Text(dispatchModeName(m)),
                  selected: w.dispatchMode == m,
                  onSelected: (_) {
                    w.dispatchMode = m;
                    state.changed();
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(dispatchModeLore(w.dispatchMode), style: magMuted),
          if (fleet.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Откройте машину и включите «Автопарк» — она начнёт брать заявки сама.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          if (w.dispatchLog.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Последние решения',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final n in w.dispatchLog.reversed.take(5))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${w.vehicles[n.vehicle]?.name ?? 'Машина'} → заказ №${n.order}: ${n.reason}',
                  style: magMuted,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
