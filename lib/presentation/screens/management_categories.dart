part of 'management.dart';

Future<(int, int)?> showIconPicker(
  BuildContext context, {
  required int icon,
  required int color,
}) => showModalBottomSheet<(int, int)>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _IconPicker(icon: icon, color: color),
);

class _IconPicker extends StatefulWidget {
  const _IconPicker({required this.icon, required this.color});
  final int icon, color;
  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  late int icon = widget.icon.abs() % iconChoices.length;
  late int color = widget.color;
  final search = TextEditingController();
  String query = '';
  String group = 'all';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final matches = searchFinanceIcons(query, group: group);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final available = MediaQuery.sizeOf(context).height - keyboard;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: math.max(120.0, available * .88),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CustomScrollView(
                    key: const ValueKey('icon-picker-scroll'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                CategoryBadge(
                                  icon: categoryIcon(icon),
                                  color: Color(color),
                                  size: 52,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Выберите иконку',
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        iconCatalog[icon].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Закрыть',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              key: const ValueKey('icon-search'),
                              controller: search,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                hintText: 'Такси, стоматолог, отпуск…',
                                suffixIcon: query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Очистить поиск',
                                        onPressed: () {
                                          search.clear();
                                          setState(() => query = '');
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                              onChanged: (value) =>
                                  setState(() => query = value),
                            ),
                            const SizedBox(height: 12),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final item in {
                                    'all': 'Все',
                                    ...iconGroups,
                                  }.entries)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(item.value),
                                        selected: group == item.key,
                                        onSelected: (_) =>
                                            setState(() => group = item.key),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Цвет иконки',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 10),
                            _colors(
                              color,
                              (value) => setState(() => color = value),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '${matches.length} иконок · ${iconChoices.length} в коллекции',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      if (matches.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'Ничего не найдено. Попробуйте другое слово или группу.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 12),
                          sliver: SliverGrid.builder(
                            key: const ValueKey('icon-picker-grid'),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 72,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                ),
                            itemCount: matches.length,
                            itemBuilder: (_, position) {
                              final entry = matches[position];
                              final selected = icon == entry.index;
                              return Semantics(
                                label:
                                    '${entry.label}, ${entry.name.replaceAll('_', ' ')}',
                                selected: selected,
                                button: true,
                                child: Tooltip(
                                  message: entry.label,
                                  child: InkWell(
                                    key: ValueKey(
                                      'catalog-icon-${entry.index}',
                                    ),
                                    onTap: () =>
                                        setState(() => icon = entry.index),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? Color(
                                                color,
                                              ).withValues(alpha: .18)
                                            : scheme.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: selected
                                              ? Color(color)
                                              : scheme.outlineVariant,
                                          width: selected ? 2 : .5,
                                        ),
                                      ),
                                      child: Icon(
                                        entry.icon,
                                        color: Color(color),
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context, (icon, color)),
                  child: const Text('Выбрать'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  EntryKind kind = EntryKind.expense;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final list = c.data.categories.where((a) => a.kind == kind).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Категории'),
        actions: [
          IconButton(
            tooltip: 'Добавить категорию',
            onPressed: () => _categoryEditor(context, kind: kind),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<EntryKind>(
                segments: const [
                  ButtonSegment(
                    value: EntryKind.expense,
                    label: Text('Расходы'),
                  ),
                  ButtonSegment(value: EntryKind.income, label: Text('Доходы')),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setState(() => kind = v.first),
              ),
            ),
          ),
          if (list.isEmpty)
            const EmptyState(
              'Пока нет категорий',
              'Создайте категории для удобного учёта.',
            ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: list.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _attempt(context, () async {
                    final items = [...list];
                    items.insert(newIndex, items.removeAt(oldIndex));
                    final order = {
                      for (var i = 0; i < items.length; i++) items[i].id: i,
                    };
                    await c.mutate(
                      (d) => d.copyWith(
                        categories: d.categories
                            .map(
                              (v) => v.kind == kind
                                  ? v.copyWith(order: order[v.id])
                                  : v,
                            )
                            .toList(),
                      ),
                    );
                  }),
              itemBuilder: (_, i) {
                final cat = list[i];
                return Padding(
                  key: ValueKey(cat.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () =>
                        _categoryEditor(context, kind: kind, category: cat),
                    child: Row(
                      children: [
                        CategoryBadge(category: cat),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (cat.subcategories.isNotEmpty)
                                Text(
                                  cat.subcategories.join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _categoryEditor(
  BuildContext context, {
  required EntryKind kind,
  Category? category,
}) async {
  final c = FinanceScope.of(context);
  final name = _text(category?.name ?? '');
  final subs = _text(category?.subcategories.join(', ') ?? '');
  var icon = category?.icon ?? 0;
  var color = category?.color ?? categoryColors.first;
  var bg = category?.background ?? 0xFF253025;
  await _edit(
    context,
    title: category == null ? 'Новая категория' : 'Настройка категории',
    controllers: [name, subs],
    fields: (set) => [
      _field(name, 'Название', maxLength: 80),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CategoryBadge(
          category: Category(
            id: 'preview',
            name: '',
            kind: kind,
            color: color,
            background: bg,
            icon: icon,
          ),
          size: 56,
        ),
        title: const Text('Иконка и цвет'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final result = await showIconPicker(
            context,
            icon: icon,
            color: color,
          );
          if (result != null) {
            set(() {
              icon = result.$1;
              color = result.$2;
            });
          }
        },
      ),
      const SizedBox(height: 12),
      const Text('Цвет иконки'),
      const SizedBox(height: 10),
      _colors(color, (v) => set(() => color = v)),
      const SizedBox(height: 18),
      const Text('Цвет фона'),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children:
            [
                  ...categoryColors.map(
                    (v) => Color(v).withValues(alpha: .18).toARGB32(),
                  ),
                  0xFF253025,
                  0xFF302821,
                  0xFF242C35,
                  0xFFF1EEE8,
                ]
                .map(
                  (v) => InkWell(
                    onTap: () => set(() => bg = v),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color(v),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: bg == v
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.withValues(alpha: .3),
                          width: bg == v ? 3 : 1,
                        ),
                      ),
                      child: bg == v ? const Icon(Icons.check, size: 18) : null,
                    ),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 18),
      _optional(subs, 'Подкатегории через запятую'),
    ],
    save: () => c.saveCategory(
      Category(
        id: category?.id ?? c.id(),
        name: name.text.trim(),
        kind: kind,
        color: color,
        background: bg,
        icon: icon,
        order:
            category?.order ??
            c.data.categories.where((a) => a.kind == kind).length,
        subcategories: subs.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(),
      ),
    ),
    delete: category == null ? null : () => c.deleteCategory(category.id),
  );
}
