import 'package:flutter/material.dart' hide Text;

import '../../../../domain/finorio/finorio.dart';
import '../../../controller.dart';
import '../../../l10n_widgets.dart';
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
                key: ValueKey('finorio-inventory-${k.name}'),
                leading: SizedBox.square(
                  dimension: 40,
                  child: FinBuildingIcon(k),
                ),
                title: Text(FinNames.building(k)),
                subtitle: Text(
                  FinNames.buildingAbout(k),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('×${w.kits[k]}'),
                onTap: () => showFinorioBuildingInfo(context, state, k),
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
              key: ValueKey('finorio-inventory-${e.key.name}'),
              leading: FinItemIcon(e.key, size: 36),
              title: Text(FinNames.item(e.key)),
              subtitle: Text(FinNames.itemAbout(e.key)),
              trailing: Text('×${e.value}'),
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Местность',
                style: TextStyle(
                  fontSize: 13,
                  color: _ink.withValues(alpha: .7),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final key in FinConfig.terrainThemes)
                  ChoiceChip(
                    key: ValueKey('finorio-theme-$key'),
                    label: Text(FinNames.terrainTheme(key)),
                    selected: w.terrainTheme == key,
                    onSelected: (_) async {
                      await state.setTerrainTheme(key);
                      setLocal(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
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

/// What a building is: its picture, description, cost, power and recipes.
Future<void> showFinorioBuildingInfo(
  BuildContext context,
  FinorioScreenState state,
  FinBuilding kind,
) {
  final w = state.world!;
  final spec = FinConfig.specs[kind]!;
  final recipes = FinConfig.recipesFor(kind);
  Widget row(String a, Widget b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            a,
            style: TextStyle(fontSize: 13, color: _ink.withValues(alpha: .7)),
          ),
        ),
        Expanded(child: b),
      ],
    ),
  );
  Widget items(Map<FinItem, int> m) => Wrap(
    spacing: 10,
    runSpacing: 4,
    children: [
      for (final e in m.entries)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FinItemIcon(e.key, size: 22),
            const SizedBox(width: 4),
            Text(
              '${e.value} ${FinNames.item(e.key).toLowerCase()}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
    ],
  );
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        key: ValueKey('finorio-info-${kind.name}'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              SizedBox.square(dimension: 64, child: FinBuildingIcon(kind)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      FinNames.building(kind),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      (w.kits[kind] ?? 0) > 0
                          ? 'В наборе: ${w.kits[kind]}'
                          : 'Строится из материалов',
                      style: TextStyle(
                        fontSize: 13,
                        color: _ink.withValues(alpha: .7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            FinNames.buildingAbout(kind),
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 10),
          row('Стоимость', items(spec.cost)),
          row(
            'Энергия',
            Text(
              kind == FinBuilding.generator
                  ? 'даёт до ${spec.power} ед.'
                  : spec.power == 0
                  ? 'не нужна'
                  : '${spec.power} ед. при работе',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (kind == FinBuilding.drill)
            row(
              'Добывает',
              items({for (final i in FinConfig.deposits.values) i: 1}),
            ),
          for (final r in recipes)
            row(
              FinNames.recipe(r.id),
              Row(
                children: [
                  Flexible(child: items(r.inputs)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 16),
                  ),
                  FinItemIcon(r.output, size: 22),
                  Text(
                    ' за ${r.seconds.toStringAsFixed(0)} с',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
