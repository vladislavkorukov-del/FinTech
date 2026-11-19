import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/material.dart' as m show Text;

import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/finora_orb.dart';

/// The AI window's look: white text on the style's colour falling into
/// black, translucent «glass» panels, accent bubbles for the person.
abstract final class AiLook {
  static const ink = Colors.white;
  static Color soft(double a) => Colors.white.withValues(alpha: a);
  static Color panel([double a = .28]) => Colors.black.withValues(alpha: a);

  /// Finora AI is its own block: always orange, whatever the app theme.
  static const orange = Color(0xFFFF7A1F);

  /// The window's background, drawn by [AiBackdrop].
  static Decoration background([Color accent = orange]) => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0, .32, .62, 1],
      colors: [
        Color(0xFF341307),
        Color(0xFF1B0B06),
        Color(0xFF0B0807),
        Color(0xFF070708),
      ],
    ),
  );

  /// The person's bubble, the mic and the send button: warm amber into
  /// deep orange, lit from the top left.
  static Gradient accent([Color c = orange]) => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF2A766), Color(0xFFE8803A), Color(0xFFC9572A)],
    stops: [0, .55, 1],
  );
}

/// The Finora AI backdrop: a muted ember glow with a lava lamp inside —
/// soft blobs of warm wax that slowly rise, stretch, sink and run into one
/// another. Still when the system asks for less motion.
class AiBackdrop extends StatefulWidget {
  const AiBackdrop({super.key, required this.child});
  final Widget child;

  @override
  State<AiBackdrop> createState() => _AiBackdropState();
}

class _AiBackdropState extends State<AiBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _flow.stop();
    } else if (!_flow.isAnimating) {
      _flow.repeat();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: AiLook.background(),
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _flow,
                builder: (context, _) =>
                    CustomPaint(painter: LavaPainter(_flow.value)),
              ),
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    ),
  );
}

/// Lava-lamp blobs. Each one travels up and down the whole window on its
/// own slow cycle (whole numbers of trips per loop, so the loop is
/// seamless), stretches along its motion and squashes at the turns. The
/// blobs are blurred so that two of them meeting melt into one shape.
class LavaPainter extends CustomPainter {
  LavaPainter(this.t);
  final double t;

  static const blobs = [
    // colour, x, radius (of width), trips per loop, phase, sway
    (Color(0x99D9561F), .28, .34, 1, 0.0, .10),
    (Color(0x80E07A2E), .72, .28, 2, 1.9, .08),
    (Color(0x66C9461A), .5, .22, 1, 3.4, .14),
    (Color(0x59EBA05A), .18, .16, 3, 4.6, .06),
    (Color(0x52B23E17), .82, .2, 2, 5.5, .09),
  ];

  /// Where blob [i] is at loop position [t]: centre (as fractions of the
  /// window) and its stretch (1 is round).
  static (double, double, double) place(int i, double t) {
    final (_, x, _, trips, phase, sway) = blobs[i];
    final a = t * 2 * math.pi * trips + phase;
    // Wax lingers at the bottom and top: an eased vertical cycle.
    final y = .55 - .5 * math.sin(a);
    final speed = math.cos(a).abs();
    final cx = x + sway * math.sin(t * 2 * math.pi + phase * 1.3);
    return (cx, y, 1 + .35 * speed);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    for (var i = 0; i < blobs.length; i++) {
      final (color, _, r, _, _, _) = blobs[i];
      final (cx, cy, stretch) = place(i, t);
      final radius = r * w;
      final rect = Rect.fromCenter(
        center: Offset(cx * w, cy * size.height),
        width: radius * 2 / math.sqrt(stretch),
        height: radius * 2 * stretch,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .45)
          ..shader = RadialGradient(
            colors: [
              color,
              color.withValues(alpha: color.a * .55),
            ],
          ).createShader(rect),
      );
    }
    // A faint warm haze along the top edge.
    final top = Offset.zero & Size(w, size.height * .25);
    canvas.drawRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x26FFD9A8), Color(0x00FFD9A8)],
        ).createShader(top),
    );
  }

  @override
  bool shouldRepaint(LavaPainter old) => old.t != t;
}

