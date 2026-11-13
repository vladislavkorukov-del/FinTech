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

/// The playfield pack (1.59): four layers drawn on one 1254 × 1254 canvas —
/// the plum backplate, a lavender cell repeated 8 × 8, the pieces and
/// obstacles, then the pearl frame. Rectangles come from the pack's
/// PLAYFIELD_LAYOUT.json and scale together with one factor.
abstract final class FlowPlayfield {
  static const folder = 'assets/finora/match3/playfield';
  static const background = '$folder/gameplay_background.png';
  static const backplate = '$folder/board_backplate.png';
  static const cell = '$folder/board_cell.png';
  static const frame = '$folder/board_frame_pearl.png';

  static const canvas = 1254.0;
  static const size = 8;
  static const backplateDest = Rect.fromLTRB(151, 158, 1098, 1102);
  static const backplateVisible = Rect.fromLTRB(56, 56, 1198, 1198);
  static const grid = Rect.fromLTRB(190, 195, 1060, 1065);
  static const cellVisible = Rect.fromLTRB(103, 114, 1149, 1154);
  static const frameVisible = Rect.fromLTRB(94, 102, 1156, 1159);
  static const gapFraction = .085;

  /// The square of the canvas shown in the board's box: the frame's visible
  /// part fills it, so the transparent margins of the PNGs take no space.
  static Rect get view {
    final side = math.max(frameVisible.width, frameVisible.height);
    return Rect.fromCenter(
      center: frameVisible.center,
      width: side,
      height: side,
    );
  }

  /// Distance between neighbouring cell centers on the canvas.
  static double get pitch => math.min(grid.width / size, grid.height / size);

  /// The cell [index] on the canvas, centered in the grid with the gap.
  static Rect cellRect(int index) {
    final step = pitch;
    final gap = step * gapFraction;
    final left = grid.left + (grid.width - step * size) / 2;
    final top = grid.top + (grid.height - step * size) / 2;
    return Rect.fromLTWH(
      left + (index % size) * step + gap / 2,
      top + (index ~/ size) * step + gap / 2,
      step - gap,
      step - gap,
    );
  }

  /// Where to draw a whole canvas image so its [visible] part fills [dest].
  static Rect place(Rect visible, Rect dest) {
    final sx = dest.width / visible.width, sy = dest.height / visible.height;
    return Rect.fromLTWH(
      dest.left - visible.left * sx,
      dest.top - visible.top * sy,
      canvas * sx,
      canvas * sy,
    );
  }

  /// The cell under a canvas point, clamped to the board's edge cells.
  static int cellAt(Offset point) {
    final step = pitch;
    final left = grid.left + (grid.width - step * size) / 2;
    final top = grid.top + (grid.height - step * size) / 2;
    final column = ((point.dx - left) / step).floor().clamp(0, size - 1);
    final row = ((point.dy - top) / step).floor().clamp(0, size - 1);
    return row * size + column;
  }

  /// A canvas rectangle in a board box [side] wide.
  static Rect toBox(Rect r, double side) {
    final v = view, k = side / v.width;
    return Rect.fromLTRB(
      (r.left - v.left) * k,
      (r.top - v.top) * k,
      (r.right - v.left) * k,
      (r.bottom - v.top) * k,
    );
  }

  /// A point in a board box [side] wide, on the canvas.
  static Offset toCanvas(Offset p, double side) =>
      p * (view.width / side) + view.topLeft;
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
        final side = box.maxWidth;
        final k = side / FlowPlayfield.view.width;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        // One decode per layer size: every cell shares the same cache width.
        final cellCanvas = FlowPlayfield.place(
          FlowPlayfield.cellVisible,
          FlowPlayfield.cellRect(0),
        );
        final cellCache = math.max(1, (cellCanvas.width * k * dpr).ceil());
        final boardCache = math.max(1, (FlowPlayfield.canvas * k * dpr).ceil());
        Widget layer(String asset, Rect rect, int cache) => Positioned.fromRect(
          rect: FlowPlayfield.toBox(rect, side),
          child: IgnorePointer(
            child: Image.asset(
              asset,
              fit: BoxFit.fill,
              cacheWidth: cache,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
        );
        return GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: widget.enabled
              ? (details) {
                  _dragCell = FlowPlayfield.cellAt(
                    FlowPlayfield.toCanvas(details.localPosition, side),
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
          child: Stack(
            key: const ValueKey('flow-board'),
            clipBehavior: Clip.none,
            children: [
              layer(
                FlowPlayfield.backplate,
                FlowPlayfield.place(
                  FlowPlayfield.backplateVisible,
                  FlowPlayfield.backplateDest,
                ),
                boardCache,
              ),
              for (var i = 0; i < 64; i++)
                layer(
                  FlowPlayfield.cell,
                  FlowPlayfield.place(
                    FlowPlayfield.cellVisible,
                    FlowPlayfield.cellRect(i),
                  ),
                  cellCache,
                ),
              for (var i = 0; i < 64; i++)
                Positioned.fromRect(
                  rect: FlowPlayfield.toBox(FlowPlayfield.cellRect(i), side),
                  child: _FlowCellView(
                    key: ValueKey('flow-cell-$i'),
                    cell: widget.session.board[i],
                    index: i,
                    selected: widget.selected == i,
                    enabled: widget.enabled,
                    onTap: () => widget.onSelect(i),
                  ),
                ),
              // The frame on top never takes a touch from the pieces.
              layer(
                FlowPlayfield.frame,
                const Rect.fromLTWH(
                  0,
                  0,
                  FlowPlayfield.canvas,
                  FlowPlayfield.canvas,
                ),
                boardCache,
              ),
            ],
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
                        fontWeight: FontWeight.w700,
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
