import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/bank_catalog.dart';
import 'package:finora/domain/service_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.6: credit organizations from the official Bank of Russia BIC
/// directory, searchable in Russian, with original marks only where verified.
void main() {
  final registry =
      jsonDecode(File('assets/banks/registry.json').readAsStringSync())
          as Map<String, dynamic>;
  final logos =
      (jsonDecode(File('assets/banks/manifest.json').readAsStringSync())
              as Map<String, dynamic>)['items']
          as List<dynamic>;

  test('catalog mirrors the recorded official registry exactly', () {
    final items = (registry['items'] as List).cast<Map<String, dynamic>>();
    expect(registry['source'], 'https://www.cbr.ru/s/newbik');
    expect(BankCatalog.entries, hasLength(items.length));
    expect(items.length, greaterThan(300));
    final byReg = {for (final b in BankCatalog.entries) b.regNumber: b};
    expect(byReg, hasLength(items.length));
    for (final item in items) {
      final bank = byReg[item['regNumber']]!;
      expect(bank.officialName, item['officialName']);
      expect(bank.bics, (item['bics'] as List).cast<String>());
    }
    final bics = [for (final b in BankCatalog.entries) ...b.bics];
    expect(bics.toSet(), hasLength(bics.length));
    expect(bics.every(RegExp(r'^\d{9}$').hasMatch), isTrue);
    final ids = BankCatalog.entries.map((b) => b.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids.every(RegExp(r'^bank_[0-9a-z]+$').hasMatch), isTrue);
  });

  test('stable registration numbers and BIC resolve major banks', () {
    expect(BankCatalog.byRegNumber('1481')!.name, 'Сбербанк');
    expect(BankCatalog.byBic('044525225')!.regNumber, '1481');
    expect(BankCatalog.byRegNumber('2673')!.name, 'Т-Банк');
    expect(BankCatalog.byRegNumber('3510-к')!.name, 'ЮMoney');
    expect(BankCatalog.byRegNumber('3510-К')!.nonBank, isTrue);
    expect(BankCatalog.byRegNumber('1481')!.nonBank, isFalse);
    expect(BankCatalog.byRegNumber('999999'), isNull);
  });

  test('Russian names, abbreviations and former names are searchable', () {
    String first(String q) => BankCatalog.search(q).first.regNumber;
    expect(first('сбер'), '1481');
    expect(first('СБЕРБАНК'), '1481');
    expect(first('тинькофф'), '2673');
    expect(first('т-банк'), '2673');
    expect(first('Т Банк'), '2673');
    expect(first('газпромбанк'), '354');
    expect(first('ГПБ'), '354');
    expect(first('промсвязьбанк'), '3251');
    expect(first('псб'), '3251');
    expect(first('альфа'), '1326');
    expect(first('россельхоз'), '3349');
    expect(first('хоум кредит'), '316');
    expect(first('юмани'), '3510-К');
    expect(first('дом рф'), '2312');
    expect(first('044525974'), '2673');
    expect(BankCatalog.byName('Тинькофф')!.regNumber, '2673');
    expect(BankCatalog.byName('  сбер ')!.regNumber, '1481');
    expect(BankCatalog.byName('ПАО Сбербанк')!.regNumber, '1481');
    expect(BankCatalog.byName('Мой банк'), isNull);
    expect(BankCatalog.byName('банк'), isNull);
  });

  test('icon library adds banks without changing the 246 services', () {
    expect(ServiceCatalog.entries, hasLength(246));
    expect(ServiceCatalog.groups['banks'], isNotNull);
    expect(
      ServiceCatalog.search('', group: 'banks'),
      hasLength(BankCatalog.entries.length),
    );
    // Subscription lookups keep their former behavior.
    expect(ServiceCatalog.byName('сбербанк')?.id, 'sberprime');
    expect(ServiceCatalog.search('СПОТИФАЙ').single.id, 'spotify');
    final sber = ServiceCatalog.byId('bank_1481')!;
    expect(sber.group, 'banks');
    expect(
      ServiceCatalog.search('тинькофф').map((s) => s.id),
      containsAll(['bank_2673', 'tbank_pro']),
    );
    for (final bank in BankCatalog.entries) {
      final service = ServiceCatalog.byId(bank.id)!;
      expect(service.renderAssetPath, bank.rasterAsset);
    }
  });

  test('every bundled logo has provenance, SHA and a PNG display copy', () {
    final withLogo = BankCatalog.entries.where((b) => b.logoAsset != null);
    expect(withLogo.length, logos.length);
    final records = {
      for (final item in logos.cast<Map<String, dynamic>>())
        item['regNumber']: item,
    };
    for (final bank in withLogo) {
      final record = records[bank.regNumber]!;
      expect(record['assetPath'], bank.logoAsset);
      expect(record['source'], startsWith('https://commons.wikimedia.org/'));
      expect((record['license'] as Map)['LicenseShortName'], isNotEmpty);
      expect(File(bank.logoAsset!).existsSync(), isTrue);
      expect(File(bank.rasterAsset!).existsSync(), isTrue, reason: bank.name);
    }
    // No mark is invented: every other organization has no logo asset.
    for (final bank in BankCatalog.entries.where((b) => b.logoAsset == null)) {
      expect(records.containsKey(bank.regNumber), isFalse);
    }
  });
}
