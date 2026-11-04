part of 'management.dart';

const _iconNames = [
  'Продукты корзина магазин',
  'Кафе ресторан еда',
  'Транспорт автобус',
  'Автомобиль машина',
  'Жильё дом',
  'Коммунальные электричество',
  'Здоровье сердце',
  'Аптека лекарства',
  'Развлечения кино',
  'Подписки',
  'Покупки сумка',
  'Одежда',
  'Подарки',
  'Путешествия самолёт',
  'Образование школа',
  'Дети',
  'Животные',
  'Налоги чек',
  'Кредит карта',
  'Прочее',
  'Зарплата работа',
  'Подработка ноутбук',
  'Бизнес магазин',
  'Проценты',
  'Инвестиции',
  'Возвраты',
  'Кошелёк наличные',
  'Накопления',
  'Банк счёт',
  'Отпуск пляж',
  'Техника',
  'Безопасность подушка',
  'Игры',
  'Спорт',
  'Кофе',
  'Музыка',
];
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
  late int icon = widget.icon;
  late int color = widget.color;
  String query = '';
  String group = 'Все';
  @override
  Widget build(BuildContext context) {
    final matches = List.generate(iconChoices.length, (i) => i)
        .where(
          (i) =>
              _iconNames[i].toLowerCase().contains(query.toLowerCase()) &&
              (group == 'Все' ||
                  (group == 'Финансы'
                      ? i >= 17 && i <= 28
                      : group == 'Повседневное'
                      ? i < 13
                      : i >= 13 && i != 17 && !(i >= 18 && i <= 28))),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: math.max(
          160.0,
          (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Row(
                      children: [
                        CategoryBadge(
                          icon: categoryIcon(icon),
                          color: Color(color),
                          size: 56,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Выберите иконку',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Поиск: кафе, дом, отпуск…',
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: ['Все', 'Финансы', 'Повседневное', 'Досуг']
                          .map(
                            (v) => ChoiceChip(
                              label: Text(v),
                              selected: group == v,
                              onSelected: (_) => setState(() => group = v),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    _colors(color, (v) => setState(() => color = v)),
                    const SizedBox(height: 14),
                    if (matches.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Ничего не найдено'),
                      ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 65,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                      itemCount: matches.length,
                      itemBuilder: (_, n) {
                        final i = matches[n];
                        return Semantics(
                          label: _iconNames[i],
                          selected: icon == i,
                          button: true,
                          child: InkWell(
                            onTap: () => setState(() => icon = i),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: icon == i
                                    ? Color(color).withValues(alpha: .25)
                                    : Theme.of(context).colorScheme.onSurface
                                          .withValues(alpha: .04),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(iconChoices[i], color: Color(color)),
                            ),
                          ),
                        );
                      },
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
