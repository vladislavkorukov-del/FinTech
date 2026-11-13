import 'package:flutter/material.dart' hide Text;

import '../../../../domain/finorio/finorio.dart';
import '../../../controller.dart';
import '../../../l10n_widgets.dart';
import 'finorio_art.dart';
import 'finorio_names.dart';
import 'finorio_panels.dart';
import 'finorio_screen.dart';

const _ink = Color(0xFF3B1F3A);

Future<void> showFinorioInventory(
  BuildContext context,
  FinorioScreenState state,
) {
  final w = state.world!;
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Инвентарь',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Наборы построек',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final k in FinBuilding.values)
            if ((w.kits[k] ?? 0) > 0)
              ListTile(
                dense: true,
                leading: SizedBox.square(
                  dimension: 32,
                  child: FinBuildingIcon(k),
                ),
                title: Text(FinNames.building(k)),
                trailing: Text('${w.kits[k]}'),
              ),
          const SizedBox(height: 8),
          const Text(
            'Материалы',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (w.inventory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Пусто. Забирайте готовое со складов и станков.'),
            ),
          for (final e in w.inventory.entries)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: FinPalette.item(e.key),
                radius: 10,
              ),
              title: Text(FinNames.item(e.key)),
              trailing: Text('${e.value}'),
            ),
        ],
      ),
    ),
  );
}

Future<void> showFinorioTasks(BuildContext context, FinorioScreenState state) {
  final w = state.world!;
  final sparks = FinanceScope.maybeOf(context)?.data.world.sparks;
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            'Задачи · ${w.tasksDone.length} из ${FinTasks.all.length}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (sparks != null)
            Text(
              'Искры Мира Финоры: $sparks · за каждую задачу +15, за технологию +50',
              style: const TextStyle(fontSize: 12),
            ),
          for (final t in FinTasks.all)
            ListTile(
              leading: Icon(
                w.tasksDone.contains(t.id)
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: w.tasksDone.contains(t.id)
                    ? const Color(0xFF2FB58C)
                    : _ink.withValues(alpha: .4),
              ),
              title: Text(t.title),
              subtitle: Text(t.hint),
            ),
        ],
      ),
    ),
  );
}

Future<void> showFinorioResearch(
  BuildContext context,
  FinorioScreenState state,
) {
  final w = state.world!;
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Технологии',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Text(
            'Исследования ведёт терминал: подайте ему схемы и энергию.',
            style: TextStyle(fontSize: 12),
          ),
          for (final t in FinConfig.research)
            ListTile(
              key: ValueKey('finorio-tech-${t.id}'),
              enabled: t.implemented,
              leading: Icon(
                w.researched.contains(t.id)
                    ? Icons.verified_rounded
                    : t.implemented
                    ? Icons.science_outlined
                    : Icons.lock_clock_outlined,
                color: w.researched.contains(t.id)
                    ? const Color(0xFF2FB58C)
                    : null,
              ),
              title: Text(FinNames.tech(t.id)),
              subtitle: Text(
                w.researched.contains(t.id)
                    ? 'Открыто. ${FinNames.techResult(t.id)}'
                    : t.implemented
                    ? '${t.cost[FinItem.circuit]} схем, ${t.seconds.toStringAsFixed(0)} с. ${FinNames.techResult(t.id)}'
                    : 'В следующих обновлениях',
              ),
            ),
        ],
      ),
    ),
  );
}

Future<String?> showFinorioMenu(
  BuildContext context,
  FinorioScreenState state,
) {
  final w = state.world!;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Пауза'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Сетка на карте'),
              value: w.showGrid,
              onChanged: (v) => setLocal(() => w.showGrid = v),
            ),
            SwitchListTile(
              title: const Text('Подсказки Финоры'),
              value: w.tips,
              onChanged: (v) => setLocal(() => w.tips = v),
            ),
            const Text(
              'Пока игра закрыта, завод стоит на паузе.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final sure = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Начать новую карту?'),
                  content: const Text(
                    'Завод и задачи начнутся заново. Полученные искры останутся.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Отмена'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Начать'),
                    ),
                  ],
                ),
              );
              if (sure == true && context.mounted) {
                Navigator.pop(context, 'restart');
              }
            },
            child: const Text('Новая карта'),
          ),
          TextButton(
            key: const ValueKey('finorio-save-exit'),
            onPressed: () => Navigator.pop(context, 'exit'),
            child: const Text('Сохранить и выйти'),
          ),
          FilledButton(
            key: const ValueKey('finorio-resume'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    ),
  );
}
