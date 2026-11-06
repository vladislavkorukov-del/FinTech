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
  bool showArchive = false;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final archiveCount = c.data.categories
        .where((a) => a.kind == kind && a.archived)
        .length;
    final list =
        c.data.categories
            .where((a) => a.kind == kind && a.archived == showArchive)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    Widget categoryRow(Category cat, int index) => Padding(
      key: ValueKey(cat.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        frosted: false,
        padding: const EdgeInsets.all(14),
        onTap: () => _categoryEditor(context, kind: kind, category: cat),
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
                  if (cat.archived)
                    Text(
                      'В архиве · история сохранена',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (cat.archived)
              IconButton(
                tooltip: 'Восстановить категорию',
                onPressed: () => _attempt(context, () async {
                  await c.saveCategory(cat.copyWith(archived: false));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('«${cat.name}» восстановлена')),
                    );
                  }
                }),
                icon: const Icon(Icons.unarchive_outlined),
              )
            else
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle_rounded),
                ),
              ),
          ],
        ),
      ),
    );
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<EntryKind>(
                    segments: const [
                      ButtonSegment(
                        value: EntryKind.expense,
                        label: Text('Расходы'),
                      ),
                      ButtonSegment(
                        value: EntryKind.income,
                        label: Text('Доходы'),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (value) => setState(() {
                      kind = value.first;
                      showArchive = false;
                    }),
                  ),
                ),
                if (archiveCount > 0 || showArchive) ...[
                  const SizedBox(height: 10),
                  FilterChip(
                    label: Text('Архив ($archiveCount)'),
                    selected: showArchive,
                    onSelected: (value) => setState(() => showArchive = value),
                  ),
                ],
              ],
            ),
          ),
          if (showArchive)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Архивные категории остаются в истории и аналитике. Восстановите категорию, чтобы использовать её для новых операций.',
              ),
            ),
          if (list.isEmpty)
            Expanded(
              child: SingleChildScrollView(
                child: EmptyState(
                  showArchive
                      ? 'Архив пуст'
                      : 'Нет категорий ${kind == EntryKind.expense ? 'расходов' : 'доходов'}',
                  showArchive
                      ? 'Все категории этого типа активны.'
                      : 'Добавьте категорию кнопкой +.',
                ),
              ),
            )
          else
            Expanded(
              child: showArchive
                  ? ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: list.length,
                      itemBuilder: (_, i) => categoryRow(list[i], i),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: list.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          _attempt(context, () async {
                            final items = [...list];
                            items.insert(newIndex, items.removeAt(oldIndex));
                            final order = {
                              for (var i = 0; i < items.length; i++)
                                items[i].id: i,
                            };
                            await c.mutate(
                              (d) => d.copyWith(
                                categories: d.categories
                                    .map(
                                      (v) => v.kind == kind && !v.archived
                                          ? v.copyWith(order: order[v.id])
                                          : v,
                                    )
                                    .toList(),
                              ),
                            );
                          }),
                      itemBuilder: (_, i) => categoryRow(list[i], i),
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
  final theme = Theme.of(context);
  var selectedKind = category?.kind ?? kind;
  var color =
      category?.color ??
      categoryColors[c.data.categories.length % categoryColors.length];
  var bg =
      category?.background ??
      Color.alphaBlend(
        Color(color).withValues(alpha: .16),
        theme.colorScheme.surface,
      ).toARGB32();
  await _edit(
    context,
    title: category == null ? 'Новая категория' : 'Настройка категории',
    controllers: [name, subs],
    fields: (set) => [
      if (category == null) ...[
        const Text('Тип категории'),
        const SizedBox(height: 10),
        SegmentedButton<EntryKind>(
          key: const ValueKey('category-kind'),
          segments: const [
            ButtonSegment(value: EntryKind.expense, label: Text('Расход')),
            ButtonSegment(value: EntryKind.income, label: Text('Доход')),
          ],
          selected: {selectedKind},
          onSelectionChanged: (value) => set(() => selectedKind = value.first),
        ),
        const SizedBox(height: 18),
      ] else ...[
        Text(
          'Тип: ${category.kind == EntryKind.expense ? 'Расход' : 'Доход'}',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Тип существующей категории сохраняется для корректной истории операций.',
        ),
        const SizedBox(height: 18),
      ],
      _field(name, 'Название', maxLength: 80),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CategoryBadge(
          category: Category(
            id: 'preview',
            name: '',
            kind: selectedKind,
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
                  0xFF231A12,
                  0xFF30251B,
                  0xFF403021,
                  0xFF886B4B,
                  0xFFE7DDD0,
                  0xFFF7F5F1,
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
      if (category != null) ...[
        const SizedBox(height: 16),
        if (category.archived)
          OutlinedButton.icon(
            icon: const Icon(Icons.unarchive_outlined),
            label: const Text('Восстановить категорию'),
            onPressed: () => _attempt(context, () async {
              await c.saveCategory(category.copyWith(archived: false));
              if (context.mounted) {
                Navigator.pop(context);
              }
            }),
          )
        else
          _CategoryRemoveAction(controller: c, category: category),
      ],
    ],
    save: () => c.saveCategory(
      Category(
        id: category?.id ?? c.id(),
        name: name.text.trim(),
        kind: selectedKind,
        archived: category?.archived ?? false,
        color: color,
        background: bg,
        icon: icon,
        order:
            category?.order ??
            c.data.categories.where((a) => a.kind == selectedKind).length,
        subcategories: subs.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(),
      ),
    ),
  );
}

class _CategoryRemoveAction extends StatefulWidget {
  const _CategoryRemoveAction({
    required this.controller,
    required this.category,
  });
  final FinanceController controller;
  final Category category;
  @override
  State<_CategoryRemoveAction> createState() => _CategoryRemoveActionState();
}

class _CategoryRemoveActionState extends State<_CategoryRemoveAction> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final id = widget.category.id;
    final linked =
        c.data.entries.any((e) => e.categoryId == id) ||
        c.data.budgets.any((b) => b.categoryId == id) ||
        c.data.recurring.any((r) => r.categoryId == id);
    return TextButton.icon(
      icon: Icon(
        linked ? Icons.archive_outlined : Icons.delete_outline_rounded,
      ),
      label: Text(linked ? 'Переместить в архив' : 'Удалить категорию'),
      onPressed: busy
          ? null
          : () async {
              final accepted = await confirm(
                context,
                linked
                    ? 'Переместить категорию в архив?'
                    : 'Удалить категорию?',
                linked
                    ? 'Категория исчезнет из выбора для новых операций. Все операции, бюджеты и аналитика сохранятся. Категорию можно восстановить из архива.'
                    : 'У категории нет связанных операций, бюджетов или регулярных платежей. Она будет удалена.',
              );
              if (!accepted || !context.mounted) {
                return;
              }
              setState(() => busy = true);
              try {
                await c.deleteCategory(id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        linked
                            ? 'Категория в архиве. История сохранена.'
                            : 'Категория удалена.',
                      ),
                    ),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  showError(context, error);
                }
              } finally {
                if (mounted) {
                  setState(() => busy = false);
                }
              }
            },
    );
  }
}
