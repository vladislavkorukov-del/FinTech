part of 'management.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, this.initialGoalId});
  final String? initialGoalId;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialGoalId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final goal = FinanceScope.of(context).goal(widget.initialGoalId);
        if (goal != null) _goalEditor(context, goal: goal);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Копим на мечты'),
        actions: [
          IconButton(
            tooltip: 'Создать цель',
            onPressed: () => _goalEditor(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Большие планы.\nМаленькие шаги.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Откладывайте на важное переводом со своего счёта. Деньги остаются вашими, а мечта становится ближе.',
          ),
          const SizedBox(height: 20),
          if (c.data.goals.isEmpty)
            const EmptyState(
              'На что копим?',
              'Отпуск, подушка безопасности или большая мечта.',
            ),
          // 1.28: swipe left to delete a dream.
          ...c.data.goals.map(
            (g) => SwipeToDelete(
              key: ValueKey('swipe-goal-${g.id}'),
              title: 'Удалить мечту «${g.name}»?',
              message:
                  'Мечта и её цель исчезнут. Мечту с пополнениями '
                  'удалить нельзя — сначала уберите пополнения.',
              onDelete: () => c.deleteGoal(g.id),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: GoalCard(
                  goal: g,
                  onTap: () => _goalEditor(context, goal: g),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.goal, this.onTap});
  final Goal goal;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final saved = FinanceEngine.goalSaved(goal, c.data.entries);
    final contributed = saved - goal.savedMinor;
    final ratio = goal.targetMinor > 0 ? saved / goal.targetMinor : 0.0;
    return SurfaceCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryBadge(
                icon: categoryIcon(goal.icon),
                color: Color(goal.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  goal.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('${(ratio * 100).round()}% накоплено'),
          const SizedBox(height: 8),
          Text(
            money(saved, goal.currency),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('из ${money(goal.targetMinor, goal.currency)}'),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 7,
              color: Color(goal.color),
              backgroundColor: Color(goal.color).withValues(alpha: .12),
            ),
          ),
          if (goal.deadline != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'До ${_date(goal.deadline!, c)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SavingsPace(goal: goal, saved: saved),
          ),
          if (contributed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Переводами отложено ${money(contributed, goal.currency)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => showEntryEditor(
                context,
                kind: EntryKind.transfer,
                goalId: goal.id,
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Пополнить мечту'),
            ),
          ),
          if (ratio >= 1)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Цель достигнута!'),
            ),
        ],
      ),
    );
  }
}

Future<void> _goalEditor(BuildContext context, {Goal? goal}) async {
  final c = FinanceScope.of(context);
  final name = _text(goal?.name ?? '');
  final target = _text(goal == null ? '' : _amount(goal.targetMinor));
  final saved = _text(_amount(goal?.savedMinor ?? 0));
  var currency = goal?.currency ?? c.currency;
  final hasLinkedTransfers =
      goal != null && c.data.entries.any((e) => e.toGoalId == goal.id);
  var deadline = goal?.deadline;
  var color = goal?.color ?? categoryColors[1];
  var icon = goal?.icon ?? 29;
  await _edit(
    context,
    title: goal == null ? 'Новая мечта' : 'Настроить мечту',
    controllers: [name, target, saved],
    fields: (set) => [
      _field(name, 'Название', maxLength: 80, hint: 'Например: Отпуск на море'),
      _field(target, 'Хочу накопить', amount: true, hint: 'Например: 150 000'),
      _field(
        saved,
        'Начальный резерв',
        amount: true,
        hint: 'Сколько уже отложено, можно 0',
      ),
      const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text(
          'Только сумма, отложенная до начала учёта. Она не создаёт деньги и не меняет баланс счетов. Новые пополнения добавляйте переводом — они учитываются отдельно.',
        ),
      ),
      _select(
        'Валюта',
        currency,
        {for (final v in currencies) v: v},
        (v) => set(() => currency = v),
        enabled: !hasLinkedTransfers,
      ),
      if (hasLinkedTransfers)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text('Валюта закреплена: с мечтой уже связаны переводы.'),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(deadline == null ? 'Установить срок' : _date(deadline!, c)),
        leading: const Icon(Icons.event_outlined),
        trailing: deadline == null
            ? null
            : IconButton(
                tooltip: 'Без срока',
                onPressed: () => set(() => deadline = null),
                icon: const Icon(Icons.close),
              ),
        onTap: () async {
          final v = await showDatePicker(
            context: context,
            initialDate:
                deadline ?? DateTime.now().add(const Duration(days: 90)),
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (v != null) {
            set(() => deadline = v);
          }
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Иконка'),
        leading: CategoryBadge(icon: categoryIcon(icon), color: Color(color)),
        onTap: () async {
          final v = await showIconPicker(context, icon: icon, color: color);
          if (v != null) {
            set(() {
              icon = v.$1;
              color = v.$2;
            });
          }
        },
      ),
      _colors(color, (v) => set(() => color = v)),
    ],
    save: () async {
      final t = FinanceEngine.parseMinor(target.text),
          s = FinanceEngine.parseMinor(saved.text);
      if (t <= 0 || s < 0) {
        throw const FormatException(
          'Цель должна быть больше нуля, накопления — неотрицательными.',
        );
      }
      await c.saveGoal(
        Goal(
          id: goal?.id ?? c.id(),
          name: name.text.trim(),
          currency: currency,
          targetMinor: t,
          savedMinor: s,
          deadline: deadline,
          color: color,
          icon: icon,
        ),
      );
    },
    delete: goal == null ? null : () => c.deleteGoal(goal.id),
  );
}
