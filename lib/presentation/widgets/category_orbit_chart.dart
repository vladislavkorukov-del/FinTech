import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/services.dart';

import '../../domain/models.dart';
import 'common.dart';
import '../l10n_widgets.dart';

class CategorySlice {
  const CategorySlice({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.amount,
  });
  final String id, name;
  final IconData icon;
  final Color color;
  final int amount;
}

/// Categories as one ring (Finora 1.26): every sector on a single circle,
/// icons sit on the sectors, the period is written in the middle. Tapping a
/// sector lifts it, shows a branch to a bubble with its icon and share, and
/// writes its name and sum in the middle; tap again (or the middle) to let go.
class CategoryOrbitChart extends StatefulWidget {
  const CategoryOrbitChart({
    super.key,
    required this.slices,
    required this.currency,
    this.kind = EntryKind.expense,
    this.onDetails,
    this.title,
    this.diameter = 200,
  });
  final List<CategorySlice> slices;
  final String currency;
  final EntryKind kind;
  final ValueChanged<String>? onDetails;

  /// The period in the middle («Ноябрь»); by default «Расходы»/«Доходы».
  final String? title;
  final double diameter;
  @override
  State<CategoryOrbitChart> createState() => _CategoryOrbitChartState();
}

class _CategoryOrbitChartState extends State<CategoryOrbitChart>
    with TickerProviderStateMixin {
  String? _selected;
  late final _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Release: the ring grows round on first show.
  late final _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _grow.value = 1;
    } else if (_grow.value == 0 && !_grow.isAnimating) {
      _grow.forward();
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _select(String? id) {
    HapticFeedback.selectionClick();
    if (id == null || id == _selected) {
      _lift.reverse().whenComplete(() {
        if (mounted && _lift.value == 0) setState(() => _selected = null);
      });
      return;
    }
    setState(() => _selected = id);
    _lift.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.slices.where((e) => e.amount > 0).toList();
    if (items.isEmpty) {
      return EmptyState(
        widget.kind == EntryKind.income
            ? 'Нет доходов за период'
            : 'Нет расходов за период',
        widget.kind == EntryKind.income
            ? 'Добавьте доход или выберите другой период.'
            : 'Добавьте расход или выберите другой период.',
      );
    }
    final total = items.fold<int>(0, (a, b) => a + b.amount);
    final units = _percentageUnits(items, total);
    final mids = <String, double>{};
    final sweeps = _displaySweeps(items, total, widget.diameter);
    var angle = -math.pi / 2;
    for (final item in items) {
      final sweep = sweeps[item.id]!;
      mids[item.id] = angle + sweep / 2;
      angle += sweep;
    }
    final selected = items.where((e) => e.id == _selected).firstOrNull;
    String percent(String id) {
      final u = units[id]!;
      return u == 0
          ? '<0,1%'
          : u % 10 == 0
          ? '${u ~/ 10}%'
          : '${u ~/ 10},${u % 10}%';
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final d = math.min(widget.diameter, width - 16);
            final stroke = d * _strokeShare;
            final ringR = d / 2 - stroke / 2 - 6;
            final height = d + 24;
            final center = Offset(width / 2, height / 2);
            return SizedBox(
              height: height,
              child: AnimatedBuilder(
                animation: Listenable.merge([_lift, _grow]),
                builder: (context, _) {
                  final t = Curves.easeOutCubic.transform(_lift.value);
                  final grow = Curves.easeOutCubic.transform(_grow.value);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            final p = details.localPosition - center;
                            if (p.distance < ringR - stroke / 2) {
                              // The middle lets go.
                              if (_selected != null) _select(null);
                              return;
                            }
                            if (p.distance > ringR + stroke / 2 + 14) return;
                            var a = math.atan2(p.dy, p.dx) + math.pi / 2;
                            if (a < 0) a += math.pi * 2;
                            var cursor = 0.0;
                            for (final item in items) {
                              cursor += sweeps[item.id]!;
                              if (a <= cursor) {
                                _select(item.id);
                                break;
                              }
                            }
                          },
                          child: CustomPaint(
                            painter: _RingPainter(
                              items: items,
                              sweeps: sweeps,
                              center: center,
                              radius: ringR,
                              stroke: stroke,
                              selected: _selected,
                              t: t,
                              grow: grow,
                              dark:
                                  Theme.of(context).brightness ==
                                  Brightness.dark,
                            ),
                          ),
                        ),
                      ),
                      // Every capsule and dot carries its symbol.
                      for (final item in items)
                        _icon(
                          item,
                          center,
                          ringR,
                          mids[item.id]!,
                          stroke,
                          t,
                          fade: ((grow - .5) * 2).clamp(0.0, 1.0),
                        ),
                      // The middle: the period and total, or the chosen one.
                      Positioned(
                        left: center.dx - (ringR - stroke / 2) * .7,
                        top: center.dy - (ringR - stroke / 2) * .55,
                        width: (ringR - stroke / 2) * 1.4,
                        height: (ringR - stroke / 2) * 1.1,
                        child: IgnorePointer(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: selected == null
                                  ? _middle(
                                      key: const ValueKey('middle-total'),
                                      top:
                                          widget.title ??
                                          (widget.kind == EntryKind.income
                                              ? 'Доходы'
                                              : 'Расходы'),
                                      main: money(total, widget.currency),
                                      bottom:
                                          '${items.length} ${_categoriesWord(items.length)}',
                                    )
                                  : _middle(
                                      key: ValueKey('middle-${selected.id}'),
                                      top: selected.name,
                                      main: money(
                                        selected.amount,
                                        widget.currency,
                                      ),
                                      bottom: percent(selected.id),
                                      color: selected.color,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      if (selected != null)
                        _bubble(
                          selected,
                          percent(selected.id),
                          center,
                          ringR + stroke / 2,
                          mids[selected.id]!,
                          width,
                          height,
                          t,
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: selected != null && widget.onDetails != null
              ? TextButton.icon(
                  key: const ValueKey('category-details'),
                  onPressed: () => widget.onDetails!(selected.id),
                  icon: const Icon(Icons.receipt_long_outlined, size: 17),
                  label: Text(
                    'Операции: ${selected.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _middle({
    required Key key,
    required String top,
    required String main,
    required String bottom,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          top,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          main,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          bottom,
          maxLines: 1,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _icon(
    CategorySlice item,
    Offset center,
    double r,
    double mid,
    double stroke,
    double t, {
    double fade = 1,
  }) {
    final lifted = _selected == item.id ? t * 6 : 0.0;
    final dimmed = _selected != null && _selected != item.id;
    final p = center + Offset(math.cos(mid), math.sin(mid)) * (r + lifted);
    final size = math.min(stroke * .5, 18.0);
    const ink = Color(0xCC1C1C1E);
    return Positioned(
      left: p.dx - stroke / 2,
      top: p.dy - stroke / 2,
      width: stroke,
      height: stroke,
      child: Semantics(
        button: true,
        label: 'Категория ${item.name}',
        selected: _selected == item.id,
        child: GestureDetector(
          key: ValueKey('category-icon-${item.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _select(item.id),
          child: Opacity(
            opacity: (dimmed ? 1 - .5 * t : 1) * fade,
            child: Icon(item.icon, size: size, color: ink),
          ),
        ),
      ),
    );
  }

  /// The branch and bubble of the chosen sector.
  Widget _bubble(
    CategorySlice item,
    String percent,
    Offset center,
    double outer,
    double mid,
    double width,
    double height,
    double t,
  ) {
    const w = 78.0, h = 32.0;
    final dir = Offset(math.cos(mid), math.sin(mid));
    final anchor = center + dir * (outer + 6);
    final elbow = anchor + dir * 14;
    final right = dir.dx >= 0;
    final end = elbow + Offset(right ? 12 : -12, 0);
    final left = (right ? end.dx : end.dx - w).clamp(-8.0, width - w + 8);
    final top = (end.dy - h / 2).clamp(-6.0, height - h + 6);
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: t,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BranchPainter(
                    points: [anchor, elbow, end],
                    color: item.color,
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: w,
                height: h,
                child: Container(
                  key: const ValueKey('category-bubble'),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(h / 2),
                    border: Border.all(color: item.color, width: 1.4),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 16, color: item.color),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            percent,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _categoriesWord(int n) {
  final last = n % 10, lastTwo = n % 100;
  if (last == 1 && lastTwo != 11) return 'категория';
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return 'категории';
  }
  return 'категорий';
}

Map<String, int> _percentageUnits(List<CategorySlice> items, int total) {
  final divisor = BigInt.from(total);
  final result = <String, int>{};
  final remainder = <String, BigInt>{};
  var used = 0;
  for (final item in items) {
    final value = BigInt.from(item.amount) * BigInt.from(1000);
    result[item.id] = (value ~/ divisor).toInt();
    remainder[item.id] = value % divisor;
    used += result[item.id]!;
  }
  final order = [...items]
    ..sort((a, b) {
      final compare = remainder[b.id]!.compareTo(remainder[a.id]!);
      return compare == 0 ? a.id.compareTo(b.id) : compare;
    });
  for (var i = 0; i < 1000 - used; i++) {
    result[order[i % order.length].id] =
        result[order[i % order.length].id]! + 1;
  }
  return result;
}

/// The ring's thickness as a share of its diameter.
const _strokeShare = .15;

/// Soft pastel of a category colour, as in a health-score ring.
Color _pastel(Color c, bool dark) {
  final h = HSLColor.fromColor(c);
  return h
      .withSaturation((h.saturation * .75).clamp(.35, .7))
      .withLightness(dark ? .7 : .78)
      .toColor();
}

/// Sweeps for the ring: a share of the circle per category, but never less
/// than a round dot, so small categories stay visible and tappable.
Map<String, double> _displaySweeps(
  List<CategorySlice> items,
  int total,
  double diameter,
) {
  final stroke = diameter * _strokeShare;
  final radius = diameter / 2 - stroke / 2 - 6;
  final full = math.pi * 2;
  final minimum = math.min((stroke + 6) / radius, full / items.length);
  final small = <String>{};
  // Fix the smallest ones at the minimum until the rest fit.
  for (var pass = 0; pass < items.length; pass++) {
    final restAmount = items
        .where((e) => !small.contains(e.id))
        .fold<int>(0, (a, e) => a + e.amount);
    final restAngle = full - minimum * small.length;
    final add = items.where(
      (e) =>
          !small.contains(e.id) &&
          e.amount / math.max(restAmount, 1) * restAngle < minimum,
    );
    if (add.isEmpty) break;
    small.addAll(add.map((e) => e.id));
  }
  final restAmount = items
      .where((e) => !small.contains(e.id))
      .fold<int>(0, (a, e) => a + e.amount);
  final restAngle = full - minimum * small.length;
  return {
    for (final e in items)
      e.id: small.contains(e.id)
          ? minimum
          : e.amount / math.max(restAmount, 1) * restAngle,
  };
}

/// Capsules with round ends and clear gaps; a category too small for a
/// capsule is a round dot (Finora Release, after a health-score ring).
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.items,
    required this.sweeps,
    required this.center,
    required this.radius,
    required this.stroke,
    required this.selected,
    required this.t,
    required this.dark,
    this.grow = 1,
  });
  final double grow;
  final List<CategorySlice> items;
  final Map<String, double> sweeps;
  final Offset center;
  final double radius, stroke, t;
  final String? selected;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    var start = -math.pi / 2;
    if (grow <= 0) return;
    // The round ends reach half a stroke past the arc; leave 6 px between.
    final gap = items.length == 1 ? 0.0 : (stroke + 6) / radius;
    for (final item in items) {
      final sweep = sweeps[item.id]! * grow;
      final chosen = selected == item.id;
      final lift = chosen ? 6 * t : 0.0;
      final mid = start + sweep / 2;
      final c = center + Offset(math.cos(mid), math.sin(mid)) * lift;
      final paint = Paint()
        ..color = _pastel(
          item.color,
          dark,
        ).withValues(alpha: selected == null || chosen ? 1 : 1 - .55 * t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + (chosen ? 4 * t : 0)
        ..strokeCap = StrokeCap.round;
      final arc = items.length == 1 ? math.pi * 2 - .001 : sweep - gap;
      if (arc > .01) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: radius),
          mid - arc / 2,
          arc,
          false,
          paint,
        );
      } else {
        canvas.drawCircle(
          c + Offset(math.cos(mid), math.sin(mid)) * radius,
          paint.strokeWidth / 2,
          Paint()..color = paint.color,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}

class _BranchPainter extends CustomPainter {
  const _BranchPainter({required this.points, required this.color});
  final List<Offset> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.first, 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BranchPainter old) =>
      old.points != points || old.color != color;
}
