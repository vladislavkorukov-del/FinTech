import 'package:flutter/material.dart' hide Text;

import '../../widgets/motion.dart';

const worldPlum = Color(0xFF4B294C);
const worldPearl = Color(0xFFF7F1F5);
const worldJade = Color(0xFF285F51);
const worldChampagne = Color(0xFFD4B592);

/// Stable source IDs stay alongside the existing persisted cosmetic IDs.
class WorldBackgroundArt {
  const WorldBackgroundArt(
    this.id,
    this.cosmeticId,
    this.title,
    this.file,
    this.width,
    this.height,
  );
  final String id, cosmeticId, title, file;
  final int width, height;
  String get asset => 'assets/finora/world/home/backgrounds/$file';
}

const worldBackgroundArt = [
  WorldBackgroundArt(
    'finora_home_mint_atrium',
    'mint',
    'Мятный атриум',
    '01_mint_atrium.png',
    941,
    1672,
  ),
  WorldBackgroundArt(
    'finora_home_tea_room',
    'pearl',
    'Чайная комната',
    '02_tea_room.png',
    941,
    1672,
  ),
  WorldBackgroundArt(
    'finora_home_observatory',
    'night',
    'Звёздная обсерватория',
    '03_observatory.png',
    941,
    1672,
  ),
  WorldBackgroundArt(
    'finora_home_garden',
    'garden',
    'Дом-сад',
    '04_garden.png',
    941,
    1672,
  ),
  WorldBackgroundArt(
    'finora_home_underwater',
    'underwater',
    'Подводный дом',
    '05_underwater.png',
    941,
    1672,
  ),
  WorldBackgroundArt(
    'finora_home_aurora',
    'aurora',
    'Северное сияние',
    '06_aurora.png',
    1052,
    1495,
  ),
];

abstract final class WorldArt {
  static String icon(String id) => 'assets/finora/world/ui/png/$id.png';
  static WorldBackgroundArt background(String id) =>
      worldBackgroundArt
          .where((art) => art.cosmeticId == id || art.id == id)
          .firstOrNull ??
      worldBackgroundArt.first;
}

/// The uploaded style applies only below this subtree, never to finance pages.
class WorldTheme extends StatelessWidget {
  const WorldTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: worldJade,
      brightness: Brightness.light,
      primary: worldJade,
      secondary: const Color(0xFFC7ACE6),
      surface: worldPearl,
      onSurface: worldPlum,
      onSurfaceVariant: const Color(0xFF735A75),
      outline: worldChampagne,
    );
    return Theme(
      data: base.copyWith(
        brightness: Brightness.light,
        colorScheme: scheme,
        scaffoldBackgroundColor: worldPearl,
        canvasColor: worldPearl,
        textTheme: base.textTheme.apply(
          bodyColor: worldPlum,
          displayColor: worldPlum,
        ),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: worldPearl,
          foregroundColor: worldPlum,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: base.textTheme.titleLarge?.copyWith(
            color: worldPlum,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: worldPlum),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB3E2CF),
            foregroundColor: worldJade,
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: worldChampagne),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: worldPlum,
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: worldChampagne),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: worldJade,
            minimumSize: const Size(48, 44),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xFFEEE6EF),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xFF79BD9C)
                : const Color(0xFFD9CFDA),
          ),
        ),
      ),
      child: child,
    );
  }
}

class WorldArtImage extends StatelessWidget {
  const WorldArtImage(this.id, {super.key, this.size = 48});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    WorldArt.icon(id),
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context) * 1.5)
        .ceil()
        .clamp(64, 512),
    excludeFromSemantics: true,
  );
}

/// Back/add/settings/close retain the circular surface baked into the PNG.
class WorldImageButton extends StatelessWidget {
  const WorldImageButton({
    super.key,
    required this.id,
    required this.label,
    required this.onPressed,
    this.size = 48,
  });
  final String id, label;
  final VoidCallback? onPressed;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    child: Tooltip(
      message: label,
      child: PressScale(
        enabled: onPressed != null,
        child: SizedBox(
          width: size < 48 ? 48 : size,
          height: size < 48 ? 48 : size,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: Opacity(
                opacity: onPressed == null ? .45 : 1,
                child: WorldArtImage(id, size: size),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class WorldPearlSurface extends StatelessWidget {
  const WorldPearlSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFBFE), Color(0xFFF0E6F2), Color(0xFFF8F2F5)],
      ),
      border: Border.all(color: worldChampagne.withValues(alpha: .75)),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: worldPlum.withValues(alpha: .09),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
