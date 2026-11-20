import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/planning/rules_engine.dart';
import '../../controller.dart';
import '../../controller_phase8.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';

/// Suggestions and notices the rules left — shown on the home screen and in
/// «Правила». Applying one changes only the app's own plan (never a bank).
class RuleNoticesCard extends StatelessWidget {
  const RuleNoticesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.maybeOf(context);
    if (c == null) return const SizedBox.shrink();
    final open = c.data.extras.notices.where((n) => !n.done).toList();
    if (open.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final n in open.reversed.take(3))
            Container(
              key: ValueKey('rule-notice-${n.id}'),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.rule_rounded, size: 17, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          n.text,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: ValueKey('rule-notice-dismiss-${n.id}'),
                        onPressed: () => c.dismissNotice(n.id),
                        child: Text(n.kind == 'notify' ? 'Понятно' : 'Не надо'),
                      ),
                      if (n.kind != 'notify')
                        FilledButton.tonal(
                          key: ValueKey('rule-notice-apply-${n.id}'),
                          onPressed: () => c.applyNotice(n),
                          child: const Text('Применить'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// «Правила»: personal «если → то» rules.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  Future<void> _fromPhrase(BuildContext context) async {
    final c = FinanceScope.of(context);
    final field = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Правило обычной фразой'),
        content: TextField(
          key: const ValueKey('rule-phrase'),
          controller: field,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Когда получаю оплату за проект, предлагай 20% в резерв',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('rule-phrase-ok'),
            onPressed: () => Navigator.pop(ctx, field.text),
            child: const Text('Разобрать'),
          ),
        ],
      ),
    );
    if (text == null || !context.mounted) return;
    final draft = RulesEngine.fromPhrase(text, c.data, c.id);
    if (draft == null) {
      showError(
        context,
        const FormatException(
          'Не поняла фразу. Соберите правило в конструкторе.',
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => RuleEditor(rule: draft)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rules = [...c.data.extras.rules]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final runs = c.data.extras.ruleRuns.reversed.take(20).toList();
    final names = {for (final r in rules) r.id: r.name};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Правила'),
        actions: [
          IconButton(
            key: const ValueKey('rules-phrase'),
            tooltip: 'Фразой',
            onPressed: () => _fromPhrase(context),
            icon: const Icon(Icons.short_text_rounded),
          ),
          IconButton(
            key: const ValueKey('rules-add'),
            tooltip: 'Новое правило',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RuleEditor(
                  rule: PersonalRule(
                    id: c.id(),
                    name: '',
                    trigger: 'income',
                    enabled: false,
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const RuleNoticesCard(),
          if (rules.isEmpty)
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Правил пока нет. Начните с готовых — они выключены, пока вы их не включите.',
                  ),
                  TextButton(
                    key: const ValueKey('rules-templates'),
                    onPressed: () => c.addRuleTemplates(),
                    child: const Text('Добавить пять готовых'),
                  ),
                ],
              ),
            ),
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                key: ValueKey('rule-${r.id}'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => RuleEditor(rule: r)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${RulesEngine.triggers[r.trigger]} → ${r.actions.map((a) => RulesEngine.actionTypes[a['type']]).join(', ')}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      key: ValueKey('rule-switch-${r.id}'),
                      value: r.enabled,
                      onChanged: (v) async {
                        try {
                          await c.saveRule(r.copyWith(enabled: v));
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (runs.isNotEmpty) ...[
            const SectionTitle('История срабатываний'),
            SurfaceCard(
              child: Column(
                children: [
                  for (final run in runs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        run.fired
                            ? Icons.check_circle_outline_rounded
                            : Icons.remove_circle_outline_rounded,
                        color: run.fired
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      title: Text(names[run.ruleId] ?? 'Правило'),
                      subtitle: Text(run.explanation),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Правила работают на телефоне по заданным условиям. Они уведомляют, '
            'предлагают или — если вы включили — меняют бюджет внутри приложения. '
            'Переводов в банке нет.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// The rule constructor: trigger, conditions, actions, priority, a check.
class RuleEditor extends StatefulWidget {
  const RuleEditor({super.key, required this.rule});
  final PersonalRule rule;
  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  late PersonalRule _r = widget.rule;
  late final _name = TextEditingController(text: widget.rule.name);
  List<RuleOutcome>? _check;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _set(PersonalRule r) => setState(() {
    _r = r;
    _check = null;
  });

  Widget _value(FinanceController c, Map<String, Object?> cond, int i) {
    void put(Object? v) {
      final list = [..._r.conditions];
      list[i] = {...cond, 'value': v};
      _set(_r.copyWith(conditions: list));
    }

    switch (cond['field']) {
      case 'category':
        return DropdownButton<String>(
          value: cond['value'] as String?,
          isExpanded: true,
          hint: const Text('Категория'),
          items: [
            for (final k in c.data.categories.where((k) => !k.archived))
              DropdownMenuItem(value: k.id, child: Text(k.name)),
          ],
          onChanged: put,
        );
      case 'account':
        return DropdownButton<String>(
          value: cond['value'] as String?,
          isExpanded: true,
          hint: const Text('Счёт'),
          items: [
            for (final a in c.data.accounts.where((a) => !a.archived))
              DropdownMenuItem(value: a.id, child: Text(a.name)),
          ],
          onChanged: put,
        );
      case 'budget':
        return DropdownButton<String>(
          value: cond['value'] as String?,
          isExpanded: true,
          hint: const Text('Бюджет'),
          items: [
            for (final b in c.data.budgets)
              DropdownMenuItem(value: b.id, child: Text(b.name)),
          ],
          onChanged: put,
        );
      case 'amountMin':
        return TextFormField(
          initialValue: cond['value'] == null
              ? ''
              : decimalMinor(
                  (cond['value'] as num).toInt(),
                ).replaceAll('.00', ''),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '₽'),
          onChanged: (v) {
            try {
              put(FinanceEngine.parseMinor(v));
            } catch (_) {}
          },
        );
      case 'percentMin':
        return TextFormField(
          initialValue: '${cond['value'] ?? 80}',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: '%'),
          onChanged: (v) => put(int.tryParse(v) ?? 80),
        );
      default:
        return TextFormField(
          initialValue: '${cond['value'] ?? ''}',
          decoration: const InputDecoration(hintText: 'текст'),
          onChanged: put,
        );
    }
  }

  Widget _action(FinanceController c, Map<String, Object?> a, int i) {
    void put(Map<String, Object?> v) {
      final list = [..._r.actions];
      list[i] = v;
      _set(_r.copyWith(actions: list));
    }

    switch (a['type']) {
      case 'notify':
        return TextFormField(
          initialValue: '${a['text'] ?? ''}',
          decoration: const InputDecoration(
            labelText: 'Текст ({сумма}, {процент}, {бюджет}, {цель})',
          ),
          onChanged: (v) => put({...a, 'text': v}),
        );
      case 'suggestGoals':
        final shares = Map<String, Object?>.from(a['shares'] as Map? ?? {});
        return Column(
          children: [
            for (final g in c.data.goals)
              Row(
                children: [
                  Expanded(child: Text(g.name)),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      initialValue: shares[g.id] == null
                          ? ''
                          : '${shares[g.id]}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(suffixText: '%'),
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        final next = {...shares};
                        if (n == null || n <= 0) {
                          next.remove(g.id);
                        } else {
                          next[g.id] = n;
                        }
                        put({...a, 'shares': next});
                      },
                    ),
                  ),
                ],
              ),
          ],
        );
      case 'restoreBudget':
        return SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Менять бюджет автоматически'),
          subtitle: const Text('Выключено — только предложение'),
          value: a['auto'] == true,
          onChanged: (v) => put({...a, 'auto': v}),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fit = RulesEngine.compatible[_r.trigger]!;
    final problems = RulesEngine.validate(
      _r.copyWith(name: _name.text),
      c.data,
    );
    final conflicts = RulesEngine.conflicts(_r, c.data.extras.rules);
    final exists = c.data.extras.rules.any((x) => x.id == _r.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(exists ? 'Правило' : 'Новое правило'),
        actions: [
          if (exists)
            IconButton(
              tooltip: 'Удалить',
              onPressed: () async {
                await c.deleteRule(_r.id);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          TextField(
            key: const ValueKey('rule-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const ValueKey('rule-trigger'),
            initialValue: _r.trigger,
            decoration: const InputDecoration(labelText: 'Когда'),
            items: [
              for (final e in RulesEngine.triggers.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => _set(
              PersonalRule(
                id: _r.id,
                name: _name.text,
                trigger: v!,
                enabled: _r.enabled,
                priority: _r.priority,
              ),
            ),
          ),
          const SectionTitle('Если'),
          for (var i = 0; i < _r.conditions.length; i++)
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    RulesEngine.conditionFields[_r.conditions[i]['field']] ??
                        '',
                  ),
                ),
                Expanded(flex: 5, child: _value(c, _r.conditions[i], i)),
                IconButton(
                  onPressed: () => _set(
                    _r.copyWith(conditions: [..._r.conditions]..removeAt(i)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          if (fit.$1.isNotEmpty)
            PopupMenuButton<String>(
              key: const ValueKey('rule-add-condition'),
              onSelected: (f) => _set(
                _r.copyWith(
                  conditions: [
                    ..._r.conditions,
                    {'field': f, 'value': null},
                  ],
                ),
              ),
              itemBuilder: (_) => [
                for (final f in fit.$1)
                  PopupMenuItem(
                    value: f,
                    child: Text(RulesEngine.conditionFields[f]!),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('+ условие'),
              ),
            ),
          const SectionTitle('То'),
          for (var i = 0; i < _r.actions.length; i++)
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          RulesEngine.actionTypes[_r.actions[i]['type']] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _set(
                          _r.copyWith(actions: [..._r.actions]..removeAt(i)),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                  _action(c, _r.actions[i], i),
                ],
              ),
            ),
          PopupMenuButton<String>(
            key: const ValueKey('rule-add-action'),
            onSelected: (t) => _set(
              _r.copyWith(
                actions: [
                  ..._r.actions,
                  {'type': t},
                ],
              ),
            ),
            itemBuilder: (_) => [
              for (final t in fit.$2)
                PopupMenuItem(
                  value: t,
                  child: Text(RulesEngine.actionTypes[t]!),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('+ действие'),
            ),
          ),
          Row(
            children: [
              const Text('Приоритет (меньше — раньше)'),
              const Spacer(),
              IconButton(
                onPressed: () => _set(_r.copyWith(priority: _r.priority - 1)),
                icon: const Icon(Icons.remove_rounded),
              ),
              Text('${_r.priority}'),
              IconButton(
                onPressed: () => _set(_r.copyWith(priority: _r.priority + 1)),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          for (final p in problems)
            Text('• $p', style: TextStyle(color: scheme.error)),
          for (final p in conflicts)
            Text('• $p', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('rule-check'),
            onPressed: problems.isNotEmpty
                ? null
                : () => setState(
                    () => _check = c.dryRun(_r.copyWith(name: _name.text)),
                  ),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Проверить на последних 30 днях'),
          ),
          if (_check != null)
            SurfaceCard(
              key: const ValueKey('rule-check-result'),
              child: _check!.isEmpty
                  ? const Text(
                      'За 30 дней не было событий этого типа. Данные не изменены.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Проверка — данные не изменены:'),
                        for (final o in _check!.take(10))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• ${o.explanation}'),
                          ),
                      ],
                    ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey('rule-save'),
            onPressed: problems.isNotEmpty
                ? null
                : () async {
                    try {
                      await c.saveRule(
                        _r.copyWith(name: _name.text.trim(), enabled: true),
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
            child: const Text('Сохранить и включить'),
          ),
        ),
      ),
    );
  }
}
