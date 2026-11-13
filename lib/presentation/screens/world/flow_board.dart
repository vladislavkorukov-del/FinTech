import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/flow/flow.dart';
import 'flow_art.dart';
import 'world_art.dart' show worldFontFamily;

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

/// One move to show on the board (1.61): the board before it, the swapped
/// pair (none for a booster) and what the engine reported.
class FlowBoardMotion {
  const FlowBoardMotion({
    required this.id,
    required this.before,
    required this.accepted,
    this.from,
    this.to,
    this.events = const [],
  });
  final int id;
  final List<FlowCell> before;
  final bool accepted;
  final int? from, to;
  final List<FlowEvent> events;

  /// The engine counts rounds from where its resolution started; the
  /// board counts from this move's first round.
  int get _base =>
      events.isEmpty ? 0 : events.map((e) => e.chain).reduce(math.min);

  /// The round of [e] within this move, from 0.
  int round(FlowEvent e) => e.chain - _base;

  /// Cells cleared in the first round, then the deepest cascade.
  Set<int> get firstRound => {
    for (final e in events)
      if (round(e) == 0 && e.index >= 0 && _clears(e.kind)) e.index,
  };
  int get cascades => events.fold(0, (m, e) => math.max(m, round(e)));
  static bool _clears(String kind) =>
      kind == 'collect' || kind == 'activate' || kind.endsWith('Damage');
}

class FlowBoard extends StatefulWidget {
  const FlowBoard({
    super.key,
    required this.session,
    required this.onSelect,
    required this.onExchange,
    this.selected,
    this.enabled = true,
    this.motion,
    this.animate = false,
  });
  final FlowSession session;
  final int? selected;
  final bool enabled;
  final ValueChanged<int> onSelect;
  final void Function(int from, int to) onExchange;

  /// The latest move to play; a new [FlowBoardMotion.id] starts it.
  final FlowBoardMotion? motion;

  /// False with reduced motion (system or world setting): changes are shown
  /// at once, nothing repeats.
  final bool animate;

  @override
  State<FlowBoard> createState() => _FlowBoardState();
}

/// Timeline of one move, in milliseconds.
abstract final class _T {
  static const swap = 170.0, pop = 190.0, fall = 380.0, cascade = 150.0;
}

class _FlowBoardState extends State<FlowBoard> with TickerProviderStateMixin {
  int? _dragCell;
  Offset _drag = Offset.zero;

  // The move being shown.
  late final AnimationController _move = AnimationController(vsync: this)
    ..addListener(_tick);
  int _comboPending = 0;

  void _tick() {
    // The cascade banner appears once the first round has popped.
    final motion = _playing;
    if (_comboPending > 0 && motion != null) {
      final swap = motion.from != null ? _T.swap : 0.0;
      if (_move.value * _moveMs >= swap + _T.pop) {
        _comboLevel = _comboPending;
        _comboPending = 0;
        _combo.forward(from: 0);
      }
    }
    setState(() {});
  }

  FlowBoardMotion? _playing;
  int _played = -1;
  double _moveMs = 0;

  // A breathing selection and a gentle hint after a pause.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..addListener(() => setState(() {}));
  (int, int)? _hinted;
  Timer? _idle;

  // The board fills with falling pieces when the level opens.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(() => setState(() {}));

  // «Отлично!» over a cascade.
  late final AnimationController _combo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..addListener(() => setState(() {}));
  int _comboLevel = 0;

