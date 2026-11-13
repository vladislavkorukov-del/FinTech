import 'package:flutter/material.dart' hide Text;

import '../../../../domain/finorio/finorio.dart';
import '../../../l10n_widgets.dart';
import 'finorio_art.dart';
import 'finorio_names.dart';
import 'finorio_panels.dart';
import 'finorio_screen.dart';

const _ink = Color(0xFF3B1F3A);

/// A machine's panel: state, recipe, buffers, speed, power and actions.
/// It covers the bottom of the screen only; the map stays in view.
class FinInspector extends StatelessWidget {
  const FinInspector({super.key, required this.state, required this.machine});
  final FinorioScreenState state;
  final FinMachine machine;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, media.padding.bottom + 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * .46),
        child: FinCard(
          child: ValueListenableBuilder(
            valueListenable: state.ticks,
            builder: (context, _, _) =>
                SingleChildScrollView(child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final w = state.world!, m = machine;
    final recipe = FinConfig.recipe(m.crafting ?? m.recipe);
    final spec = m.spec;
    final share = m.powered / FinRules.work;
    String speed() {
      if (m.kind == FinBuilding.drill) {
        return '${(60 / FinRules.mineSeconds * share).toStringAsFixed(1)} / мин';
      }
      if (recipe != null &&
          (m.kind == FinBuilding.furnace || m.kind == FinBuilding.assembler)) {
        return '${(60 / recipe.seconds * share).toStringAsFixed(1)} ${FinNames.item(recipe.output).toLowerCase()} / мин';
      }
      if (m.isBelt) {
        return '${FinRules.beltSpeed[m.kind]! * FinRules.ticksPerSecond ~/ FinRules.beltSpacing} предм. / с';
      }
      return '—';
    }

    double cycle() {
      if (m.kind == FinBuilding.drill) {
        return m.progress / (FinRules.mineTicks * FinRules.work);
      }
      if (m.kind == FinBuilding.lab) {
        final t = FinConfig.tech(m.researching ?? '');
        return t == null
            ? 0
            : m.progress /
                  (t.seconds * FinRules.ticksPerSecond * FinRules.work);
      }
      final r = FinConfig.recipe(m.crafting);
      return r == null ? 0 : m.progress / (r.ticks * FinRules.work);
    }

    final ore = FinConfig.deposits[w.terrain.at(m.x, m.y)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox.square(dimension: 40, child: FinBuildingIcon(m.kind)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    FinNames.building(m.kind),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: FinNames.statusColor(m.status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        FinNames.status(m.status, m.kind),
                        key: const ValueKey('finorio-status'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('finorio-inspector-close'),
              tooltip: 'Закрыть',
              onPressed: () => state.update(() => state.inspected = null),
              icon: const Icon(Icons.close_rounded, color: _ink),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (m.kind == FinBuilding.drill && ore != null)
          _line('Добывает', FinNames.item(ore)),
        if (m.kind == FinBuilding.furnace ||
            m.kind == FinBuilding.assembler) ...[
          Text(
            'Рецепт',
            style: TextStyle(fontSize: 12, color: _ink.withValues(alpha: .7)),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in FinConfig.recipesFor(m.kind))
                ChoiceChip(
                  key: ValueKey('finorio-recipe-${r.id}'),
                  label: Text(_recipeText(r)),
                  selected: m.recipe == r.id,
                  onSelected: (_) {
                    w.setRecipe(m.id, r.id);
                    state.changed();
                  },
                ),
            ],
          ),
          if (m.kind == FinBuilding.furnace && m.recipe == null)
            Text(
              'Печь сама выберет рецепт по первой поданной руде.',
              style: TextStyle(fontSize: 12, color: _ink.withValues(alpha: .7)),
            ),
          const SizedBox(height: 6),
        ],
        if (m.kind == FinBuilding.lab) ..._lab(context, w, m),
        if (spec.inputCap > 0 || m.kind == FinBuilding.storage)
          _buffer(
            'Вход',
            m.input,
            m.kind == FinBuilding.storage
                ? FinRules.storageCapacity
                : spec.inputCap,
            total: m.kind == FinBuilding.storage,
          ),
        if (spec.outputCap > 0) _buffer('Готово', m.output, spec.outputCap),
        if (m.isBelt) _line('На ленте', '${m.items.length} из 2'),
        if (m.kind == FinBuilding.generator) ...[
          _line('Мощность', '${spec.power} ед.'),
          _line(
            'Сеть: потребление / производство',
            '${w.demand} / ${w.supply}',
          ),
          _line(
            'Топливо в работе',
            '${(m.energy / spec.power / FinRules.ticksPerSecond).ceil()} с',
          ),
        ] else if (spec.power > 0) ...[
          _line(
            'Энергопотребление',
            '${spec.power} ед. × ${(share * 100).round()}%',
          ),
          _line('Скорость', speed()),
        ] else if (m.isBelt)
          _line('Скорость', speed()),
        if (m.kind != FinBuilding.storage &&
            !m.isBelt &&
            m.kind != FinBuilding.generator) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              key: const ValueKey('finorio-cycle'),
              value: cycle().clamp(0.0, 1.0),
              minHeight: 8,
              color: FinPalette.teal,
              backgroundColor: const Color(0x1A4B2346),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('finorio-rotate'),
              onPressed: () {
                w.rotate(m.id);
                state.changed();
              },
              icon: const Icon(Icons.rotate_right_rounded),
              label: const Text('Повернуть'),
            ),
            if (m.kind == FinBuilding.generator)
              FilledButton.tonalIcon(
                key: const ValueKey('finorio-fuel'),
                onPressed: (w.inventory[FinItem.biomass] ?? 0) == 0
                    ? null
                    : () {
                        final n = w.insert(m.id, FinItem.biomass, 10);
                        state.say(
                          n > 0 ? 'Загружено биомассы: $n' : 'Генератор полон',
                        );
                        state.changed();
                      },
                icon: const Icon(Icons.local_fire_department_outlined),
                label: Text('Топливо (${w.inventory[FinItem.biomass] ?? 0})'),
              ),
            if (m.output.isNotEmpty ||
                m.kind == FinBuilding.storage && m.input.isNotEmpty)
              FilledButton.tonalIcon(
                key: const ValueKey('finorio-collect'),
                onPressed: () {
                  var n = 0;
                  for (final i in {
                    ...m.output.keys,
                    if (m.kind == FinBuilding.storage) ...m.input.keys,
                  }.toList()) {
                    n += w.collect(m.id, i, 1 << 30);
                  }
                  state.say('В инвентарь: $n');
                  state.changed();
                },
                icon: const Icon(Icons.move_to_inbox_outlined),
                label: const Text('Забрать'),
              ),
            TextButton.icon(
              key: const ValueKey('finorio-remove'),
              onPressed: () {
                w.remove(m.id);
                state.inspected = null;
                state.say('Разобрано: набор и содержимое в инвентаре');
                state.changed();
              },
              icon: const Icon(Icons.handyman_outlined),
              label: const Text('Разобрать'),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _lab(BuildContext context, FinWorld w, FinMachine m) {
    final tech = FinConfig.tech(m.researching ?? '');
    if (tech == null) {
      final next = FinConfig.research.where(w.canResearch).firstOrNull;
      return [
        Text(
          next == null
              ? 'Доступные исследования открыты'
              : 'Исследование не выбрано',
          style: const TextStyle(fontSize: 13),
        ),
        if (next != null)
          TextButton(
            onPressed: () {
              w.startResearch(m.id, next.id);
              state.changed();
            },
            child: Text('Начать: ${FinNames.tech(next.id)}'),
          ),
      ];
    }
    final need = tech.cost[FinItem.circuit] ?? 0;
    return [
      _line('Исследование', FinNames.tech(tech.id)),
      _line('Схемы', '${m.input[FinItem.circuit] ?? 0} из $need'),
      Text(
        FinNames.techResult(tech.id),
        style: TextStyle(fontSize: 12, color: _ink.withValues(alpha: .7)),
      ),
      if ((w.inventory[FinItem.circuit] ?? 0) > 0)
        TextButton(
          onPressed: () {
            w.insert(m.id, FinItem.circuit, need);
            state.changed();
          },
          child: Text(
            'Подать схемы из инвентаря (${w.inventory[FinItem.circuit]})',
          ),
        ),
    ];
  }

  String _recipeText(FinRecipe r) {
    final ins = r.inputs.entries
        .map((e) => '${e.value} ${FinNames.item(e.key).toLowerCase()}')
        .join(' + ');
    return '${FinNames.recipe(r.id)} ← $ins · ${r.seconds.toStringAsFixed(0)} с';
  }

  Widget _line(String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            a,
            style: TextStyle(fontSize: 13, color: _ink.withValues(alpha: .72)),
          ),
        ),
        Text(
          b,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _buffer(
    String title,
    Map<FinItem, int> items,
    int cap, {
    bool total = false,
  }) {
    final used = items.values.fold(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total ? '$title: $used из $cap' : title,
            style: TextStyle(fontSize: 12, color: _ink.withValues(alpha: .7)),
          ),
          const SizedBox(height: 3),
          if (items.isEmpty)
            const Text('пусто', style: TextStyle(fontSize: 13))
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final e in items.entries)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: FinItemIcon(e.key, size: 20),
                    label: Text(
                      total
                          ? '${FinNames.item(e.key)}: ${e.value}'
                          : '${FinNames.item(e.key)}: ${e.value} / $cap',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
