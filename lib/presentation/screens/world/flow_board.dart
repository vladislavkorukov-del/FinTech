import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/flow/flow.dart';

/// Temporary renderer: changing this mapping later does not change game rules.
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
        : cell.booster != FlowBooster.none
        ? FlowTileArt.boosterName(cell.booster)
        : type == null
        ? 'Пустая клетка'
        : FlowTileArt.name(type);
    final color = type == null
        ? const Color(0xFFE0D5E7)
        : FlowTileArt.color(type);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label${cell.ice > 0 ? ", лёд ${cell.ice}" : ""}, строка ${index ~/ 8 + 1}, столбец ${index % 8 + 1}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TileShape(type, color, cell.stack),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: cell.booster != FlowBooster.none
                        ? Icon(
                            FlowTileArt.booster(cell.booster),
                            size: math.min(25, box.maxWidth * .65),
                            color: const Color(0xFF38243F),
                          )
                        : Text(
                            cell.stack > 0
                                ? 'R'
                                : type == null
                                ? ''
                                : FlowTileArt.symbol(type),
                            style: TextStyle(
                              fontSize: math.min(18, box.maxWidth * .48),
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF38243F),
                            ),
                          ),
                  ),
                ),
                if (cell.ice > 0 || cell.stack > 0)
                  Positioned(
                    right: 1,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      color: cell.ice > 0
                          ? const Color(0xFFD2EFFB)
                          : const Color(0xFFF0D8AE),
                      child: Text(
                        '${cell.ice > 0 ? 'I' : 'R'}${cell.ice > 0 ? cell.ice : cell.stack}',
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF38243F),
                        ),
                      ),
                    ),
                  ),
                if (selected || cell.ice > 0)
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

class _TileShape extends CustomPainter {
  const _TileShape(this.type, this.color, this.layers);
  final FlowTile? type;
  final Color color;
  final int layers;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final p = Paint()..color = layers > 0 ? const Color(0xFFD7BD9B) : color;
    if (type == FlowTile.coin) {
      canvas.drawOval(rect, p);
    } else if (type == FlowTile.goal) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width / 2, 1)
          ..lineTo(size.width - 1, size.height / 2)
          ..lineTo(size.width / 2, size.height - 1)
          ..lineTo(1, size.height / 2)
          ..close(),
        p,
      );
    } else if (type == FlowTile.shield) {
      canvas.drawPath(
        Path()
          ..moveTo(3, 2)
          ..lineTo(size.width - 3, 2)
          ..lineTo(size.width - 3, size.height * .55)
          ..quadraticBezierTo(
            size.width * .85,
            size.height * .8,
            size.width / 2,
            size.height - 1,
          )
          ..quadraticBezierTo(
            size.width * .15,
            size.height * .8,
            3,
            size.height * .55,
          )
          ..close(),
        p,
      );
    } else if (type == FlowTile.chart) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width * .25, 2)
          ..lineTo(size.width * .75, 2)
          ..lineTo(size.width - 1, size.height / 2)
          ..lineTo(size.width * .75, size.height - 2)
          ..lineTo(size.width * .25, size.height - 2)
          ..lineTo(1, size.height / 2)
          ..close(),
        p,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(type == FlowTile.wallet ? 9 : 3),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_TileShape old) =>
      old.type != type || old.color != color || old.layers != layers;
}
