import 'dart:math' as math;

import 'package:flutter/material.dart';

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
