import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Paints the theme's [FinanceBackdrop] behind the whole app. An idle screen
/// draws no frames, and scrolling never repaints the backdrop (1.11.1).
class FinanceBackground extends StatelessWidget {
  const FinanceBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [const FinanceBackdropLayer(), child],
  );
}

/// 1.42: the painted backdrop alone. Pages opened on top of another page
/// carry their own copy, so a page is never see-through while it slides in.
///
/// Apple polish: one flat grouped-background color; no gradient, no glows.
class FinanceBackdropLayer extends StatelessWidget {
  const FinanceBackdropLayer({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: DecoratedBox(
        key: const ValueKey('finance-backdrop'),
        decoration: BoxDecoration(color: FinanceBackdrop.of(context).top),
      ),
    ),
  );
}
