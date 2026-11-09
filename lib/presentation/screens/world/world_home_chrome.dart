import 'package:flutter/material.dart' hide Text;

import '../../l10n_widgets.dart';
import 'world_art.dart';

/// Controls float above the house; the scene never scrolls behind a page header.
class WorldHomeHeader extends StatelessWidget {
  const WorldHomeHeader({
    super.key,
    required this.title,
    required this.points,
    required this.progress,
    required this.sparks,
    required this.onBack,
    required this.onRank,
    required this.onCurrency,
    required this.onSettings,
  });
  final String title;
  final int points, sparks;
  final double? progress;
  final VoidCallback onBack, onRank, onCurrency, onSettings;
  static bool stacks(double width, double scale) =>
      width < 360 && scale > 1.3 || width < 500 && scale > 1.8;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final stacked = stacks(box.maxWidth, scale);
      final rank = WorldPearlSurface(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
        onTap: onRank,
        child: Row(
          children: [
            const WorldArtImage('rank_badge', size: 34),
            const SizedBox(width: 3),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$points опыта',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: worldJade),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      key: const ValueKey('world-level-progress'),
                      value: progress,
                      color: const Color(0xFF7CC9AC),
                      backgroundColor: const Color(0xFFE2D6E4),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
      final currency = Semantics(
        label: '$sparks искр. Как получать искры',
        button: true,
        child: Tooltip(
          message: 'Как получать искры',
          child: WorldPearlSurface(
            key: const ValueKey('world-currency-ways'),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
            onTap: onCurrency,
            child: Row(
              children: [
                const WorldArtImage('currency_gem', size: 26),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    '$sparks',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final back = WorldImageButton(
        key: const ValueKey('world-back'),
        id: 'back',
        label: 'Назад',
        onPressed: onBack,
      );
      final settings = WorldImageButton(
        key: const ValueKey('world-settings'),
        id: 'settings',
        label: 'Настройки мира',
        onPressed: onSettings,
      );
      if (stacked) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                back,
                const SizedBox(width: 4),
                Expanded(child: rank),
                settings,
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: 116, child: currency),
            ),
          ],
        );
      }
      return Row(
        children: [
          back,
          const SizedBox(width: 2),
          Expanded(child: rank),
          const SizedBox(width: 6),
          SizedBox(width: scale > 1.3 ? 94 : 82, child: currency),
          const SizedBox(width: 2),
          settings,
        ],
      );
    },
  );
}

/// A curved pearl platform, drawn locally so it stays sharp on every screen.
class WorldHomeDock extends StatelessWidget {
  const WorldHomeDock({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _DockPainter(),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: children,
      ),
    ),
  );
}

class _DockPainter extends CustomPainter {
  const _DockPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * .07, h * .19)
      ..quadraticBezierTo(w * .5, h * .32, w * .93, h * .19)
      ..cubicTo(w * 1.02, h * .23, w * 1.02, h * .78, w * .93, h * .9)
      ..quadraticBezierTo(w * .5, h * 1.04, w * .07, h * .9)
      ..cubicTo(-w * .02, h * .78, -w * .02, h * .23, w * .07, h * .19)
      ..close();
    canvas.drawShadow(path, const Color(0xFF365A50), 10, true);
    final rect = Offset.zero & size;
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFCF6FD),
            Color(0xFFF0E7F0),
            Color(0xFFB9E7D5),
            Color(0xFFF9EFD9),
          ],
          stops: [0, .64, .88, 1],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFEEE1BB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final highlight = Path()
      ..moveTo(w * .04, h * .75)
      ..quadraticBezierTo(w * .5, h * 1.02, w * .96, h * .75);
    canvas.drawPath(
      highlight,
      Paint()
        ..color = const Color(0xDFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DockPainter oldDelegate) => false;
}
