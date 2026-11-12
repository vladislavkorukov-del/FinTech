import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/flow/flow.dart';
import 'flow_art.dart';

/// Stable names and original art, independent of matching and saved tile IDs.
abstract final class FlowTileArt {
  static String symbol(FlowTile type) =>
      const ['C', 'W', 'G', 'S', 'R', 'H'][type.index];
  static String name(FlowTile type) =>
      const ['Монета', 'Кошелёк', 'Цель', 'Щит', 'Чек', 'График'][type.index];
  static Color color(FlowTile type) => const [
    Color(0xFFE9C98A),
    Color(0xFF9DD1B5),
    Color(0xFFC6AEDB),
    Color(0xFF9BBAD9),
    Color(0xFFDEAFA5),
    Color(0xFF8DC9C6),
  ][type.index];
  static IconData booster(FlowBooster booster) => switch (booster) {
    FlowBooster.rocketRow => Icons.swap_horiz,
    FlowBooster.rocketColumn => Icons.swap_vert,
    FlowBooster.bomb => Icons.stars_outlined,
    FlowBooster.core => Icons.adjust,
    FlowBooster.drone => Icons.flight_outlined,
    FlowBooster.none => Icons.circle,
  };
  static String boosterName(FlowBooster booster) => switch (booster) {
    FlowBooster.rocketRow => 'Ракета по строке',
    FlowBooster.rocketColumn => 'Ракета по столбцу',
    FlowBooster.bomb => 'Fin-взрыв',
    FlowBooster.core => 'Ядро Finora',
    FlowBooster.drone => 'Finora Drone',
    FlowBooster.none => '',
  };
}

class FlowBoard extends StatefulWidget {
  const FlowBoard({
    super.key,
    required this.session,
    required this.onSelect,
    required this.onExchange,
    this.selected,
    this.enabled = true,
  });
  final FlowSession session;
  final int? selected;
  final bool enabled;
  final ValueChanged<int> onSelect;
  final void Function(int from, int to) onExchange;

  @override
  State<FlowBoard> createState() => _FlowBoardState();
}

class _FlowBoardState extends State<FlowBoard> {
  int? _dragCell;
  Offset _drag = Offset.zero;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: widget.enabled
              ? (details) {
                  _dragCell =
                      (details.localPosition.dy / width * 8).floor().clamp(
                            0,
                            7,
                          ) *
                          8 +
                      (details.localPosition.dx / width * 8).floor().clamp(
                        0,
                        7,
                      );
                  _drag = Offset.zero;
                }
              : null,
          onPanUpdate: widget.enabled
              ? (details) => _drag += details.delta
              : null,
          onPanCancel: () => _dragCell = null,
          onPanEnd: widget.enabled
              ? (_) {
                  final from = _dragCell;
                  _dragCell = null;
                  if (from == null || _drag.distance < 12) return;
                  final horizontal = _drag.dx.abs() > _drag.dy.abs();
                  final to =
                      from +
                      (horizontal
                          ? (_drag.dx > 0 ? 1 : -1)
                          : (_drag.dy > 0 ? 8 : -8));
                  if (FlowEngine.neighbors(from, to)) {
                    widget.onExchange(from, to);
                  }
                }
              : null,
          child: GridView.builder(
            key: const ValueKey('flow-board'),
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
            ),
            itemCount: 64,
            itemBuilder: (context, i) => _FlowCellView(
              key: ValueKey('flow-cell-$i'),
              cell: widget.session.board[i],
              index: i,
              selected: widget.selected == i,
              enabled: widget.enabled,
              onTap: () => widget.onSelect(i),
            ),
          ),
        );
      },
    ),
  );
}

class _FlowCellView extends StatelessWidget {
  const _FlowCellView({
    super.key,
    required this.cell,
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final FlowCell cell;
  final int index;
  final bool selected, enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final type = cell.tile;
    final label = cell.stack > 0
        ? 'Стопка чеков, ${cell.stack} слоёв'
        : cell.crate > 0
        ? 'Ящик, прочность ${cell.crate}'
        : cell.booster != FlowBooster.none
        ? FlowTileArt.boosterName(cell.booster)
        : type == null
        ? 'Пустая клетка'
        : FlowTileArt.name(type);

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label${cell.ice > 0 ? ", лёд ${cell.ice}" : ""}${cell.chain > 0 ? ", цепи ${cell.chain}" : ""}, строка ${index ~/ 8 + 1}, столбец ${index % 8 + 1}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEE8F3).withValues(alpha: .64),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFE1D8DF)),
                    ),
                  ),
                ),
                if (cell.stack > 0)
                  for (var layer = 0; layer < math.min(cell.stack, 3); layer++)
                    Positioned.fill(
                      top: layer * 3,
                      child: const FlowSprite('match3_receipt', trim: false),
                    )
                else if (cell.crate > 0)
                  Positioned.fill(
                    child: FlowSprite(
                      cell.crate > 1
                          ? 'obstacle_crate_intact'
                          : 'obstacle_crate_damaged',
                      trim: false,
                    ),
                  )
                else if (cell.booster == FlowBooster.drone)
                  const Positioned.fill(
                    child: Icon(
                      Icons.flight_outlined,
                      color: Color(0xFF4B1038),
                    ),
                  )
                else if (cell.booster != FlowBooster.none || type != null)
                  Positioned.fill(
                    child: FlowSprite(switch (cell.booster) {
                      FlowBooster.rocketRow => 'match3_rocket_horizontal',
                      FlowBooster.rocketColumn => 'match3_rocket_vertical',
                      FlowBooster.bomb => 'booster_bomb',
                      FlowBooster.core => 'match3_rainbow_sphere',
                      _ => 'match3_${type!.name}',
                    }, trim: false),
                  ),
                if (cell.ice > 0)
                  Positioned.fill(
                    child: FlowSprite(
                      cell.ice > 1
                          ? 'obstacle_ice_intact'
                          : 'obstacle_ice_cracked',
                      trim: false,
                    ),
                  ),
                if (cell.chain > 0)
                  Positioned.fill(
                    child: FlowSprite(
                      cell.chain > 1
                          ? 'obstacle_chain_intact'
                          : 'obstacle_chain_damaged',
                      trim: false,
                    ),
                  ),
                if (cell.stack > 0)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Text(
                      '${cell.stack}',
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: Color(0xFF4B1038),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                if (selected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF285F51)
                              : const Color(0xFF599AC3),
                          width: selected ? 3 : 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
