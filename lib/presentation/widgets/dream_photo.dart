import 'dart:io';

import 'package:flutter/material.dart';

import 'motion.dart';

/// 1.55: whether a dream's photo can be shown (set and still on disk).
bool hasDreamPhoto(String? path) => path != null && File(path).existsSync();

/// A card whose background is the dream's photo. A dark scrim keeps the text
/// readable, and the content is drawn in a light-on-dark theme.
class DreamPhotoCard extends StatelessWidget {
  const DreamPhotoCard({
    super.key,
    required this.path,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 6, 12),
  });

  final String path;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: base.colorScheme.primary,
      brightness: Brightness.dark,
    ).copyWith(onSurface: Colors.white, onSurfaceVariant: Colors.white70);
    return PressScale(
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  cacheWidth: 1200,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: base.colorScheme.surface),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .25),
                        Colors.black.withValues(alpha: .62),
                      ],
                    ),
                  ),
                ),
              ),
              Theme(
                data: base.copyWith(
                  colorScheme: scheme,
                  iconTheme: const IconThemeData(color: Colors.white),
                  textTheme: base.textTheme.apply(
                    bodyColor: Colors.white,
                    displayColor: Colors.white,
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: Padding(padding: padding, child: child),
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

/// The dream's photo as a 2:1 banner at the top of a card.
class DreamPhotoBanner extends StatelessWidget {
  const DreamPhotoBanner({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: BorderRadius.circular(14),
    child: AspectRatio(
      aspectRatio: 2,
      child: Image.file(
        File(path),
        key: const ValueKey('dream-photo-banner'),
        fit: BoxFit.cover,
        cacheWidth: 1200,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );
}
