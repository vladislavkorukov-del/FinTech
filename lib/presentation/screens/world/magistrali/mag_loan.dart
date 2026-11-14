import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Loans (FIN-15), a tab of the finance centre: the debt, its interest a
/// day, how much the bank still lends; take or pay back in steps.
List<Widget> loanCards(MagistraliScreenState state) {
  final w = state.world;
  final free = w.loanLimit - w.debt;
  Widget button(String key, String label, VoidCallback? tap) => Padding(
    padding: const EdgeInsets.only(right: 6, bottom: 6),
    child: OutlinedButton(
      key: ValueKey(key),
      onPressed: tap,
      child: Text(label),
    ),
  );
  return [
    Container(
      key: const ValueKey('mag-loan'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Банк', style: TextStyle(fontWeight: FontWeight.w800)),
          magRow(
            'Долг',
            '${magMoney(w.debt)} кр',
            color: w.debt > 0 ? const Color(0xFFD64B5C) : null,
          ),
          magRow(
            'Проценты в день',
            '${magMoney(w.dailyInterest)} кр · ${(MagRules.loanRate * 100).toStringAsFixed(1)}% в день',
          ),
          magRow('Банк ещё даст', '${magMoney(free)} кр'),
          const SizedBox(height: 6),
          const Text(
            'Кредит — деньги сейчас на дорогу, машины или завод. Проценты списываются каждый день, гасить можно в любой момент. Кредит не выручка: в отчётах он отдельно.',
            style: magMuted,
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final n in [5000, 20000, 50000])
                button(
                  'mag-loan-take-$n',
                  '+${magMoney(n)}',
                  n > free ? null : () => state.report(w.takeLoan(n)),
                ),
            ],
          ),
          Wrap(
            children: [
              for (final n in [5000, 20000])
                button(
                  'mag-loan-pay-$n',
                  '−${magMoney(n)}',
                  w.debt == 0 || w.money < n
                      ? null
                      : () => state.report(w.repayLoan(n)),
                ),
              button(
                'mag-loan-pay-all',
                'Погасить всё',
                w.debt == 0 || w.money < w.debt
                    ? null
                    : () => state.report(w.repayLoan(w.debt)),
              ),
            ],
          ),
        ],
      ),
    ),
  ];
}
