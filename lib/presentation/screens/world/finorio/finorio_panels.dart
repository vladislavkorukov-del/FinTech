import 'package:flutter/material.dart' hide Text;

import '../../../../domain/finorio/finorio.dart';
import '../../../l10n_widgets.dart';
import 'finorio_art.dart';
import 'finorio_names.dart';
import 'finorio_screen.dart';
import 'finorio_sheets.dart';

const _ink = Color(0xFF3B1F3A);

/// A soft pearl card for Finorio's panels.
class FinCard extends StatelessWidget {
  const FinCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xF7FFFFFF), Color(0xF2F1EAF7)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x264B2346),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: _ink),
      child: child,
    ),
  );
}

/// The top: back, power, the current task and the menu.
class FinTopBar extends StatelessWidget {
  const FinTopBar({super.key, required this.state});
  final FinorioScreenState state;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: state.ticks,
    builder: (context, _, _) {
      final w = state.world!;
      final task = w.currentTask;
      final short = w.demand > w.supply;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _RoundButton(
                key: const ValueKey('finorio-back'),
                icon: Icons.arrow_back_rounded,
                label: 'Назад',
                onTap: () async {
                  await state.save();
                  if (context.mounted) Navigator.of(context).maybePop();
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FinCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Finorio',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Semantics(
                        label: 'Энергия: ${w.demand} из ${w.supply}',
                        excludeSemantics: true,
                        child: Row(
                          key: const ValueKey('finorio-power'),
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 18,
                              color: short
                                  ? const Color(0xFFE0566B)
                                  : const Color(0xFF2FB58C),
                            ),
                            Text(
                              '${w.demand} / ${w.supply}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _RoundButton(
                key: const ValueKey('finorio-menu'),
                icon: Icons.pause_rounded,
                label: 'Пауза и настройки',
                onTap: state.openMenu,
              ),
            ],
          ),
          if (task != null && w.tips) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => showFinorioTasks(context, state),
              child: FinCard(
                key: const ValueKey('finorio-task'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: FinPalette.teal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Задача ${task.id} из ${FinTasks.all.length}: ${task.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Финора: ${task.hint}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: _ink.withValues(alpha: .72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: Colors.white.withValues(alpha: .92),
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: const Color(0x404B2346),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(dimension: 48, child: Icon(icon, color: _ink)),
      ),
    ),
  );
}

/// Buildings in the order they are needed most.
const _order = [
  FinBuilding.belt,
  FinBuilding.fastBelt,
  FinBuilding.drill,
  FinBuilding.generator,
  FinBuilding.furnace,
  FinBuilding.assembler,
  FinBuilding.storage,
  FinBuilding.lab,
];

/// The bottom: tools, buildings to place, inventory and research.
class FinBuildBar extends StatelessWidget {
  const FinBuildBar({super.key, required this.state});
  final FinorioScreenState state;
  @override
  Widget build(BuildContext context) {
    final w = state.world!;
    final pad = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, pad + 8),
      child: FinCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _ToolChip(
                  key: const ValueKey('finorio-tool-select'),
                  icon: Icons.touch_app_outlined,
                  label: 'Выбор',
                  on: state.tool == FinTool.select,
                  onTap: () => _setTool(FinTool.select, null),
                ),
                _ToolChip(
                  key: const ValueKey('finorio-tool-rotate'),
                  icon: Icons.rotate_right_rounded,
                  label: const ['Вверх', 'Вправо', 'Вниз', 'Влево'][state.dir],
                  on: false,
                  turns: state.dir / 4,
                  onTap: () =>
                      state.update(() => state.dir = FinDir.turn(state.dir)),
                ),
                _ToolChip(
                  key: const ValueKey('finorio-tool-remove'),
                  icon: Icons.handyman_outlined,
                  label: 'Разобрать',
                  on: state.tool == FinTool.remove,
                  onTap: () => _setTool(FinTool.remove, null),
                ),
                _ToolChip(
                  key: const ValueKey('finorio-inventory'),
                  icon: Icons.inventory_2_outlined,
                  label: 'Инвентарь',
                  on: false,
                  onTap: () => showFinorioInventory(context, state),
                ),
                _ToolChip(
                  key: const ValueKey('finorio-research'),
                  icon: Icons.science_outlined,
                  label: 'Технологии',
                  on: false,
                  onTap: () => showFinorioResearch(context, state),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 78,
              // Eight tiles: built at once (no lazy list) and scrolled.
              child: SingleChildScrollView(
                key: const ValueKey('finorio-palette'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final kind in _order)
                      if (w.unlocked(kind))
                        _BuildingTile(
                          key: ValueKey('finorio-build-${kind.name}'),
                          kind: kind,
                          count: w.kits[kind] ?? 0,
                          affordable: w.affordable(kind),
                          selected:
                              state.tool == FinTool.build &&
                              state.building == kind,
                          onTap: () => _setTool(FinTool.build, kind),
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

  void _setTool(FinTool tool, FinBuilding? kind) => state.update(() {
    state.tool = tool;
    state.building = kind;
    state.overlay
      ..ghost = kind
      ..beltStartX = null
      ..beltStartY = null
      ..beltPreview = const [];
    state.inspected = null;
  });
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.turns = 0,
  });
  final IconData icon;
  final String label;
  final bool on;
  final double turns;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: on
                ? FinPalette.teal.withValues(alpha: .22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RotationTransition(
                turns: AlwaysStoppedAnimation(turns),
                child: Icon(icon, size: 20, color: _ink),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BuildingTile extends StatelessWidget {
  const _BuildingTile({
    super.key,
    required this.kind,
    required this.count,
    required this.affordable,
    required this.selected,
    required this.onTap,
  });
  final FinBuilding kind;
  final int count;
  final bool affordable, selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label:
        '${FinNames.building(kind)}, ${count > 0
            ? 'в наборе $count'
            : affordable
            ? 'из материалов'
            : 'нет материалов'}',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: selected
              ? FinPalette.teal.withValues(alpha: .22)
              : const Color(0x0F4B2346),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? FinPalette.teal : Colors.transparent,
            width: 2,
          ),
        ),
        child: Opacity(
          opacity: count > 0 || affordable ? 1 : .45,
          child: Column(
            children: [
              Expanded(child: FinBuildingIcon(kind)),
              Text(
                count > 0 ? '×$count' : (affordable ? 'из мат.' : '—'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A building drawn small, for menus (same art as on the map).
class FinBuildingIcon extends StatelessWidget {
  const FinBuildingIcon(this.kind, {super.key});
  final FinBuilding kind;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _IconPainter(kind), child: const SizedBox.expand());
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.kind);
  final FinBuilding kind;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s);
    final m = FinMachine(id: 0, kind: kind, x: 0, y: 0);
    if (m.isBelt) {
      paintBelt(canvas, m, 3, 0);
    } else {
      paintBuilding(canvas, m, 0, active: false);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.kind != kind;
}