  @override
  void initState() {
    super.initState();
    _played = widget.motion?.id ?? -1;
    if (widget.animate) {
      _enter.forward();
      _scheduleHint();
    } else {
      _enter.value = 1;
    }
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant FlowBoard old) {
    super.didUpdateWidget(old);
    final motion = widget.motion;
    if (motion != null && motion.id != _played) {
      _played = motion.id;
      if (widget.animate) _play(motion);
    }
    if (!widget.animate) {
      _move.value = _move.upperBound;
      _enter.value = 1;
      _hint.value = 0;
      _combo.value = 0;
    }
    _syncPulse();
    if (old.session != widget.session || old.selected != widget.selected) {
      _scheduleHint();
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    _move.dispose();
    _pulse.dispose();
    _hint.dispose();
    _enter.dispose();
    _combo.dispose();
    super.dispose();
  }

  void _syncPulse() {
    final want = widget.animate && widget.selected != null;
    if (want && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!want && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  void _scheduleHint() {
    _idle?.cancel();
    _hinted = null;
    _hint.value = 0;
    if (!widget.animate) return;
    _idle = Timer(const Duration(seconds: 6), () {
      if (!mounted || !widget.enabled || widget.session.finished) return;
      final moves = FlowEngine.legalMoves(widget.session);
      if (moves.isEmpty) return;
      setState(() => _hinted = moves.first);
      _hint.forward(from: 0).whenComplete(_scheduleHint);
    });
  }

  void _play(FlowBoardMotion motion) {
    _playing = motion;
    final swap = motion.from != null ? _T.swap : 0.0;
    _moveMs = motion.accepted
        ? swap + _T.pop + _T.fall + motion.cascades * _T.cascade
        : swap * 2 + 120;
    _move
      ..duration = Duration(milliseconds: _moveMs.round())
      ..forward(from: 0);
    _comboPending = motion.accepted ? motion.cascades : 0;
  }

  bool get _busy => widget.animate && _move.isAnimating;

  /// What a cell looks like right now: which board, and how it moves.
  ({FlowCell cell, Offset shift, double scale, double opacity}) _look(
    int i,
    double pitch,
  ) {
    var cell = widget.session.board[i];
    var shift = Offset.zero;
    var scale = 1.0, opacity = 1.0;
    final motion = _playing;
    if (widget.animate && motion != null && _move.isAnimating) {
      final ms = _move.value * _moveMs;
      final swap = motion.from != null ? _T.swap : 0.0;
      Offset delta(int a, int b) =>
          Offset(((b % 8) - (a % 8)) * pitch, ((b ~/ 8) - (a ~/ 8)) * pitch);
      if (!motion.accepted) {
        // There and back, with a little shake in the middle.
        cell = motion.before[i];
        final out = ms < swap
            ? Curves.easeOutCubic.transform(ms / swap)
            : ms < swap + 120
            ? 1 - .12 * math.sin((ms - swap) / 120 * math.pi * 3)
            : 1 -
                  Curves.easeInOutCubic.transform(
                    ((ms - swap - 120) / swap).clamp(0.0, 1.0),
                  );
        if (i == motion.from) shift = delta(i, motion.to!) * out;
        if (i == motion.to) shift = delta(i, motion.from!) * out;
      } else if (ms < swap) {
        cell = motion.before[i];
        final p = Curves.easeInOutCubic.transform(ms / swap);
        if (i == motion.from) shift = delta(i, motion.to!) * p;
        if (i == motion.to) shift = delta(i, motion.from!) * p;
      } else if (ms < swap + _T.pop) {
        // The swapped board; the first round of matches pops.
        final swapped = List<FlowCell>.of(motion.before);
        if (motion.from != null) {
          swapped[motion.from!] = motion.before[motion.to!];
          swapped[motion.to!] = motion.before[motion.from!];
        }
        cell = swapped[i];
        if (motion.firstRound.contains(i)) {
          final p = (ms - swap) / _T.pop;
          scale = 1 + .18 * math.sin(p * math.pi) - p * .9;
          opacity = 1 - Curves.easeIn.transform(p);
        }
      } else {
        // The new board settles: pieces in a column with cleared cells fall
        // from above, the lowest first, with a soft landing.
        final cleared = <int, int>{};
        for (final e in motion.events) {
          if (e.index >= 0 && FlowBoardMotion._clears(e.kind)) {
            cleared[e.index % 8] = math.max(
              cleared[e.index % 8] ?? -1,
              e.index ~/ 8,
            );
          }
        }
        final column = i % 8, row = i ~/ 8;
        final lowest = cleared[column];
        if (lowest != null && row <= lowest) {
          final count = motion.events
              .where(
                (e) =>
                    e.index >= 0 &&
                    e.index % 8 == column &&
                    FlowBoardMotion._clears(e.kind),
              )
              .map((e) => e.index)
              .toSet()
              .length;
          final delay = (lowest - row) * 18.0;
          final p = ((ms - swap - _T.pop - delay) / (_T.fall - 60)).clamp(
            0.0,
            1.0,
          );
          final drop = math.max(1, count) * pitch;
          shift = Offset(0, -drop * (1 - const _Land().transform(p)));
          opacity = p == 0 ? 0 : 1;
        }
      }
    } else if (widget.animate && _enter.value < 1) {
      final row = i ~/ 8, column = i % 8;
      final delay = (7 - row) * .055 + column * .012;
      final p = ((_enter.value - delay) / .5).clamp(0.0, 1.0);
      shift = Offset(0, -(row + 3) * pitch * (1 - const _Land().transform(p)));
      opacity = p == 0 ? 0 : 1;
    }
    // The hint: the two pieces lean toward each other twice.
    final hint = _hinted;
    if (hint != null && _hint.isAnimating && (i == hint.$1 || i == hint.$2)) {
      final other = i == hint.$1 ? hint.$2 : hint.$1;
      final dir = Offset(
        ((other % 8) - (i % 8)).toDouble(),
        ((other ~/ 8) - (i ~/ 8)).toDouble(),
      );
      final w = math.sin(_hint.value * math.pi * 4).abs();
      shift += dir * pitch * .12 * w;
      scale *= 1 + .05 * w;
    }
    if (widget.selected == i && widget.animate) {
      scale *= 1 + .07 * Curves.easeInOut.transform(_pulse.value);
    }
    return (cell: cell, shift: shift, scale: scale, opacity: opacity);
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth;
        final k = side / FlowPlayfield.view.width;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final pitch = FlowPlayfield.pitch * k;
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
        final enabled = widget.enabled && !_busy;
        final bursts = _bursts(side);
        return GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: enabled
              ? (details) {
                  _scheduleHint();
                  _dragCell = FlowPlayfield.cellAt(
                    FlowPlayfield.toCanvas(details.localPosition, side),
                  );
                  _drag = Offset.zero;
                }
              : null,
          onPanUpdate: enabled ? (details) => _drag += details.delta : null,
          onPanCancel: () => _dragCell = null,
          onPanEnd: enabled
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
              // Pieces stay inside the grid while they fall in from above.
              Positioned.fromRect(
                rect: FlowPlayfield.toBox(FlowPlayfield.grid, side),
                child: ClipRect(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < 64; i++)
                        _piece(i, side, pitch, enabled),
                    ],
                  ),
                ),
              ),
              if (bursts.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _BurstPainter(bursts)),
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
              if (_combo.isAnimating && _comboLevel > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _ComboBanner(
                      level: _comboLevel,
                      t: _combo.value,
                      side: side,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _piece(int i, double side, double pitch, bool enabled) {
    final grid = FlowPlayfield.toBox(FlowPlayfield.grid, side);
    final rect = FlowPlayfield.toBox(
      FlowPlayfield.cellRect(i),
      side,
    ).shift(-grid.topLeft);
    final look = _look(i, pitch);
    return Positioned.fromRect(
      rect: rect,
      child: Opacity(
        opacity: look.opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: look.shift,
          child: Transform.scale(
            scale: look.scale.clamp(0.0, 2.0),
            child: _FlowCellView(
              key: ValueKey('flow-cell-$i'),
              cell: look.cell,
              index: i,
              selected: widget.selected == i,
              enabled: enabled,
              onTap: () {
                _scheduleHint();
                widget.onSelect(i);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Sparks where pieces burst: the first round as they pop, later
  /// cascades one after another while the board settles.
  List<_Burst> _bursts(double side) {
    final motion = _playing;
    if (!widget.animate || motion == null || !_move.isAnimating) return [];
    if (!motion.accepted) return [];
    final ms = _move.value * _moveMs;
    final swap = motion.from != null ? _T.swap : 0.0;
    final out = <_Burst>[];
    final seen = <(int, int)>{};
    for (final e in motion.events) {
      if (e.index < 0 || !FlowBoardMotion._clears(e.kind)) continue;
      final round = motion.round(e);
      if (!seen.add((e.index, round))) continue;
      final start = swap + (round == 0 ? 0 : _T.pop + round * _T.cascade);
      final p = (ms - start) / 420;
      if (p <= 0 || p >= 1) continue;
      final center = FlowPlayfield.toBox(
        FlowPlayfield.cellRect(e.index),
        side,
      ).center;
      out.add(
        _Burst(
          center: center,
          radius: FlowPlayfield.pitch * side / FlowPlayfield.view.width,
          color: _sparkColor(e.tile),
          t: p,
          seed: e.index * 7 + round,
        ),
      );
    }
    return out;
  }

  static Color _sparkColor(FlowTile? tile) => switch (tile) {
    FlowTile.coin => const Color(0xFFFFC93C),
    FlowTile.wallet => const Color(0xFFA77BF6),
    FlowTile.goal => const Color(0xFFFF5D6C),
    FlowTile.shield => const Color(0xFF3FD6EA),
    FlowTile.receipt => const Color(0xFFFFB38F),
    FlowTile.chart => const Color(0xFF4C7DF5),
    null => const Color(0xFFFFF1C2),
  };
}

/// A quick landing with a small settle, for falling pieces.
class _Land extends Curve {
  const _Land();
  @override
  double transformInternal(double t) {
    if (t < .78) {
      final p = t / .78;
      return p * p * (3 - 2 * p) * 1.04;
    }
    final p = (t - .78) / .22;
    return 1.04 - .04 * Curves.easeOut.transform(p);
  }
}

class _Burst {
  const _Burst({
    required this.center,
    required this.radius,
    required this.color,
    required this.t,
    required this.seed,
  });
  final Offset center;
  final double radius, t;
  final Color color;
  final int seed;
}

/// A ring and a handful of sparks flying out and fading.
class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.bursts);
  final List<_Burst> bursts;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bursts) {
      final ease = Curves.easeOutCubic.transform(b.t);
      final fade = 1 - b.t;
      canvas.drawCircle(
        b.center,
        b.radius * (.25 + .55 * ease),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = b.radius * .08 * fade
          ..color = Colors.white.withValues(alpha: .8 * fade),
      );
      canvas.drawCircle(
        b.center,
        b.radius * .35 * (1 - ease * .6),
        Paint()
          ..color = b.color.withValues(alpha: .45 * fade)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.radius * .18),
      );
      final rng = math.Random(b.seed);
      for (var k = 0; k < 8; k++) {
        final angle = k * math.pi / 4 + rng.nextDouble() * .5;
        final reach = b.radius * (.35 + .55 * ease) * (.8 + rng.nextDouble());
        final at = b.center + Offset(math.cos(angle), math.sin(angle)) * reach;
        canvas.drawCircle(
          at,
          b.radius * .06 * (1 - b.t * .7),
          Paint()
            ..color = (k.isEven ? b.color : Colors.white).withValues(
              alpha: fade,
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => true;
}

/// «Отлично!», «Великолепно!» or «Невероятно!» over a cascade.
class _ComboBanner extends StatelessWidget {
  const _ComboBanner({
    required this.level,
    required this.t,
    required this.side,
  });
  final int level;
  final double t, side;

  @override
  Widget build(BuildContext context) {
    final text = switch (level) {
      1 => 'Отлично!',
      2 => 'Великолепно!',
      _ => 'Невероятно!',
    };
    final appear = Curves.easeOutBack.transform((t / .25).clamp(0.0, 1.0));
    final leave = Curves.easeIn.transform(((t - .7) / .3).clamp(0.0, 1.0));
    return Center(
      child: Opacity(
        opacity: (1 - leave).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -side * .06 * leave),
          child: Transform.scale(
            scale: .6 + .4 * appear,
            child: Text(
              text,
              style: TextStyle(
                fontFamily: worldFontFamily,
                fontSize: side * .085,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: const [
                  Shadow(
                    color: Color(0xFF4B1038),
                    blurRadius: 0,
                    offset: Offset(0, 3),
                  ),
                  Shadow(color: Color(0xAA7A2A6A), blurRadius: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
