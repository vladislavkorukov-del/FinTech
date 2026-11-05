import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models.dart';
import 'common.dart';

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

/// Labels are paged around the complete ring. Paging never drops a sector or
/// changes the total; it only makes dense category sets readable on a phone.
class CategoryOrbitChart extends StatefulWidget {
  const CategoryOrbitChart({
    super.key,
    required this.slices,
    required this.currency,
    this.kind = EntryKind.expense,
    this.onDetails,
  });
  final List<CategorySlice> slices;
  final String currency;
  final EntryKind kind;
  final ValueChanged<String>? onDetails;
  @override
  State<CategoryOrbitChart> createState() => _CategoryOrbitChartState();
}

class _CategoryOrbitChartState extends State<CategoryOrbitChart> {
  final _amountLabels = <String>{};
  String? _selected;
  int _page = 0;
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
    final angles = <String, double>{};
    var angle = -math.pi / 2;
    for (final item in items) {
      final sweep = item.amount / total * math.pi * 2;
      angles[item.id] = angle + sweep / 2;
      angle += sweep;
    }
    final left = items.where((e) => math.cos(angles[e.id]!) < 0).toList()
      ..sort(
        (a, b) => math.sin(angles[a.id]!).compareTo(math.sin(angles[b.id]!)),
      );
    final right = items.where((e) => math.cos(angles[e.id]!) >= 0).toList()
      ..sort(
        (a, b) => math.sin(angles[a.id]!).compareTo(math.sin(angles[b.id]!)),
      );
    const perSide = 3;
    final pages = math.max(
      1,
      (math.max(left.length, right.length) / perSide).ceil(),
    );
    final page = _page.clamp(0, pages - 1);
    final selected = items.where((e) => e.id == _selected).firstOrNull;
    void select(String id) {
      setState(() {
        _selected = id;
        final side = left.any((e) => e.id == id) ? left : right;
        _page = side.indexWhere((e) => e.id == id) ~/ perSide;
      });
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final labelWidth = (width * .255).clamp(62.0, 94.0);
            final diameter = math.max(82.0, width - labelWidth * 2 - 12);
            final visibleLeft = left
                .skip(page * perSide)
                .take(perSide)
                .toList();
            final visibleRight = right
                .skip(page * perSide)
                .take(perSide)
                .toList();
            final rows = math.max(visibleLeft.length, visibleRight.length);
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            var rowHeight = math.max(88.0, 88.0 * textScale);
            // Reserve the full formatted amount even while showing a percent.
            // Large balances and accessibility fonts must never clip a label.
            for (final item in [...visibleLeft, ...visibleRight]) {
              final amountText = TextPainter(
                text: TextSpan(
                  text: money(item.amount, widget.currency),
                  style: DefaultTextStyle.of(context).style.merge(
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: labelWidth - 8);
              rowHeight = math.max(
                rowHeight,
                60 + 18 * textScale + amountText.height,
              );
              amountText.dispose();
            }
            final height = math.max(diameter + 30, rows * rowHeight + 12);
            final center = Offset(width / 2, height / 2);
            final radius = diameter / 2 - 11;
            final positions = <String, Offset>{};
            for (final pair in [(visibleLeft, true), (visibleRight, false)]) {
              for (var i = 0; i < pair.$1.length; i++) {
                positions[pair.$1[i].id] = Offset(
                  pair.$2 ? labelWidth - 4 : width - labelWidth + 4,
                  (height - pair.$1.length * rowHeight) / 2 +
                      i * rowHeight +
                      rowHeight / 2,
                );
              }
            }
            return SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTapUp: (details) {
                        final p = details.localPosition - center;
                        if ((p.distance - radius).abs() > 22) {
                          return;
                        }
                        var a = math.atan2(p.dy, p.dx) + math.pi / 2;
                        if (a < 0) {
                          a += math.pi * 2;
                        }
                        var cursor = 0.0;
                        for (final item in items) {
                          cursor += item.amount / total * math.pi * 2;
                          if (a <= cursor) {
                            select(item.id);
                            break;
                          }
                        }
                      },
                      child: CustomPaint(
                        painter: _OrbitPainter(
                          items: items,
                          total: total,
                          center: center,
                          radius: radius,
                          angles: angles,
                          labels: positions,
                          selected: selected?.id,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: center.dx - diameter * .29,
                    top: center.dy - diameter * .25,
                    width: diameter * .58,
                    height: diameter * .5,
                    child: IgnorePointer(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.kind == EntryKind.income
                                    ? 'Доходы'
                                    : 'Расходы',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                money(total, widget.currency),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final pair in [
                    (visibleLeft, true),
                    (visibleRight, false),
                  ])
                    for (var i = 0; i < pair.$1.length; i++)
                      Positioned(
                        left: pair.$2 ? 0 : width - labelWidth,
                        top:
                            (height - pair.$1.length * rowHeight) / 2 +
                            i * rowHeight,
                        width: labelWidth,
                        height: rowHeight,
                        child: _label(
                          pair.$1[i],
                          units[pair.$1[i].id]!,
                          select,
                        ),
                      ),
                ],
              ),
            );
          },
        ),
        if (pages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Предыдущие категории',
                onPressed: page > 0
                    ? () => setState(() => _page = page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Flexible(
                child: Text(
                  '${page + 1} / $pages · ${items.length} категорий',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              IconButton(
                tooltip: 'Следующие категории',
                onPressed: page + 1 < pages
                    ? () => setState(() => _page = page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        if (selected != null && widget.onDetails != null)
          TextButton.icon(
            key: const ValueKey('category-details'),
            onPressed: () => widget.onDetails!(selected.id),
            icon: const Icon(Icons.receipt_long_outlined, size: 17),
            label: Text(
              'Операции: ${selected.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _label(CategorySlice item, int units, ValueChanged<String> select) {
    final amount = _amountLabels.contains(item.id);
    final percent = units == 0
        ? '<0,1%'
        : units % 10 == 0
        ? '${units ~/ 10}%'
        : '${units ~/ 10},${units % 10}%';
    final selected = _selected == item.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            button: true,
            label: 'Категория ${item.name}',
            selected: selected,
            child: InkWell(
              key: ValueKey('category-icon-${item.id}'),
              onTap: () => select(item.id),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : item.color.withValues(alpha: .4),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Icon(item.icon, size: 18, color: item.color),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
          InkWell(
            key: ValueKey('category-value-${item.id}'),
            onTap: () => setState(() {
              if (!_amountLabels.add(item.id)) {
                _amountLabels.remove(item.id);
              }
            }),
            borderRadius: BorderRadius.circular(6),
            child: Tooltip(
              message: amount ? 'Показать процент' : 'Показать точную сумму',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                child: Text(
                  amount ? money(item.amount, widget.currency) : percent,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.items,
    required this.total,
    required this.center,
    required this.radius,
    required this.angles,
    required this.labels,
    required this.selected,
  });
  final List<CategorySlice> items;
  final int total;
  final Offset center;
  final double radius;
  final Map<String, double> angles;
  final Map<String, Offset> labels;
  final String? selected;
  @override
  void paint(Canvas canvas, Size size) {
    for (final item in items) {
      final label = labels[item.id];
      if (label == null) {
        continue;
      }
      final a = angles[item.id]!;
      final anchor = center + Offset(math.cos(a), math.sin(a)) * (radius + 12);
      final elbow = Offset(
        label.dx < center.dx ? center.dx - radius - 7 : center.dx + radius + 7,
        label.dy,
      );
      canvas.drawPath(
        Path()
          ..moveTo(anchor.dx, anchor.dy)
          ..lineTo(elbow.dx, elbow.dy)
          ..lineTo(label.dx, label.dy),
        Paint()
          ..color = item.color.withValues(alpha: .28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7,
      );
    }
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (final item in items) {
      final sweep = item.amount / total * math.pi * 2;
      final gap = math.min(.025, sweep * .13);
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..color = item.color.withValues(
            alpha: selected == null || selected == item.id ? 1 : .42,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = (selected == item.id ? 22.0 : 17.0)
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => true;
}
