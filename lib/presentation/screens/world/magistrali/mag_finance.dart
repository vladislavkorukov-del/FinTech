import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_business.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

const _red = Color(0xFFD64B5C);

/// The company's finance centre (master plan stage 5): an overview of the
/// periods with a chart, transport, businesses, served settlements and
/// assets — all from the real figures of the game, never the player's own
/// Finora accounting.
Future<void> showFinanceSheet(MagistraliScreenState state) =>
    magSheet(state, 'mag-finance', (context) => MagFinanceCenter(state: state));

class MagFinanceCenter extends StatefulWidget {
  const MagFinanceCenter({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  State<MagFinanceCenter> createState() => _MagFinanceCenterState();
}

class _MagFinanceCenterState extends State<MagFinanceCenter> {
  int tab = 0;
  static const tabs = [
    'Обзор',
    'Транспорт',
    'Производства',
    'Поселения',
    'Активы',
  ];

  @override
  Widget build(BuildContext context) {
    final w = widget.state.world;
    return Column(
      key: const ValueKey('mag-finance-center'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Финансовый центр', style: magTitle),
        const Text(
          'Управленческий учёт компании: выручка отдельно от вложений, внутренние передачи не считаются доходом.',
          style: magMuted,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var k = 0; k < tabs.length; k++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: ValueKey('mag-fin-tab-$k'),
                    label: Text(tabs[k]),
                    selected: tab == k,
                    selectedColor: const Color(0x332BB59A),
                    onSelected: (_) => setState(() => tab = k),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...switch (tab) {
          0 => _overview(w),
          1 => _transport(w),
          2 => _industries(w),
          3 => _towns(w),
          _ => _assets(w),
        },
      ],
    );
  }

  Widget _card(List<Widget> children, {Key? key}) => Container(
    key: key,
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: magCard(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Text _head(String t) =>
      Text(t, style: const TextStyle(fontWeight: FontWeight.w800));

  String _signed(int v) => v >= 0 ? '+${magMoney(v)}' : '−${magMoney(-v)}';

  Color _tone(int v) => v >= 0 ? MagPalette.teal : _red;

  List<Widget> _overview(MagWorld w) {
    final figures = w.industryFigures;
    final good = figures.where((f) => f.profit > 0).length;
    return [
      _card([
        magRow('Деньги', '${magMoney(w.money)} кр'),
        magRow('Стоимость компании', '${magMoney(w.companyValue)} кр'),
        magRow('Заработано всего', '${magMoney(w.earnedTotal)} кр'),
        magRow('Доставок всего', '${w.deliveries}'),
        if (figures.isNotEmpty)
          magRow(
            'Предприятия: прибыльных / убыточных',
            '$good / ${figures.length - good}',
          ),
      ]),
      for (final p in w.periods)
        _card(key: ValueKey('mag-fin-period-${p.title}'), [
          _head(p.title),
          magRow('Выручка', '+${magMoney(p.revenue)}', color: MagPalette.teal),
          magRow('Операционные расходы', '−${magMoney(p.opex)}'),
          magRow(
            'Операционная прибыль',
            _signed(p.operating),
            color: _tone(p.operating),
          ),
          magRow('Рентабельность', '${(p.margin * 100).round()}%'),
          magRow('Вложения', '−${magMoney(p.capex)}'),
          if (p.assetSales > 0)
            magRow('Продажа активов', '+${magMoney(p.assetSales)}'),
          magRow(
            'Денежный поток',
            _signed(p.cashFlow),
            color: _tone(p.cashFlow),
          ),
        ]),
      _card([
        _head('По месяцам'),
        const Text(
          'Выручка (бирюзовый) и операционные расходы (серый)',
          style: magMuted,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          width: double.infinity,
          child: CustomPaint(
            painter: _MonthsChart([
              for (final m in w.months) w.periodOf(m, ''),
            ]),
          ),
        ),
      ]),
      if (w.revenueMix.isNotEmpty)
        _card([
          _head('Структура выручки'),
          for (final e in w.revenueMix)
            magRow(magIncomeNames[e.key] ?? e.key, magMoney(e.value)),
        ]),
      MagJournalPanel(state: widget.state),
    ];
  }

  List<Widget> _transport(MagWorld w) {
    final list = w.vehicleFigures;
    var income = 0, costs = 0;
    for (final f in list) {
      income += f.vehicle.income;
      costs += f.vehicle.costs;
    }
    return [
      _card([
        magRow('Выручка перевозок', '+${magMoney(income)}'),
        magRow(
          'Эксплуатация (топливо, корм, обслуживание, ремонт)',
          '−${magMoney(costs)}',
        ),
        magRow(
          'Прибыль транспорта',
          _signed(income - costs),
          color: _tone(income - costs),
        ),
      ]),
      for (final f in list)
        _card(key: ValueKey('mag-fin-vehicle-${f.vehicle.id}'), [
          _head(f.vehicle.name),
          magRow('Выручка', '+${magMoney(f.vehicle.income)}'),
          magRow('Расходы', '−${magMoney(f.vehicle.costs)}'),
          magRow('Прибыль', _signed(f.profit), color: _tone(f.profit)),
          magRow(
            'С грузом / пробег',
            f.loaded == null
                ? 'ещё не ездила'
                : '${(f.loaded! * 100).round()}% из ${magMoney(f.vehicle.odometer.round())} кл.',
          ),
          magRow('Рейсов', '${f.vehicle.trips}'),
        ]),
      if (w.routes.isNotEmpty) ...[
        _head('Маршруты'),
        for (final r in w.routes.values)
          magRow(r.name, '${magMoney(r.income)} кр · ${r.deliveries} дост.'),
      ],
    ];
  }

  List<Widget> _industries(MagWorld w) {
    final list = w.industryFigures;
    if (list.isEmpty) {
      return [
        const Text(
          'Своих предприятий пока нет. Купите или постройте предприятие — здесь появятся его продажи, расходы, выпуск и окупаемость.',
          style: magMuted,
        ),
      ];
    }
    return [
      for (final f in list)
        _card(key: ValueKey('mag-fin-industry-${f.industry.id}'), [
          _head('${f.industry.name} · ур. ${f.industry.level}'),
          magRow('Внешние продажи', '+${magMoney(f.industry.revenue)}'),
          magRow(
            'Сырьё, переработка, содержание',
            '−${magMoney(f.industry.costs)}',
          ),
          magRow(
            'Операционная прибыль',
            _signed(f.profit),
            color: _tone(f.profit),
          ),
          magRow(
            'Выпущено / продано',
            '${f.industry.produced} / ${f.industry.sold}',
          ),
          magRow(
            'На складе',
            '${f.industry.stock.values.fold(0, (a, b) => a + b)} из ${w.outputCapOf(f.industry)}',
          ),
          magRow('Вложено', magMoney(f.industry.invested)),
          magRow(
            'Окупаемость (оценка)',
            f.paybackDays == null
                ? 'пока нет прибыли'
                : '≈ ${f.paybackDays} дн.',
          ),
        ]),
    ];
  }

  List<Widget> _towns(MagWorld w) {
    final list = w.servedTowns;
    if (list.isEmpty) {
      return [
        const Text(
          'Вы ещё ничего не возили в поселения. Здесь появятся объёмы, выручка и контракты по каждому поселению.',
          style: magMuted,
        ),
      ];
    }
    return [
      const Text(
        'Выручка — оплата перевозок, продажа своей продукции и контракты в этом поселении. Общие расходы не распределяются.',
        style: magMuted,
      ),
      const SizedBox(height: 6),
      for (final i in list)
        _card(key: ValueKey('mag-fin-town-${i.id}'), [
          _head('${i.name} · ${i.town!.spec.name}'),
          magRow(
            'Выручка',
            '+${magMoney(i.town!.revenue)}',
            color: MagPalette.teal,
          ),
          magRow('Привезено, ед.', '${i.town!.delivered}'),
          magRow('Контракт развития', i.town!.devPaid ? 'выполнен' : 'открыт'),
        ]),
    ];
  }

  List<Widget> _assets(MagWorld w) {
    final horses = w.vehicles.values.where((v) => v.spec.horse).length;
    return [
      _card([
        magRow('Деньги', '${magMoney(w.money)} кр'),
        magRow(
          'Транспорт (${w.vehicles.length - horses} машин, $horses повозок)',
          '${magMoney(w.fleetValue)} кр',
        ),
        magRow(
          'Предприятия (${w.map.industries.where((i) => i.owned).length})',
          '${magMoney(w.industriesValue)} кр',
        ),
        magRow(
          'Склады (${w.warehouses.length})',
          '${magMoney(w.warehousesValue)} кр',
        ),
        magRow('Дороги', '${magMoney(w.roadsValue)} кр'),
        const Divider(),
        magRow('Стоимость компании', '${magMoney(w.companyValue)} кр'),
      ]),
      const Text(
        'Активы оценены по цене продажи: машины с учётом износа, предприятия и склады — половина вложенного, дороги — половина стоимости покрытия. Склады в стоимость компании пока не входят.',
        style: magMuted,
      ),
    ];
  }
}

/// Bars of revenue and running costs per month.
class _MonthsChart extends CustomPainter {
  _MonthsChart(this.months);
  final List<MagPeriod> months;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    final top = months.fold(
      1,
      (m, p) => math.max(m, math.max(p.revenue, p.opex)),
    );
    final slot = size.width / math.max(months.length, 6);
    final bar = math.min(14.0, slot * .32);
    final base = size.height - 2;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()..color = const Color(0x22000000),
    );
    for (var k = 0; k < months.length; k++) {
      final p = months[k];
      final x = slot * k + slot / 2;
      void draw(double dx, int v, Color c) {
        final h = (base - 4) * v / top;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + dx, base - h, bar, h),
            const Radius.circular(3),
          ),
          Paint()..color = c,
        );
      }

      draw(-bar - 1, p.revenue, MagPalette.mint);
      draw(1, p.opex, const Color(0xFFB7C1C4));
    }
  }

  @override
  bool shouldRepaint(_MonthsChart old) => true;
}