/// A small translucent pill («× Закрыть чат»).
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
  });
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AiLook.soft(.12),
    shape: StadiumBorder(side: BorderSide(color: AiLook.soft(.16), width: .8)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: AiLook.soft(.85)),
              const SizedBox(width: 6),
            ],
            Text(label, style: TextStyle(color: AiLook.soft(.9), fontSize: 13)),
          ],
        ),
      ),
    ),
  );
}

/// A round translucent icon button.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: Material(
      color: AiLook.soft(.12),
      shape: CircleBorder(side: BorderSide(color: AiLook.soft(.16), width: .8)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 38,
          child: Icon(icon, size: 18, color: AiLook.soft(.9)),
        ),
      ),
    ),
  );
}

/// A suggestion card on the welcome view.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.text,
    required this.accent,
    required this.onTap,
  });
  final String text;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AiLook.panel(.26),
    shape: const StadiumBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.sparkles, size: 15, color: accent),
            const SizedBox(width: 7),
            Text(
              text,
              maxLines: 1,
              style: const TextStyle(color: AiLook.ink, fontSize: 13.5),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The round mic button with a soft ring (bigger while listening).
class MicButton extends StatelessWidget {
  const MicButton({
    super.key,
    required this.accent,
    required this.onTap,
    this.size = 44,
    this.ring = false,
  });
  final Color accent;
  final VoidCallback onTap;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(ring ? 9 : 0),
    decoration: ring
        ? BoxDecoration(
            shape: BoxShape.circle,
            color: AiLook.soft(.05),
            border: Border.all(color: AiLook.soft(.12)),
          )
        : null,
    child: Material(
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AiLook.accent(accent),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: .45), blurRadius: 18),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              CupertinoIcons.mic_fill,
              color: Colors.white,
              size: size * .45,
            ),
          ),
        ),
      ),
    ),
  );
}

/// One chat message: the person's on the right in an accent bubble,
/// Finora's on the left with her small orb.
class ChatMessage extends StatelessWidget {
  const ChatMessage({
    super.key,
    required this.text,
    required this.mine,
    required this.accent,
    this.typing = false,
    this.onTyped,
  });
  final String text;
  final bool mine;
  final Color accent;

  /// Finora's newest answer is typed out letter by letter.
  final bool typing;

  /// Called once the typing has finished (or was skipped).
  final VoidCallback? onTyped;

  @override
  Widget build(BuildContext context) {
    if (mine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 60, bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: AiLook.accent(accent),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.3,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: FinoraCharacter(
              size: 24,
              moods: [FinoraMood.happy],
              rings: false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TypewriterText(
              text,
              typing: typing,
              onDone: onTyped,
              style: const TextStyle(
                color: AiLook.ink,
                fontSize: 15,
                height: 1.38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text that appears as if being typed: the letters show up one after
/// another, a little faster for long answers. The whole text is laid out
/// from the start (the rest is transparent), so the bubble never jumps
/// and screen readers get the full answer at once. A tap shows it all.
/// Shown whole when [typing] is off or the system asks for less motion.
class TypewriterText extends StatefulWidget {
  const TypewriterText(
    this.text, {
    super.key,
    required this.style,
    this.typing = true,
    this.onDone,
  });
  final String text;
  final TextStyle style;
  final bool typing;
  final VoidCallback? onDone;

  /// How long typing [length] characters takes: ~22 ms a letter at first,
  /// never longer than 2.4 s.
  static Duration durationFor(int length) =>
      Duration(milliseconds: math.min(2400, 120 + length * 22));

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(
        vsync: this,
        duration: TypewriterText.durationFor(widget.text.length),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone?.call();
      });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.typing || still) {
      if (_c.value < 1) _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (!widget.typing && _c.value < 1) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: _c.value < 1 ? () => _c.value = 1 : null,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final text = widget.text;
        final shown = (Curves.easeOut.transform(_c.value) * text.length)
            .round()
            .clamp(0, text.length);
        return m.Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text.substring(0, shown)),
              if (shown < text.length)
                TextSpan(
                  text: text.substring(shown),
                  style: const TextStyle(color: Colors.transparent),
                ),
            ],
          ),
          semanticsLabel: text,
          style: widget.style,
        );
      },
    ),
  );
}
