import 'package:flutter/material.dart';

/// Shared dimensions keep dense finance views calm and consistent.
abstract final class Space {
  static const double xs = 6, sm = 12, md = 20, lg = 28, xl = 36;
}

/// Finora's palette deliberately stays within lime, sage and neutral graphite.
/// User-defined category colors are separate from the product color system.
abstract final class AppTheme {
  static const lightBase = Color(0xFFEEF1EC);
  static const lightCard = Color(0xFFFCFEFA);
  static const darkBase = Color(0xFF070807);
  static const darkCard = Color(0xFF1F2321);
  static const lime = Color(0xFFC5E768);
  static const electric = Color(0xFFD9FF3F);
  static const sage = Color(0xFFA3C156);
  static const muted = Color(0xFF78806D);
  static const graphite = Color(0xFF434840);
  static const border = Color(0xFFD5D7CF);
  static const subdued = Color(0xFFACAEA9);

  static const presetNames = <String, String>{
    'lime': 'Lime · фирменный',
    'electric': 'Electric · яркий',
    'sage': 'Sage · спокойный',
    'graphite': 'Graphite · строгий',
    'paper': 'Paper · мягкий',
    'midnight': 'Midnight · глубокий',
  };

  static Color accent(String value) => switch (value) {
    'electric' => electric,
    'sage' => sage,
    'graphite' => const Color(0xFFBFC9B4),
    'paper' => const Color(0xFFD9E5C8),
    'midnight' => const Color(0xFFB6D86A),
    // Legacy accents remain readable, without reviving the old multicolor UI.
    _ => lime,
  };

  static ThemeData build(Brightness brightness, String selected) {
    final dark = brightness == Brightness.dark;
    final seed = accent(selected);
    final ink = dark ? lightCard : darkBase;
    final secondaryInk = dark ? subdued : graphite;
    final card = dark ? darkCard : lightCard;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: seed,
          onPrimary: darkBase,
          primaryContainer: dark
              ? const Color(0xFF2D3820)
              : const Color(0xFFE1EDCE),
          onPrimaryContainer: dark ? lime : darkBase,
          secondary: sage,
          onSecondary: darkBase,
          secondaryContainer: dark
              ? const Color(0xFF30392A)
              : const Color(0xFFE4E9DD),
          onSecondaryContainer: ink,
          tertiary: muted,
          onTertiary: dark ? darkBase : lightCard,
          surface: card,
          onSurface: ink,
          onSurfaceVariant: secondaryInk,
          surfaceContainerLowest: dark ? darkBase : lightBase,
          surfaceContainerLow: card,
          surfaceContainer: card,
          surfaceContainerHigh: dark
              ? const Color(0xFF292E29)
              : const Color(0xFFE5E9E1),
          surfaceContainerHighest: dark
              ? const Color(0xFF343A32)
              : const Color(0xFFDEE4D8),
          outline: dark ? muted : const Color(0xFF71776A),
          outlineVariant: dark ? graphite : border,
          surfaceTint: Colors.transparent,
          inverseSurface: dark ? lightCard : darkCard,
          onInverseSurface: dark ? darkBase : lightCard,
          inversePrimary: dark ? graphite : lime,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? darkBase : lightBase,
      fontFamily: 'sans-serif',
    );
    return base.copyWith(
      textTheme: base.textTheme.merge(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.8,
          ),
          headlineLarge: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
          headlineSmall: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
          ),
          titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 16, height: 1.45),
          bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          labelSmall: TextStyle(
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 28,
        thickness: .7,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      iconTheme: IconThemeData(color: ink),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: dark ? graphite : lime,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF292E29) : lightBase,
        labelStyle: TextStyle(color: secondaryInk),
        hintStyle: TextStyle(color: secondaryInk),
        prefixIconColor: secondaryInk,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: dark ? seed : graphite, width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: electric,
          foregroundColor: darkBase,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: dark ? seed : graphite),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? lightCard : graphite,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: card,
        selectedColor: seed,
        secondarySelectedColor: seed,
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? darkBase : ink,
          ),
        ),
        secondaryLabelStyle: const TextStyle(color: darkBase),
        checkmarkColor: darkBase,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? darkBase : ink,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? seed : card,
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? darkBase : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? seed
              : scheme.surfaceContainerHighest,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: dark ? seed : graphite,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: seed,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? darkBase
                : secondaryInk,
          ),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ink),
        ),
      ),
    );
  }
}
