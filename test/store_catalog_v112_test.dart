import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finora/domain/bank_catalog.dart';
import 'package:finora/domain/service_catalog.dart';
import 'package:finora/domain/store_catalog.dart';
import 'package:finora/presentation/widgets/service_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.12: Russian stores and everyday services with the icons their
/// own sites publish, recognized from payees as banks write them; and the
/// major banks' current marks.
void main() {
  final manifest =
      jsonDecode(File('assets/stores/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final records = {
    for (final item in (manifest['items'] as List).cast<Map<String, dynamic>>())
      'store_${item['id']}': item,
  };

  test('every store has a reviewed, recorded icon and its own group', () {
    expect(StoreCatalog.entries.length, greaterThanOrEqualTo(90));
    final ids = StoreCatalog.entries.map((s) => s.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final store in StoreCatalog.entries) {
      final record = records[store.id]!;
      expect(record['rejected'], isNull, reason: store.name);
      expect(record['site'], startsWith('https://'));
      expect(record['downloadUrl'], startsWith('https://'));
      expect(record['originalSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.renderAssetPath, record['rasterPath']);
      expect(File(store.renderAssetPath!).existsSync(), isTrue);
      expect(StoreCatalog.groups, contains(store.group));
      expect(ServiceCatalog.groups, contains(store.group));
      expect(ServiceCatalog.byId(store.id), same(store));
    }
    // Refused icons ship nothing.
    for (final item in records.values.where((r) => r['rejected'] != null)) {
      expect(ids, isNot(contains('store_${item['id']}')));
      expect(item['rasterPath'], isNull);
    }
  });

  test('payees as banks and people write them find their store', () {
    String? id(String payee) => ServiceCatalog.byName(payee)?.id;
    expect(id('Пятёрочка'), 'store_pyaterochka');
    expect(id('пятерочка 1234'), 'store_pyaterochka');
    expect(id('PYATEROCHKA 5521 MOSCOW'), 'store_pyaterochka');
    expect(id('MAGNIT MM KOSTROMA'), 'store_magnit');
    expect(id('Магнит у дома'), 'store_magnit');
    expect(id('WHOOSH'), 'store_whoosh');
    expect(id('Whoosh.'), 'store_whoosh');
    expect(id('вуш'), 'store_whoosh');
    expect(id('OZON.RU'), 'store_ozon');
    expect(id('Вкусно и точка'), 'store_vkusno_i_tochka');
    expect(id('YANDEX*GO'), 'store_yandex_go');
    expect(id('Яндекс Такси'), 'store_yandex_go');
    expect(id('Перекресток'), 'store_perekrestok');
    expect(id('DNS-SHOP'), 'store_dns');
    // Not a brand prefix, and subscriptions keep their exact match.
    expect(id('Магнитогорский рынок'), isNull);
    expect(id('Иван Петров'), isNull);
    expect(id('Ozon Premium'), 'ozon_premium');
    expect(id('Сбербанк'), 'sberprime');
  });

  test('store names and aliases are not shared by two brands', () {
    String loose(String v) => v
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'''[«»"“”„()\-–—.,/*’'&_]'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final owner = <String, String>{};
    for (final store in StoreCatalog.entries) {
      for (final name in {store.name, ...store.aliases}.map(loose)) {
        expect(
          owner.putIfAbsent(name, () => store.id),
          store.id,
          reason: '«$name» belongs to two stores',
        );
      }
    }
    // Every store resolves from its own name and aliases, except three
    // aliases that already named a subscription with the same parent-brand
    // mark (subscriptions keep their former exact match).
    const subscriptionFirst = {
      'Wildberries': 'wb_jam',
      'Вайлдберриз': 'wb_jam',
      'Озон': 'ozon_premium',
    };
    for (final store in StoreCatalog.entries) {
      for (final name in [store.name, ...store.aliases]) {
        expect(
          ServiceCatalog.byName(name)?.id,
          subscriptionFirst[name] ?? store.id,
          reason: name,
        );
      }
    }
    expect(ServiceCatalog.byName('WILDBERRIES 12345')?.id, 'store_wildberries');
  });

  test('major banks now carry their current marks', () {
    for (final reg in ['1481', '1000', '1326', '2673', '3349', '963', '3251']) {
      final bank = BankCatalog.byRegNumber(reg)!;
      expect(bank.logoAsset, isNotNull, reason: bank.name);
    }
    // Refused after review: the site shows another bank's or a former mark.
    expect(BankCatalog.byRegNumber('316')!.logoAsset, isNull);
    expect(BankCatalog.byRegNumber('1143')!.logoAsset, isNull);
  });

  testWidgets('store icons decode and replace the category icon', (
    tester,
  ) async {
    for (final store in StoreCatalog.entries) {
      await tester.runAsync(() async {
        final bytes = await rootBundle.load(store.renderAssetPath!);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThanOrEqualTo(80), reason: store.id);
      });
    }
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ServiceBadge(name: 'MAGNIT MM KOSTROMA')),
      ),
    );
    expect(
      find.byKey(const ValueKey('service-badge-store_magnit')),
      findsOneWidget,
    );
  });
}
