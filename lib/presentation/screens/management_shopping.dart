part of 'management.dart';

/// 1.38: the shopping list. Write what to buy (with a quantity and a price
/// if you like), tick it off in the shop; the ticked ones can become one
/// expense with their total, and are cleared after it is saved.
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  /// «молоко 2 шт 89» → name «молоко», quantity «2 шт», price 89.
  static ShoppingItem parse(String id, String text) {
    var rest = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    var quantity = '';
    final q = RegExp(
      r'(?:^|\s)(\d+(?:[.,]\d+)?\s?(?:шт|кг|гр|г|л|мл|уп|пач|бут|банк)[а-яё]*\.?)(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(rest);
    if (q != null) {
      quantity = q.group(1)!.trim();
      rest = '${rest.substring(0, q.start)} ${rest.substring(q.end)}'
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
    }
    int? price;
    final p = RegExp(
      r'^(.*?\S)\s+((?:\d{1,3}(?: \d{3})+|\d+)(?:[.,]\d{1,2})?)'
      r'\s*(?:₽|р\.?|руб\.?|рублей)?$',
    ).firstMatch(rest);
    if (p != null) {
      try {
        price = FinanceEngine.parseMinor(p.group(2)!);
        rest = p.group(1)!;
      } on FormatException {
        price = null;
      }
    }
    final name = rest.isEmpty ? text.trim() : rest;
    return ShoppingItem(
      id: id,
      name: name.length > 200 ? name.substring(0, 200) : name,
      quantity: quantity,
      priceMinor: price,
    );
  }

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add(FinanceController c) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final item = ShoppingScreen.parse(c.id(), text);
    _input.clear();
    Haptics.light();
    await c.mutate((d) => d.copyWith(shopping: [...d.shopping, item]));
    _focus.requestFocus();
  }

  Future<void> _toggle(FinanceController c, ShoppingItem item) async {
    Haptics.tap();
    await c.mutate(
      (d) => d.copyWith(
        shopping: [
          for (final s in d.shopping)
            s.id == item.id ? s.copyWith(done: !s.done) : s,
        ],
      ),
    );
  }

  Future<void> _remove(FinanceController c, String id) => c.mutate(
    (d) => d.copyWith(shopping: d.shopping.where((s) => s.id != id).toList()),
  );

  Future<void> _edit(FinanceController c, ShoppingItem item) async {
    final name = TextEditingController(text: item.name);
    final quantity = TextEditingController(text: item.quantity);
    final price = TextEditingController(
      text: item.priceMinor == null
          ? ''
          : groupAmount(decimalMinor(item.priceMinor!)),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Покупка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('shopping-edit-name'),
              controller: name,
              decoration: const InputDecoration(labelText: 'Что купить'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: quantity,
              decoration: const InputDecoration(
                labelText: 'Сколько',
                hintText: 'Например: 2 шт, 1 кг',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('shopping-edit-price'),
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [AmountGroupingFormatter()],
              decoration: const InputDecoration(labelText: 'Цена'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      int? minor;
      try {
        minor = price.text.trim().isEmpty
            ? null
            : FinanceEngine.parseMinor(price.text);
      } on FormatException {
        minor = item.priceMinor;
      }
      await c.mutate(
        (d) => d.copyWith(
          shopping: [
            for (final s in d.shopping)
              s.id == item.id
                  ? s.copyWith(
                      name: name.text.trim(),
                      quantity: quantity.text.trim(),
                      priceMinor: minor,
                    )
                  : s,
          ],
        ),
      );
    }
    name.dispose();
    quantity.dispose();
    price.dispose();
  }

  /// The ticked items as one expense; cleared once it is saved.
  Future<void> _record(FinanceController c) async {
    final done = c.data.shopping.where((s) => s.done).toList();
    if (done.isEmpty) return;
    final total = done.fold<int>(0, (sum, s) => sum + (s.priceMinor ?? 0));
    final account = c.data.accounts.where((a) => !a.archived).firstOrNull;
    if (account == null) {
      showError(context, const FormatException('Сначала добавьте счёт.'));
      return;
    }
    final before = c.data.entries.length;
    final category = VoiceEntryParser.categoryFor(
      'продукты',
      EntryKind.expense,
      c.data.categories,
    );
    await showEntryEditor(
      context,
      entry: FinanceEntry(
        id: c.id(),
        kind: EntryKind.expense,
        amountMinor: total > 0 ? total : 1,
        currency: account.currency,
        accountId: account.id,
        categoryId: category,
        date: DateTime.now(),
        note: done.map((s) => s.name).join(', '),
      ),
    );
    if (c.data.entries.length > before) {
      await c.mutate(
        (d) => d.copyWith(shopping: d.shopping.where((s) => !s.done).toList()),
      );
      Finora.react(FinoraMood.done, text: 'Покупки записаны');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = [
      ...c.data.shopping.where((s) => !s.done),
      ...c.data.shopping.where((s) => s.done),
    ];
    final done = c.data.shopping.where((s) => s.done).toList();
    final total = done.fold<int>(0, (sum, s) => sum + (s.priceMinor ?? 0));
    final planned = c.data.shopping
        .where((s) => !s.done)
        .fold<int>(0, (sum, s) => sum + (s.priceMinor ?? 0));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Список покупок'),
        actions: [
          if (done.isNotEmpty)
            IconButton(
              key: const ValueKey('shopping-clear-done'),
              tooltip: 'Убрать купленное',
              onPressed: () => c.mutate(
                (d) => d.copyWith(
                  shopping: d.shopping.where((s) => !s.done).toList(),
                ),
              ),
              icon: const Icon(Icons.playlist_remove_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              key: const ValueKey('shopping-input'),
              controller: _input,
              focusNode: _focus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(c),
              decoration: InputDecoration(
                hintText: 'Что купить? Например: молоко 2 шт 89',
                prefixIcon: const Icon(Icons.add_shopping_cart_rounded),
                suffixIcon: IconButton(
                  key: const ValueKey('shopping-add'),
                  tooltip: 'Добавить',
                  onPressed: () => _add(c),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ),
          ),
          if (planned > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Примерно к покупке: ${money(planned, c.currency)}',
                  key: const ValueKey('shopping-planned'),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? const SingleChildScrollView(
                    child: EmptyState(
                      'Список пуст',
                      'Добавьте, что купить: «хлеб», «молоко 2 шт 89». '
                          'В магазине отмечайте купленное.',
                      icon: Icons.shopping_basket_outlined,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    children: [
                      for (final s in items)
                        SwipeToDelete(
                          key: ValueKey('shopping-${s.id}'),
                          margin: const EdgeInsets.only(bottom: 8),
                          title: 'Удалить «${s.name}»?',
                          message: 'Строка исчезнет из списка покупок.',
                          onDelete: () => _remove(c, s.id),
                          child: SurfaceCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            onTap: () => _edit(c, s),
                            child: Row(
                              children: [
                                Checkbox(
                                  key: ValueKey('shopping-check-${s.id}'),
                                  value: s.done,
                                  shape: const CircleBorder(),
                                  onChanged: (_) => _toggle(c, s),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.name,
                                        style: TextStyle(
                                          fontSize: 16,
                                          decoration: s.done
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color: s.done
                                              ? scheme.onSurfaceVariant
                                              : null,
                                        ),
                                      ),
                                      if (s.quantity.isNotEmpty)
                                        Text(
                                          s.quantity,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (s.priceMinor != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Text(
                                      money(s.priceMinor!, c.currency),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: s.done
                                            ? scheme.onSurfaceVariant
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: done.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                  key: const ValueKey('shopping-record'),
                  onPressed: () => _record(c),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: Text(
                    total > 0
                        ? 'Записать расход: ${money(total, c.currency)}'
                        : 'Записать купленное как расход',
                  ),
                ),
              ),
            ),
    );
  }
}
