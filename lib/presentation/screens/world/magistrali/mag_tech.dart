import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_fleet.dart';
import 'mag_hud.dart';
import 'mag_lore.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// The technology tree: four branches drawn as chains of nodes, each with
/// its story, effect, cost and what it still needs.
Future<void> showTechSheet(MagistraliScreenState state, [MagBranch? start]) {
  var branch = start ?? MagBranch.fleet;
  return showModalBottomSheet<void>(
    context: state.context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF7FAF8),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(state.context).size.height * .88,
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => ValueListenableBuilder<int>(
        key: const ValueKey('mag-tech'),
        valueListenable: state.ticks,
        builder: (context, _, _) {
          final w = state.world;
          final nodes = MagTechTree.of(branch).toList()
            ..sort((a, b) {
              final l = a.level.compareTo(b.level);
              return l != 0 ? l : a.cost.compareTo(b.cost);
            });
          final learned = w.techs.length, total = MagTechTree.all.length;
          return SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Древо технологий', style: magTitle),
                          ),
                          TextButton.icon(
                            key: const ValueKey('mag-tech-trucks'),
                            onPressed: () {
                              Navigator.pop(context);
                              unawaited(showUpgradesSheet(state));
                            },
                            icon: const Icon(
                              Icons.local_shipping_rounded,
                              size: 18,
                            ),
                            label: const Text('Машины'),
                          ),
                        ],
                      ),
                      Text(
                        'Изучено $learned из $total · уровень ${w.level} · доставок ${w.deliveries}',
                        style: magMuted,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final b in MagBranch.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  key: ValueKey('mag-branch-${b.name}'),
                                  label: Text(
                                    '${branchName(b)} ${MagTechTree.of(b).where((t) => w.techs.contains(t.id)).length}/${MagTechTree.of(b).length}',
                                  ),
                                  selected: branch == b,
                                  onSelected: (_) => setSheet(() => branch = b),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(branchLore(branch), style: magMuted),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    itemCount: nodes.length,
                    itemBuilder: (context, k) =>
                        _node(state, nodes[k], k == nodes.length - 1),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Widget _node(MagistraliScreenState state, MagTech t, bool last) {
  final w = state.world;
  final done = w.techs.contains(t.id);
  final blocker = done ? null : w.techBlocker(t);
  final ready = !done && blocker == null;
  final color = done
      ? MagPalette.mint
      : ready
      ? MagPalette.teal
      : const Color(0xFFB4BEC1);
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The chain: a dot and a line down to the next node.
        SizedBox(
          width: 28,
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: done ? color : Colors.white,
                  border: Border.all(color: color, width: 3),
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: Colors.white,
                      )
                    : null,
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 3,
                    color: color.withValues(alpha: .5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            key: ValueKey('mag-tech-${t.id}'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: magCard(16).copyWith(
              border: Border.all(
                color: ready ? MagPalette.mint : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.lore,
                  style: magMuted.copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 6),
                Text(
                  t.effect,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: MagPalette.teal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    'ур. ${t.level}',
                    if (t.deliveries > 0) '${t.deliveries} доставок',
                    if (t.requires.isNotEmpty)
                      'после: ${t.requires.map((r) => MagTechTree.byId(r)!.title).join(', ')}',
                  ].join(' · '),
                  style: magMuted,
                ),
                const SizedBox(height: 6),
                if (done)
                  const Text(
                    'Изучено',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: MagPalette.mint,
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          blocker ??
                              (t.cost > w.money
                                  ? 'Не хватает кредитов'
                                  : 'Можно изучить'),
                          style: TextStyle(
                            fontSize: 12,
                            color: blocker == null && t.cost <= w.money
                                ? MagPalette.teal
                                : const Color(0xFF8A9599),
                          ),
                        ),
                      ),
                      FilledButton(
                        key: ValueKey('mag-research-${t.id}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: MagPalette.mint,
                        ),
                        onPressed: ready && t.cost <= w.money
                            ? () => state.report(
                                w.research(t.id),
                                'Изучено: ${t.title}',
                              )
                            : null,
                        child: Text('${magMoney(t.cost)} кр'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
