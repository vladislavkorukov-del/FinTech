import 'dart:async';

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../l10n_widgets.dart';
import 'finora_orb.dart';

/// Finora's short lines («Записала…», «Не поняла…») at the bottom of the
/// screen, with her small orb — shown while the orb itself has no place in
/// the layout. Listens to [Finora.reactions]; a line stays for its hold
/// time, then fades.
class FinoraSays extends StatefulWidget {
  const FinoraSays({super.key});
  @override
  State<FinoraSays> createState() => _FinoraSaysState();
}

class _FinoraSaysState extends State<FinoraSays> {
  FinoraReaction? _shown;
  Timer? _clear;

  @override
  void initState() {
    super.initState();
    Finora.reactions.addListener(_react);
  }

  @override
  void dispose() {
    _clear?.cancel();
    Finora.reactions.removeListener(_react);
    super.dispose();
  }

  void _react() {
    final r = Finora.reactions.value;
    if (!mounted || r == null || r.text == null) return;
    _clear?.cancel();
    setState(() => _shown = r);
    _clear = Timer(r.hold, () {
      if (mounted) setState(() => _shown = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _shown;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, .3),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        child: r == null
            ? const SizedBox.shrink()
            : Container(
                key: const ValueKey('finora-says'),
                constraints: const BoxConstraints(maxWidth: 340),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.fromLTRB(10, 9, 16, 9),
                decoration: ShapeDecoration(
                  color: scheme.surface,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: scheme.primary.withValues(alpha: .35),
                    ),
                  ),
                  shadows: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FinoraCharacter(size: 26, moods: [r.mood], rings: false),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        r.text!,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          color: scheme.onSurface,
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
