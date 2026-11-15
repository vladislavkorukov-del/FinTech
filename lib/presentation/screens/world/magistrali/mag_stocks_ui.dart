import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// The stock exchange (STK-01, STK-02, S23): the company's share price and
/// its history, issuing and buying back shares, stakes in rivals.
List<Widget> stockCards(MagistraliScreenState state) {
  final w = state.world;
  final h = w.priceHistory;
  final change = h.length < 2 ? 0.0 : (h.last - h.first) / h.first * 100;
  final outside = MagRules.shares - w.ownShares;
  return [
    Container(
      key: const ValueKey('mag-stock-card'),
      padding: const EdgeInsets.all(14),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Акция компании',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}% за ${h.length} дн.',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: change >= 0
                      ? MagPalette.teal
                      : const Color(0xFFD64B5C),
                ),
              ),
            ],
          ),
          Text(
            '${magMoney(w.sharePrice)} кр',
            key: const ValueKey('mag-share-price'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            width: double.infinity,
            child: CustomPaint(painter: _Spark(List.of(h))),
          ),
          const SizedBox(height: 8),
          Text(
            'Ваши ${w.ownShares} из ${MagRules.shares} акций (${(w.ownShares / 10).toStringAsFixed(1)}%)'
            '${outside > 0 ? ' · держателям — 30% месячной прибыли пропорционально доле' : ''}',
            style: magMuted,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('mag-shares-issue'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MagPalette.mint,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: w.ownShares - 100 < MagRules.controlShares
                      ? null
                      : () => state.report(w.issueShares(), 'Акции выпущены'),
                  child: Text(
                    'Выпустить 100 · +${magMoney((100 * w.sharePrice * .95).round())}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('mag-shares-buyback'),
                  onPressed: outside == 0
                      ? null
                      : () =>
                            state.report(w.buybackShares(), 'Акции выкуплены'),
                  child: Text(
                    'Выкупить 100 · ${magMoney((100 * w.sharePrice * 1.05).round())}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    const Text(
      'Акции конкурентов',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    const Text(
      'Соберите 51% — компания станет вашей без выкупа целиком; пакет приносит долю их накоплений каждый месяц.',
      style: magMuted,
    ),
    if (w.rivals.isEmpty)
      const Text('На бирже пока нет других компаний', style: magMuted),
    for (var k = 0; k < w.rivals.length; k++)
      Container(
        key: ValueKey('mag-rival-stock-$k'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: magCard(14),
        child: Row(
          children: [
            CircleAvatar(radius: 7, backgroundColor: Color(w.rivals[k].color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.rivals[k].name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${magMoney(w.rivalSharePrice(w.rivals[k]))} кр за акцию · ваш пакет ${(w.stakeIn(w.rivals[k]) / 10).toStringAsFixed(0)}%',
                    style: magMuted,
                  ),
                ],
              ),
            ),
            FilledButton(
              key: ValueKey('mag-rival-stock-buy-$k'),
              style: FilledButton.styleFrom(
                backgroundColor: MagPalette.mint,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: () =>
                  state.report(w.buyRivalShares(k), 'Пакет куплен'),
              child: const Text('+100'),
            ),
          ],
        ),
      ),
    const SizedBox(height: 14),
    ...creditCards(state),
  ];
}

class _Spark extends CustomPainter {
  _Spark(this.h);
  final List<int> h;

  @override
  void paint(Canvas c, Size size) {
    if (h.length < 2) {
      c.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        Paint()..color = const Color(0x332BB59A),
      );
      return;
    }
    final lo = h.reduce((a, b) => a < b ? a : b).toDouble();
    final hi = h.reduce((a, b) => a > b ? a : b).toDouble();
    final span = (hi - lo).abs() < 1 ? 1.0 : hi - lo;
    Offset at(int i) => Offset(
      i / (h.length - 1) * size.width,
      size.height - (h[i] - lo) / span * (size.height - 6) - 3,
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < h.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final up = h.last >= h.first;
    final color = up ? MagPalette.mint : const Color(0xFFD64B5C);
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    c.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    c.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_Spark old) =>
      old.h.length != h.length ||
      (h.isNotEmpty && old.h.isNotEmpty && old.h.last != h.last);
}

/// S24: the credit rating (FIN-17), bonds (FIN-18), insurance (INS-01).
List<Widget> creditCards(MagistraliScreenState state) {
  final w = state.world;
  final r = w.rating;
  final good = r.startsWith('A');
  return [
    Container(
      key: const ValueKey('mag-credit-card'),
      padding: const EdgeInsets.all(14),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: good
                      ? const Color(0x222BB59A)
                      : const Color(0x22D64B5C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  r,
                  key: const ValueKey('mag-rating'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: good ? MagPalette.teal : const Color(0xFFD64B5C),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Кредитный рейтинг · ${w.creditScore} из 100',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Выше рейтинг — дешевле кредит и облигации, больше лимит банка. Его поднимают малый долг, прибыльные месяцы и рост компании.',
            style: magMuted,
          ),
          const SizedBox(height: 10),
          Text(
            'Облигации · купон ${(w.bondRate * 100).toStringAsFixed(2)}% в месяц · срок ${MagRules.bondDays ~/ MagRules.daysPerMonth} мес.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final a in const [25000, 50000, 100000])
                OutlinedButton(
                  key: ValueKey('mag-bond-$a'),
                  onPressed: () =>
                      state.report(w.issueBond(a), 'Облигации размещены'),
                  child: Text('+${magMoney(a)}'),
                ),
            ],
          ),
          for (final b in w.bonds)
            magRow(
              'Облигация ${magMoney(b.amount)} кр',
              'купон ${magMoney((b.amount * b.rate).round())}/мес · погашение через ${((b.until - w.tick) / MagRules.ticksPerDay).ceil()} дн.',
            ),
          const Divider(),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('mag-insurance'),
              contentPadding: EdgeInsets.zero,
              value: w.insured,
              activeThumbColor: MagPalette.mint,
              title: const Text('Страховка от стихии'),
              subtitle: Text(
                '${magMoney(w.insurancePremium)} кр в месяц · ремонт после бедствий бесплатно и за день, выплата ${magMoney(MagRules.insurancePayout)} кр за клетку',
                style: magMuted,
              ),
              onChanged: (v) => state.report(w.setInsured(v)),
            ),
          ),
        ],
      ),
    ),
  ];
}
