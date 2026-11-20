import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/planning/purchase_math.dart';
import '../../controller.dart';
import '../../controller_phase8.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';

/// «Цены»: the person's own price history of products — per kg, litre or
/// piece, by store, with shrinking packs.
class PricesScreen extends StatelessWidget {
  const PricesScreen({super.key, this.fromEntry});

  /// An expense to record a product price from (no new expense is made).
  final FinanceEntry? fromEntry;

  Future<void> _newProduct(BuildContext context) async {
    final c = FinanceScope.of(context);
    final name = TextEditingController(),
        brand = TextEditingController(),
        variant = TextEditingController(),
        barcode = TextEditingController();
    var unit = 'pcs';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Новый товар'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('product-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                TextField(
                  controller: brand,
                  decoration: const InputDecoration(labelText: 'Бренд'),
                ),
                TextField(
                  controller: variant,
                  decoration: const InputDecoration(
                    labelText: 'Вариант (вкус, жирность)',
                  ),
                ),
                TextField(
                  controller: barcode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Штрихкод (если есть)',
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'kg', label: Text('кг')),
                    ButtonSegment(value: 'l', label: Text('л')),
                    ButtonSegment(value: 'pcs', label: Text('шт.')),
                  ],
                  selected: {unit},
                  onSelectionChanged: (s) => set(() => unit = s.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const ValueKey('product-save'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final p = Product(
        id: c.id(),
        name: name.text.trim(),
        unit: unit,
        brand: brand.text.trim(),
        variant: variant.text.trim(),
        barcode: barcode.text.trim().isEmpty ? null : barcode.text.trim(),
      );
      await c.saveProduct(p);
      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                ProductScreen(productId: p.id, fromEntry: fromEntry),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final products = [...c.data.extras.products]
      ..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(
        title: Text(fromEntry == null ? 'Цены' : 'Цена из операции'),
        actions: [
          IconButton(
            key: const ValueKey('products-add'),
            onPressed: () => _newProduct(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: products.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                'Товаров нет',
                'Добавьте товар и его цену — Финора покажет цену за кг/л/шт., магазины и уменьшение упаковки.',
                icon: Icons.sell_outlined,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (fromEntry != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Выберите товар для цены из «${fromEntry!.payee}» — расход не повторяется.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                for (final p in products)
                  () {
                    final h = PriceMath.history(p);
                    final shrink = PriceMath.shrinks(p).isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        key: ValueKey('product-${p.id}'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ProductScreen(
                              productId: p.id,
                              fromEntry: fromEntry,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [
                                      p.name,
                                      p.brand,
                                      p.variant,
                                    ].where((x) => x.isNotEmpty).join(' · '),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    h.isEmpty
                                        ? 'Цен пока нет'
                                        : 'Последняя: ${money(h.last.perUnitMinor, h.last.record.currency)} за ${PriceMath.units[p.unit]} · ${h.length} записей',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (shrink)
                              Icon(Icons.compress_rounded, color: scheme.error),
                          ],
                        ),
                      ),
                    );
                  }(),
              ],
            ),
    );
  }
}

/// One product: history, stores, shrinking packs, and adding a price.
class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.productId, this.fromEntry});
  final String productId;
  final FinanceEntry? fromEntry;

  Future<void> _addPrice(BuildContext context, Product p) async {
    final c = FinanceScope.of(context);
    final store = TextEditingController(text: fromEntry?.payee ?? '');
    final price = TextEditingController(
      text: fromEntry == null
          ? ''
          : decimalMinor(fromEntry!.amountMinor).replaceAll('.', ','),
    );
    final size = TextEditingController();
    final packs = TextEditingController(text: '1');
    var promo = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Цена'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('price-store'),
                  controller: store,
                  decoration: const InputDecoration(labelText: 'Магазин'),
                ),
                TextField(
                  key: const ValueKey('price-amount'),
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Заплатили за все упаковки, ₽',
                  ),
                ),
                TextField(
                  key: const ValueKey('price-packs'),
                  controller: packs,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Упаковок'),
                ),
                TextField(
                  key: const ValueKey('price-size'),
                  controller: size,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'В упаковке, ${PriceMath.units[p.unit]} (например 0,9)',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('По акции'),
                  value: promo,
                  onChanged: (v) => set(() => promo = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const ValueKey('price-save'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    int minor(String s) {
      try {
        return FinanceEngine.parseMinor(s);
      } catch (_) {
        return 0;
      }
    }

    // Size in thousandths of the unit: «0,9» → 900; «1,5» → 1500.
    final sizeValue = size.text.trim().replaceAll(',', '.');
    final parts = sizeValue.split('.');
    final whole = int.tryParse(parts.first) ?? 0;
    final frac = parts.length > 1
        ? int.tryParse(parts[1].padRight(3, '0').substring(0, 3)) ?? 0
        : 0;
    final milli = whole * 1000 + frac;
    if (ok == true && minor(price.text) > 0 && milli > 0) {
      await c.saveProduct(
        p.copyWith(
          prices: [
            ...p.prices,
            PriceRecord(
              id: c.id(),
              date: fromEntry?.date ?? DateTime.now(),
              store: store.text.trim().isEmpty ? 'Магазин' : store.text.trim(),
              priceMinor: minor(price.text),
              sizeMilli: milli,
              currency: fromEntry?.currency ?? c.currency,
              packs: (int.tryParse(packs.text) ?? 1).clamp(1, 1000),
              promo: promo,
              entryId: fromEntry?.id,
            ),
          ],
        ),
      );
    } else if (ok == true && context.mounted) {
      showError(
        context,
        const FormatException('Укажите цену и размер упаковки'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final p = c.data.extras.products
        .where((x) => x.id == productId)
        .firstOrNull;
    if (p == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final h = PriceMath.history(p);
    final stores = PriceMath.byStore(p);
    final shrinks = PriceMath.shrinks(p);
    final unit = PriceMath.units[p.unit];
    String d(DateTime x) =>
        '${x.day}.${x.month.toString().padLeft(2, '0')}.${x.year % 100}';
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            tooltip: 'Удалить товар',
            onPressed: () async {
              await c.deleteProduct(p.id);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('price-add'),
        onPressed: () => _addPrice(context, p),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Цена'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          for (final s in shrinks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                key: const ValueKey('price-shrink'),
                child: Text(
                  'Упаковка уменьшилась: было ${money(s.before.priceMinor, s.before.currency)} за ${PriceMath.size(s.before.sizeMilli, p.unit)}, '
                  'стало ${money(s.after.priceMinor, s.after.currency)} за ${PriceMath.size(s.after.sizeMilli, p.unit)}. '
                  'Цена за $unit выросла на ${(s.percent / 100).toStringAsFixed(1).replaceAll('.', ',')} %.',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          if (stores.length > 1) ...[
            const SectionTitle('Магазины (по вашим покупкам)'),
            SurfaceCard(
              child: Column(
                children: [
                  for (final s in stores)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.record.store),
                      subtitle: Text(
                        '${d(s.record.date)}${s.record.promo ? ' · по акции' : ''}',
                      ),
                      trailing: Text(
                        '${money(s.perUnitMinor, s.record.currency)} / $unit',
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SectionTitle('История цен'),
          if (h.isEmpty)
            const SurfaceCard(
              child: Text('Добавьте первую цену кнопкой «Цена».'),
            )
          else
            SurfaceCard(
              key: const ValueKey('price-history'),
              child: Column(
                children: [
                  for (final u in h.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 64, child: Text(d(u.record.date))),
                          Expanded(
                            child: Text(
                              '${u.record.store} · ${u.record.packs > 1 ? '${u.record.packs} × ' : ''}${PriceMath.size(u.record.sizeMilli, p.unit)} · ${money(u.record.priceMinor, u.record.currency)}${u.record.promo ? ' · акция' : ''}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            '${money(u.perUnitMinor, u.record.currency)}/$unit',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Перенести к другому товару',
                            onSelected: (to) =>
                                c.movePrice(u.record.id, p.id, to),
                            itemBuilder: (_) => [
                              for (final o in c.data.extras.products.where(
                                (o) => o.id != p.id && o.unit == p.unit,
                              ))
                                PopupMenuItem(
                                  value: o.id,
                                  child: Text('Это «${o.name}»'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Сравниваются только ваши покупки этого товара в одной валюте и единице. '
            'Ошибочно сопоставленную цену можно перенести к другому товару (⋮).',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
