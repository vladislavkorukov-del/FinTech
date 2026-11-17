import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// Finger navigation: a swipe to the right that starts in the left fifth of
/// the screen goes back one page, like a phone's back gesture; on the main
/// tabs the same swipe opens the side panel (the shell's own drawer swipe).
///
/// This one works only while a page lies above the main shell. Sheets and
/// dialogs are left alone, and so are full-screen forms, so an unfinished
/// entry is never thrown away by a swipe.
class MenuEdgeSwipe extends StatefulWidget {
  const MenuEdgeSwipe({super.key, required this.child});
  final Widget child;

  /// The app's navigator (given to MaterialApp).
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Opens the side panel; set by the main shell while it is shown.
  static VoidCallback? openMenu;

  /// The share of the screen width, from the left, where the swipe starts.
  static const edge = .2;

  @override
  State<MenuEdgeSwipe> createState() => _MenuEdgeSwipeState();
}

class _MenuEdgeSwipeState extends State<MenuEdgeSwipe> {
  bool _done = false;
  double _dx = 0;

  /// The top route, read without popping anything.
  Route<dynamic>? _top(NavigatorState nav) {
    Route<dynamic>? top;
    nav.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }

  bool _allowed(Offset position) {
    final nav = MenuEdgeSwipe.navigatorKey.currentState;
    if (nav == null || MenuEdgeSwipe.openMenu == null) return false;
    final width = MediaQuery.sizeOf(context).width;
    if (position.dx > width * MenuEdgeSwipe.edge) return false;
    final top = _top(nav);
    // Full-screen forms (a new operation) keep their input.
    return top is PageRoute && !top.isFirst && !top.fullscreenDialog;
  }

  /// One page back.
  void _open() {
    if (_done) return;
    _done = true;
    final nav = MenuEdgeSwipe.navigatorKey.currentState;
    if (nav == null || !nav.canPop()) return;
    HapticFeedback.selectionClick();
    nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _EdgeDrag: GestureRecognizerFactoryWithHandlers<_EdgeDrag>(
          () => _EdgeDrag(_allowed),
          (drag) => drag
            ..onStart = (_) {
              _done = false;
              _dx = 0;
            }
            ..onUpdate = (d) {
              _dx += d.delta.dx;
              if (_dx > 56) _open();
            }
            ..onEnd = (d) {
              if (_dx > 16 && d.velocity.pixelsPerSecond.dx > 350) _open();
            },
        ),
      },
      child: widget.child,
    );
  }
}

/// A horizontal drag that only takes part when it starts at the left edge
/// while a page is open.
class _EdgeDrag extends HorizontalDragGestureRecognizer {
  _EdgeDrag(this.allowed);
  final bool Function(Offset position) allowed;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      allowed(event.position) && super.isPointerAllowed(event);
}
