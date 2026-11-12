import 'package:flutter/material.dart';

import 'widgets/finance_background.dart';

/// 1.42: how pages open and close. The app's pages are see-through (one
/// painted backdrop behind everything), so the stock zoom/fade transitions
/// showed two screens on top of each other. Here a page opened on top of
/// another gets its own backdrop and slides in from the side, while the
/// page below moves back a little and dims; editors (full-screen dialogs)
/// rise from the bottom.
class FinoraPageTransitionsBuilder extends PageTransitionsBuilder {
  const FinoraPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) {
      return child;
    }
    final curve = CurvedAnimation(
      parent: animation,
      // The iOS sheet/push curve: fast start, long soft landing.
      curve: const Cubic(.32, .72, 0, 1),
      reverseCurve: Curves.easeInCubic,
    );
    final page = RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [const FinanceBackdropLayer(), child],
      ),
    );
    final below = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: below,
      builder: (context, inner) {
        final t = below.value;
        if (t == 0) return inner!;
        // The page underneath steps back and dims.
        return Transform.translate(
          offset: Offset(
            (rtl ? 1 : -1) * MediaQuery.sizeOf(context).width * .22 * t,
            0,
          ),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: .28 * t),
              BlendMode.srcATop,
            ),
            child: inner,
          ),
        );
      },
      child: route.fullscreenDialog
          ? SlideTransition(
              position: Tween(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curve),
              child: page,
            )
          : SlideTransition(
              position: Tween(
                begin: Offset(rtl ? -1 : 1, 0),
                end: Offset.zero,
              ).animate(curve),
              child: page,
            ),
    );
  }
}

/// [theme] with Finora's page transitions on every platform.
ThemeData withFinoraTransitions(ThemeData theme) => theme.copyWith(
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FinoraPageTransitionsBuilder(),
      TargetPlatform.iOS: FinoraPageTransitionsBuilder(),
      TargetPlatform.linux: FinoraPageTransitionsBuilder(),
      TargetPlatform.macOS: FinoraPageTransitionsBuilder(),
      TargetPlatform.windows: FinoraPageTransitionsBuilder(),
      TargetPlatform.fuchsia: FinoraPageTransitionsBuilder(),
    },
  ),
);
