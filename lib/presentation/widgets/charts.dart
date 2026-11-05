import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'common.dart';

class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.values,
    required this.colors,
    this.onSelect,
    required this.center,
  });
  final List<int> values;
  final List<Color> colors;
  final ValueChanged<int>? onSelect;
  final Widget center;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Кольцевая диаграмма по категориям. Выберите категорию в списке под диаграммой.',
    child: AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTapUp: (d) {
          final size = context.size;
          if (size == null || values.isEmpty) {
            return;
          }
          final p = d.localPosition - Offset(size.width / 2, size.height / 2);
          var angle = math.atan2(p.dy, p.dx) + math.pi / 2;
          if (angle < 0) {
            angle += 2 * math.pi;
          }
          final sum = values.fold<int>(0, (a, b) => a + b);
          var cursor = 0.0;
          for (var i = 0; i < values.length; i++) {
            cursor += values[i] / sum * 2 * math.pi;
            if (angle <= cursor) {
              onSelect?.call(i);
              return;
            }
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Donut(
                  values,
                  colors,
                  Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: .2),
                ),
              ),
            ),
            FractionallySizedBox(
              widthFactor: .58,
              heightFactor: .58,
              child: FittedBox(fit: BoxFit.scaleDown, child: center),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Donut extends CustomPainter {
  _Donut(this.values, this.colors, this.empty);
  final List<int> values;
  final List<Color> colors;
  final Color empty;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.shortestSide - 26,
      height: size.shortestSide - 26,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = empty);
      return;
    }
    var angle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(
        rect,
        angle + .025,
        math.max(.005, sweep - .05),
        false,
        paint..color = colors[i % colors.length],
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Donut old) => true;
}

class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.values,
    required this.color,
    this.area = true,
    this.bars = false,
  });
  final List<double> values;
  final Color color;
  final bool area, bars;
  @override
  Widget build(BuildContext context) => Semantics(
    label: bars ? 'Столбчатая диаграмма' : 'График динамики',
    child: SizedBox(
      height: 130,
      width: double.infinity,
      child: CustomPaint(painter: _Trend(values, color, area, bars)),
    ),
  );
}

class _Trend extends CustomPainter {
  _Trend(this.values, this.color, this.area, this.bars);
  final List<double> values;
  final Color color;
  final bool area, bars;
  @override
  void paint(Canvas c, Size s) {
    if (values.isEmpty) {
      return;
    }
    final maxValue = math.max(1.0, values.reduce(math.max));
    final minValue = math.min(0.0, values.reduce(math.min));
    final range = maxValue - minValue;
    for (var i = 0; i < 4; i++) {
      final y = s.height * i / 3;
      c.drawLine(
        Offset(0, y),
        Offset(s.width, y),
        Paint()..color = color.withValues(alpha: .08),
      );
    }
    final points = List.generate(
      values.length,
      (i) => Offset(
        values.length == 1 ? s.width / 2 : i / (values.length - 1) * s.width,
        s.height - (values[i] - minValue) / range * (s.height - 12) - 6,
      ),
    );
    if (bars) {
      final w = s.width / values.length;
      for (var i = 0; i < values.length; i++) {
        final y = points[i].dy;
        final zero = s.height - (0 - minValue) / range * (s.height - 12) - 6;
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              i * w + 2,
              math.min(y, zero),
              i * w + w - 3,
              math.max(y, zero),
            ),
            const Radius.circular(5),
          ),
          Paint()..color = color.withValues(alpha: .85),
        );
      }
      return;
    }
    final p = Path()..moveTo(points.first.dx, points.first.dy);
    for (final o in points.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    if (area) {
      final fill = Path.from(p)
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close();
      c.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .25), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & s),
      );
    }
    c.drawPath(
      p,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _Trend old) => true;
}

/// Daily, lazily rendered columns preserve exact amounts instead of grouping
/// several days into one unlabeled bucket on long periods.
class DailyExpenseChart extends StatelessWidget {
  const DailyExpenseChart({
    super.key,
    required this.start,
    required this.days,
    required this.amountsMinor,
    required this.currency,
    this.onDayTap,
  });
  final DateTime start;
  final int days;
  final Map<int, int> amountsMinor;
  final String currency;
  final ValueChanged<DateTime>? onDayTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxMinor = amountsMinor.values.fold<int>(1, math.max);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 190 + math.max(0, scale - 1) * 26,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: days,
        itemBuilder: (context, index) {
          final date = DateTime(start.year, start.month, start.day + index);
          final amount = amountsMinor[index] ?? 0;
          final barHeight = amount == 0
              ? 2.0
              : math.max(4.0, amount / maxMinor * 108);
          final label = money(amount, currency);
          return SizedBox(
            width: 86,
            child: Semantics(
              button: onDayTap != null,
              label: '${displayDate(date)}, расход $label',
              child: Tooltip(
                message: '${displayDate(date)} · $label',
                child: InkWell(
                  key: ValueKey('daily-bar-$index'),
                  onTap: onDayTap == null ? null : () => onDayTap!(date),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 2, 7, 6),
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Positioned(
                                bottom: 0,
                                left: 18,
                                right: 18,
                                child: Container(
                                  height: barHeight,
                                  decoration: BoxDecoration(
                                    color: amount == 0
                                        ? scheme.outlineVariant
                                        : scheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: barHeight + 8,
                                left: 0,
                                right: 0,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          DateFormat('dd MMM', 'ru').format(date),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
