part of 'management.dart';

/// The shopping list, a small app of its own: several lists («Покупки»,
/// «Дом», «Аптека»…), items grouped by the shop's departments, quick
/// quantities, suggestions from what is bought often, progress in the
/// shop, sending the list as text — and the bought items become one
/// expense with their total.
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  /// «молоко 2 шт 89» → name «молоко», quantity «2 шт», price 89.
  static ShoppingItem parse(String id, String text) => Shopping.parse(id, text);

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  /// The open list: '' is the main one.
  String _list = '';
  bool _showBought = true;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _name(String list) => list.isEmpty ? Shopping.mainList : list;

  Future<void> _set(
    FinanceController c,
    List<ShoppingItem> Function(List<ShoppingItem>) change,
  ) => c.mutate((d) => d.copyWith(shopping: change(d.shopping)));

  Future<void> _add(FinanceController c, [String? text]) async {
    final value = (text ?? _input.text).trim();
    if (value.isEmpty) return;
    final item = Shopping.parse(c.id(), value, list: _list);
    if (text == null) _input.clear();
    Haptics.light();
    await _set(c, (all) => [...all, item]);
    if (text == null) _focus.requestFocus();
  }

  Future<void> _toggle(FinanceController c, ShoppingItem item) async {
    Haptics.tap();
    await c.mutate(
      (d) => d.copyWith(
        shopping: [
          for (final s in d.shopping)
            s.id == item.id ? s.copyWith(done: !s.done) : s,
        ],
        // Bought: remembered for suggestions.
        preferences: item.done
            ? d.preferences
            : d.preferences.copyWith(
                shoppingHistory: Shopping.remember(
                  d.preferences.shoppingHistory,
                  [item.name],
                ),
              ),
      ),
    );
  }

  Future<void> _bump(FinanceController c, ShoppingItem item, int by) async {
    final q = Shopping.bump(item.quantity, by);
    if (q == null) return;
    Haptics.tap();
    await _set(
      c,
      (all) => [
        for (final s in all) s.id == item.id ? s.copyWith(quantity: q) : s,
      ],
    );
  }

  Future<void> _remove(FinanceController c, String id) =>
      _set(c, (all) => all.where((s) => s.id != id).toList());

  Future<void> _edit(FinanceController c, ShoppingItem item) async {
    final name = TextEditingController(text: item.name);
    final quantity = TextEditingController(text: item.quantity);
    final price = TextEditingController(
      text: item.priceMinor == null
          ? ''
          : groupAmount(decimalMinor(item.priceMinor!)),
    );
    var section = Shopping.sectionFor(item);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Покупка'),
          content: SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const ValueKey('shopping-edit-section'),
                  initialValue: section,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Отдел'),
                  items: [
                    for (final s in [
                      ...Shopping.sections.map((e) => e.$1),
                      Shopping.other,
                    ])
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => set(() => section = v ?? section),
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
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
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
      final auto = Shopping.sectionOf(name.text.trim());
      await _set(
        c,
        (all) => [
          for (final s in all)
            s.id == item.id
                ? s.copyWith(
                    name: name.text.trim(),
                    quantity: quantity.text.trim(),
                    priceMinor: minor,
                    // Kept only when it differs from the automatic one.
                    section: section == auto ? '' : section,
                  )
                : s,
        ],
      );
    }
    name.dispose();
    quantity.dispose();
    price.dispose();
  }

  /// A new list, or the current one renamed (null [old]: new).
  Future<void> _nameList(FinanceController c, {String? old}) async {
    final field = TextEditingController(text: old ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? 'Новый список' : 'Переименовать список'),
        content: TextField(
          key: const ValueKey('shopping-list-name'),
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Например: Дом, Аптека'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('shopping-list-save'),
            onPressed: () => Navigator.pop(ctx, field.text),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    field.dispose();
    final name = value?.trim() ?? '';
    final lists = c.data.preferences.shoppingLists;
    if (name.isEmpty ||
        name.length > 40 ||
        name == Shopping.mainList ||
        lists.contains(name)) {
      return;
    }
    await c.mutate(
      (d) => d.copyWith(
        preferences: d.preferences.copyWith(
          shoppingLists: old == null
              ? [...lists, name]
              : [for (final l in lists) l == old ? name : l],
        ),
        shopping: old == null
            ? d.shopping
            : [
                for (final s in d.shopping)
                  s.list == old ? s.copyWith(list: name) : s,
              ],
      ),
    );
    if (mounted) setState(() => _list = name);
  }

  Future<void> _deleteList(FinanceController c) async {
    final list = _list;
    if (list.isEmpty) return;
    final sure = await confirmWithFinora(
      context,
      title: 'Удалить список «$list»?',
      message: 'Покупки из него тоже удалятся.',
      action: 'Удалить',
      destructive: true,
    );
    if (!sure) return;
    await c.mutate(
      (d) => d.copyWith(
        preferences: d.preferences.copyWith(
          shoppingLists: d.preferences.shoppingLists
              .where((l) => l != list)
              .toList(),
        ),
        shopping: d.shopping.where((s) => s.list != list).toList(),
      ),
    );
    if (mounted) setState(() => _list = '');
  }

  Future<void> _share(List<ShoppingItem> items) => SharePlus.instance.share(
    ShareParams(text: Shopping.asText(_name(_list), items, '')),
  );

  /// The bought items of this list as one expense; cleared once saved.
  Future<void> _record(FinanceController c, List<ShoppingItem> done) async {
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
      final ids = {for (final s in done) s.id};
      await _set(c, (all) => all.where((s) => !ids.contains(s.id)).toList());
      Finora.react(FinoraMood.done, text: 'Покупки записаны');
    }
  }

  @override
  Widget build(BuildContext context) => FeatureGate(
    featureId: PaidFeature.shopping,
    child: Builder(builder: _content),
  );

  Widget _content(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final prefs = c.data.preferences;
    final lists = ['', ...prefs.shoppingLists];
    if (!lists.contains(_list)) _list = '';
    final mine = c.data.shopping.where((s) => s.list == _list).toList();
    final open = mine.where((s) => !s.done).toList();
    final done = mine.where((s) => s.done).toList();
    final total = done.fold<int>(0, (sum, s) => sum + (s.priceMinor ?? 0));
    final planned = open.fold<int>(0, (sum, s) => sum + (s.priceMinor ?? 0));
    final suggestions = Shopping.suggestions(prefs.shoppingHistory, mine);
    // Departments in the shop's order.
    final groups = <String, List<ShoppingItem>>{};
    for (final s in open) {
      groups.putIfAbsent(Shopping.sectionFor(s), () => []).add(s);
    }
    final order = groups.keys.toList()
      ..sort(
        (a, b) => Shopping.sectionRank(a).compareTo(Shopping.sectionRank(b)),
      );
    Widget row(ShoppingItem s) => _ShoppingRow(
      key: ValueKey('shopping-${s.id}'),
      item: s,
      currency: c.currency,
      onToggle: () => _toggle(c, s),
      onEdit: () => _edit(c, s),
      onDelete: () => _remove(c, s.id),
      onMore: () => _bump(c, s, 1),
      onLess: () => _bump(c, s, -1),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_name(_list)),
        actions: [
          if (mine.isNotEmpty)
            IconButton(
              key: const ValueKey('shopping-share'),
              tooltip: 'Отправить список',
              onPressed: () => _share(mine),
              icon: const Icon(Icons.ios_share_rounded),
            ),
          if (done.isNotEmpty)
            IconButton(
              key: const ValueKey('shopping-clear-done'),
              tooltip: 'Убрать купленное',
              onPressed: () => _set(
                c,
                (all) =>
                    all.where((s) => !(s.done && s.list == _list)).toList(),
              ),
              icon: const Icon(Icons.playlist_remove_rounded),
            ),
          PopupMenuButton<String>(
            key: const ValueKey('shopping-menu'),
            onSelected: (v) => switch (v) {
              'new' => _nameList(c),
              'rename' => _nameList(c, old: _list),
              _ => _deleteList(c),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('Новый список')),
              if (_list.isNotEmpty) ...[
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('Переименовать'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Удалить список'),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // The lists.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final l in lists)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('shopping-list-${_name(l)}'),
                      label: Text(
                        '${_name(l)} · '
                        '${c.data.shopping.where((s) => s.list == l && !s.done).length}',
                      ),
                      selected: l == _list,
                      onSelected: (_) => setState(() => _list = l),
                    ),
                  ),
                ActionChip(
                  key: const ValueKey('shopping-new-list'),
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Список'),
                  onPressed: () => _nameList(c),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
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
          // Often bought, one tap to add.
          if (suggestions.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                key: const ValueKey('shopping-suggestions'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final s in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        key: ValueKey('shopping-suggest-$s'),
                        avatar: const Icon(Icons.history_rounded, size: 16),
                        label: Text(s),
                        onPressed: () => _add(c, s),
                      ),
                    ),
                ],
              ),
            ),
          // Progress in the shop and the expected sum.
          if (mine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Куплено ${done.length} из ${mine.length}',
                          key: const ValueKey('shopping-progress'),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (planned > 0)
                        Text(
                          'Примерно к покупке: ${money(planned, c.currency)}',
                          key: const ValueKey('shopping-planned'),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GradientProgress(
                    value: done.length / mine.length,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            ),
          Expanded(
            child: mine.isEmpty
                ? const SingleChildScrollView(
                    child: EmptyState(
                      'Список пуст',
                      'Добавьте, что купить: «хлеб», «молоко 2 шт 89». '
                          'Покупки сами разложатся по отделам магазина.',
                      icon: Icons.shopping_basket_outlined,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    children: [
                      for (final section in order) ...[
                        _SectionHeader(section, groups[section]!.length),
                        for (final s in groups[section]!) row(s),
                      ],
                      if (done.isNotEmpty) ...[
                        InkWell(
                          key: const ValueKey('shopping-bought-toggle'),
                          onTap: () =>
                              setState(() => _showBought = !_showBought),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'КУПЛЕНО · ${done.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      letterSpacing: .6,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _showBought
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 20,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showBought)
                          for (final s in done) row(s),
                      ],
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
                  onPressed: () => _record(c, done),
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

/// A department's title over its items.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.count);
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
    child: Text(
      '${title.toUpperCase()} · $count',
      style: TextStyle(
        fontSize: 12,
        letterSpacing: .6,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// One item: a round check, the name with its quantity (− and + when it
/// has a number), and the price on the name's line.
class _ShoppingRow extends StatelessWidget {
  const _ShoppingRow({
    super.key,
    required this.item,
    required this.currency,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onMore,
    required this.onLess,
  });
  final ShoppingItem item;
  final String currency;
  final VoidCallback onToggle, onEdit, onMore, onLess;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = item;
    final counted = !s.done && Shopping.bump(s.quantity, 1) != null;
    return SwipeToDelete(
      key: ValueKey('swipe-shopping-${s.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      title: 'Удалить «${s.name}»?',
      message: 'Строка исчезнет из списка покупок.',
      onDelete: onDelete,
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        onTap: onEdit,
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('shopping-check-${s.id}'),
              value: s.done,
              shape: const CircleBorder(),
              onChanged: (_) => onToggle(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            s.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              decoration: s.done
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: s.done ? scheme.onSurfaceVariant : null,
                            ),
                          ),
                        ),
                        if (s.priceMinor != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, right: 8),
                            child: Text(
                              money(s.priceMinor!, currency),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: s.done ? scheme.onSurfaceVariant : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (s.quantity.isNotEmpty || counted)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            if (counted)
                              _Step(
                                key: ValueKey('shopping-less-${s.id}'),
                                icon: Icons.remove_rounded,
                                onTap: onLess,
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                s.quantity.isEmpty ? '1 шт' : s.quantity,
                                key: ValueKey('shopping-qty-${s.id}'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (counted)
                              _Step(
                                key: ValueKey('shopping-more-${s.id}'),
                                icon: Icons.add_rounded,
                                onTap: onMore,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small round − / + button.
class _Step extends StatelessWidget {
  const _Step({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .07),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16),
      ),
    ),
  );
}
