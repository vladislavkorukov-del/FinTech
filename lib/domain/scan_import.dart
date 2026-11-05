import 'finance_engine.dart';
import 'models.dart';
import 'scan_document.dart';
import 'scan_draft.dart';
import 'service_catalog.dart';

const _keep = Object();

/// Reviewed input, independent of widgets and persistence.
class ScanImportItem {
  const ScanImportItem({
    required this.draft,
    this.accountId,
    this.toAccountId,
    this.destinationMinor,
    this.selected = true,
  });
  final ScanDraft draft;
  final String? accountId, toAccountId;
  final int? destinationMinor;
  final bool selected;
  ScanImportItem copyWith({
    ScanDraft? draft,
    Object? accountId = _keep,
    Object? toAccountId = _keep,
    Object? destinationMinor = _keep,
    bool? selected,
  }) => ScanImportItem(
    draft: draft ?? this.draft,
    accountId: identical(accountId, _keep)
        ? this.accountId
        : accountId as String?,
    toAccountId: identical(toAccountId, _keep)
        ? this.toAccountId
        : toAccountId as String?,
    destinationMinor: identical(destinationMinor, _keep)
        ? this.destinationMinor
        : destinationMinor as int?,
    selected: selected ?? this.selected,
  );
}

abstract final class ScanImport {
  static List<ScanImportItem> prepare(
    ScanDocument document,
    FinanceData data, {
    String? preferredAccountId,
  }) => [
    for (final draft in document.drafts)
      _prepare(draft, data, preferredAccountId),
  ];

  static ScanImportItem _prepare(
    ScanDraft draft,
    FinanceData data,
    String? preferred,
  ) {
    final accounts = data.accounts.where(
      (a) =>
          !a.archived &&
          (draft.currency == null || a.currency == draft.currency),
    );
    final account =
        accounts.where((a) => a.id == preferred).firstOrNull ??
        accounts.firstOrNull;
    final item = ScanImportItem(draft: draft, accountId: account?.id);
    return item.copyWith(selected: !isPossibleDuplicate(item, data));
  }

  static String _key(String text) => text
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]'), '');
  static bool isPossibleDuplicate(ScanImportItem item, FinanceData data) {
    final d = item.draft;
    if (d.date == null ||
        d.kind == null ||
        d.amountMinor == null ||
        d.payee == null ||
        _key(d.payee!).isEmpty ||
        item.accountId == null) {
      return false;
    }
    return data.entries.any(
      (e) =>
          e.status == 'posted' &&
          e.accountId == item.accountId &&
          e.kind == d.kind &&
          e.amountMinor == d.amountMinor &&
          e.currency == d.currency &&
          e.date.year == d.date!.year &&
          e.date.month == d.date!.month &&
          e.date.day == d.date!.day &&
          _key(e.payee) == _key(d.payee!),
    );
  }

  /// Validate the whole selected batch before the repository commits anything.
  static List<FinanceEntry> entries(
    List<ScanImportItem> items,
    FinanceData data, {
    required String Function() newId,
    String? attachmentPath,
  }) {
    if (!items.any((i) => i.selected)) {
      throw const FormatException('Выберите хотя бы одну операцию.');
    }
    if (items.where((i) => i.selected).length > 500) {
      throw const FormatException(
        'Импортируйте не более 500 операций за один раз.',
      );
    }
    final result = <FinanceEntry>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (!item.selected) continue;
      try {
        final d = item.draft;
        final account = data.accounts
            .where((a) => a.id == item.accountId && !a.archived)
            .firstOrNull;
        if (account == null) {
          throw const FormatException('Выберите активный счёт.');
        }
        if (d.kind == null) {
          throw const FormatException('Выберите тип операции.');
        }
        if (d.amountMinor == null) {
          throw const FormatException('Укажите сумму.');
        }
        if (d.date == null) throw const FormatException('Укажите дату.');
        if (d.currency != account.currency) {
          throw const FormatException(
            'Проверьте валюту и выберите счёт в этой валюте.',
          );
        }
        if (d.kind != EntryKind.transfer &&
            !data.categories.any(
              (c) => c.id == d.categoryId && c.kind == d.kind && !c.archived,
            )) {
          throw const FormatException(
            'Выберите активную категорию подходящего типа.',
          );
        }
        final destination = data.accounts
            .where((a) => a.id == item.toAccountId && !a.archived)
            .firstOrNull;
        if (d.kind == EntryKind.transfer && destination == null) {
          throw const FormatException('Выберите счёт зачисления для перевода.');
        }
        final entry = FinanceEntry(
          id: newId(),
          kind: d.kind!,
          amountMinor: d.amountMinor!,
          currency: account.currency,
          accountId: account.id,
          categoryId: d.kind == EntryKind.transfer ? null : d.categoryId,
          toAccountId: d.kind == EntryKind.transfer ? item.toAccountId : null,
          destinationMinor: d.kind == EntryKind.transfer
              ? (destination?.currency == account.currency
                    ? d.amountMinor
                    : item.destinationMinor)
              : null,
          date: d.date!,
          payee: d.payee ?? '',
          note: d.comment,
          attachmentPath: attachmentPath,
          serviceId: d.kind == EntryKind.transfer
              ? null
              : ServiceCatalog.byName(d.payee)?.id,
          memberId: data.members.any((m) => m.id == 'me')
              ? 'me'
              : data.members.first.id,
        );
        FinanceEngine.validateEntry(entry, data);
        result.add(entry);
      } on FormatException catch (error) {
        throw FormatException('Операция ${index + 1}: ${error.message}');
      }
    }
    return result;
  }
}
