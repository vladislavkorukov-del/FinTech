import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/finora_orb.dart';

/// The AI window's look: white text on the style's colour falling into
/// black, translucent «glass» panels, accent bubbles for the person.
abstract final class AiLook {
  static const ink = Colors.white;
  static Color soft(double a) => Colors.white.withValues(alpha: a);
  static Color panel([double a = .28]) => Colors.black.withValues(alpha: a);

  /// The window's background: the accent at the top, deepening into black.
  static Decoration background(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    final bright = hsl
        .withSaturation((hsl.saturation * 1.05).clamp(.45, .95))
        .withLightness(.46)
        .toColor();
    final deep = hsl.withLightness(.18).toColor();
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .34, .7, 1],
        colors: [
          bright,
          deep,
          const Color(0xFF0A0A0B),
          const Color(0xFF070708),
        ],
      ),
    );
  }

  /// The person's bubble and the mic: a soft gradient of the accent.
  static Gradient accent(Color c) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color.lerp(c, Colors.white, .12)!, c],
  );
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
    shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(18)),
    child: InkWell(
      onTap: onTap,
      customBorder: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: SizedBox(
        width: 148,
        height: 108,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.sparkles, size: 18, color: accent),
              const Spacer(),
              Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AiLook.ink,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
            ],
          ),
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
  });
  final String text;
  final bool mine;
  final Color accent;

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
            child: Text(
              text,
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
