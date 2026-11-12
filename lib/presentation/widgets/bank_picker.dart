import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../domain/bank_catalog.dart';
import '../../domain/models.dart';
import '../controller.dart';
import 'common.dart';
import 'service_badge.dart';
import '../l10n_widgets.dart';

/// Bank of Russia registration number and BIC, shown so a person can tell
/// similarly named institutions apart.
String bankDetails(RussianBank bank) => [
  bank.nonBank ? 'НКО' : 'Банк',
  'рег. № ${bank.regNumber}',
  if (bank.bics.isNotEmpty) 'БИК ${bank.bics.first}',
  if (bank.city.isNotEmpty) bank.city,
].join(' · ');

/// Logo of a recognized bank (only when an original mark is bundled),
/// otherwise null so callers keep their own icon.
Widget? bankLogoFor(String bankName, {double size = 44}) {
  final bank = BankCatalog.byName(bankName);
  if (bank?.logoAsset == null) return null;
  return ServiceBadge(serviceId: bank!.id, name: bank.name, size: size);
}

/// The bank logo of [account], only if the person turned it on for this
/// account in its editor (1.22.1); null otherwise.
Widget? accountBankLogo(
  BuildContext context,
  Account account, {
  double size = 44,
}) {
  final on = FinanceScope.of(
    context,
  ).data.preferences.bankLogos.contains(account.id);
  return on ? bankLogoFor(account.bank, size: size) : null;
}

Future<RussianBank?> showBankPicker(BuildContext context) =>
    showModalBottomSheet<RussianBank>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _BankPicker(),
    );

class _BankPicker extends StatefulWidget {
  const _BankPicker();
  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final results = BankCatalog.search(query);
    final available =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: math.max(160.0, available * .86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Банк',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const ValueKey('bank-search'),
                autofocus: false,
                style: const TextStyle(fontSize: 15),
                decoration: searchDecoration(
                  context,
                  'Название, БИК или рег. номер',
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Text(
                '${results.length} из ${BankCatalog.entries.length} · реестр Банка России на ${BankCatalog.businessDay.split('-').reversed.join('.')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const EmptyState(
                      'Не найдено',
                      'Проверьте название или введите банк вручную.',
                      icon: Icons.account_balance_outlined,
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, index) {
                        final bank = results[index];
                        return ListTile(
                          key: ValueKey('bank-option-${bank.id}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 2,
                          ),
                          leading: ServiceBadge(
                            serviceId: bank.id,
                            name: bank.name,
                            size: 40,
                          ),
                          title: Text(
                            bank.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            bankDetails(bank),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, bank),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
