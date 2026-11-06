import 'package:flutter/material.dart';

import 'reference_palettes.dart';

/// Shared dimensions keep dense finance views calm and consistent.
abstract final class Space {
  static const double xs = 6, sm = 12, md = 20, lg = 28, xl = 36;
}

/// Semantic finance colors keep product widgets independent of visual presets.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.expense,
    required this.income,
    required this.iconBackground,
    required this.iconForeground,
    required this.brandBackground,
    required this.brandForeground,
  });
  final Color expense,
      income,
      iconBackground,
      iconForeground,
      brandBackground,
      brandForeground;

  static FinanceColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FinanceColors>() ??
        FinanceColors(
          expense: theme.colorScheme.error,
          income: theme.colorScheme.primary,
          iconBackground: theme.colorScheme.surfaceContainerHigh,
          iconForeground: theme.colorScheme.onSurface,
          brandBackground: theme.colorScheme.primaryContainer,
          brandForeground: theme.colorScheme.onPrimaryContainer,
        );
  }

  @override
  FinanceColors copyWith({
    Color? expense,
    Color? income,
    Color? iconBackground,
    Color? iconForeground,
    Color? brandBackground,
    Color? brandForeground,
  }) => FinanceColors(
    expense: expense ?? this.expense,
    income: income ?? this.income,
    iconBackground: iconBackground ?? this.iconBackground,
    iconForeground: iconForeground ?? this.iconForeground,
    brandBackground: brandBackground ?? this.brandBackground,
    brandForeground: brandForeground ?? this.brandForeground,
  );

  @override
  FinanceColors lerp(covariant FinanceColors? other, double t) {
    if (other == null) {
      return this;
    }
    return FinanceColors(
      expense: Color.lerp(expense, other.expense, t)!,
      income: Color.lerp(income, other.income, t)!,
      iconBackground: Color.lerp(iconBackground, other.iconBackground, t)!,
      iconForeground: Color.lerp(iconForeground, other.iconForeground, t)!,
      brandBackground: Color.lerp(brandBackground, other.brandBackground, t)!,
      brandForeground: Color.lerp(brandForeground, other.brandForeground, t)!,
    );
  }
}

/// Painted app background (1.8): a vertical gradient that starts tinted by
/// the palette and two soft color glows. The plain [ThemeData.scaffoldBackgroundColor]
/// stays the palette's base color underneath.
@immutable
class FinanceBackdrop extends ThemeExtension<FinanceBackdrop> {
  const FinanceBackdrop({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.glowA,
    required this.glowB,
  });
  final Color top, middle, bottom, glowA, glowB;

  static FinanceBackdrop of(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerLowest;
    return theme.extension<FinanceBackdrop>() ??
        FinanceBackdrop(
          top: base,
          middle: base,
          bottom: base,
          glowA: Colors.transparent,
          glowB: Colors.transparent,
        );
  }

  /// Derives a backdrop from a base color and two accents.
  factory FinanceBackdrop.derive({
    required bool dark,
    required Color base,
    required Color tint,
    required Color glow,
    required Color second,
    double strength = 1,
  }) => FinanceBackdrop(
    top: Color.lerp(base, tint, (dark ? .42 : .30) * strength)!,
    middle: Color.lerp(base, tint, (dark ? .12 : .08) * strength)!,
    bottom: Color.lerp(base, second, (dark ? .16 : .12) * strength)!,
    glowA: glow.withValues(alpha: (dark ? .20 : .26) * strength),
    glowB: second.withValues(alpha: (dark ? .16 : .20) * strength),
  );

  @override
  FinanceBackdrop copyWith({
    Color? top,
    Color? middle,
    Color? bottom,
    Color? glowA,
    Color? glowB,
  }) => FinanceBackdrop(
    top: top ?? this.top,
    middle: middle ?? this.middle,
    bottom: bottom ?? this.bottom,
    glowA: glowA ?? this.glowA,
    glowB: glowB ?? this.glowB,
  );

  @override
  FinanceBackdrop lerp(covariant FinanceBackdrop? other, double t) {
    if (other == null) return this;
    return FinanceBackdrop(
      top: Color.lerp(top, other.top, t)!,
      middle: Color.lerp(middle, other.middle, t)!,
      bottom: Color.lerp(bottom, other.bottom, t)!,
      glowA: Color.lerp(glowA, other.glowA, t)!,
      glowB: Color.lerp(glowB, other.glowB, t)!,
    );
  }
}

/// Finance supports the warm Coffee palette and preserves earlier presets.
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

  static const coffeeBase = Color(0xFF0F0C08);
  static const coffeeCard = Color(0xFF231A12);
  static const coffeeTaupe = Color(0xFF886B4B);
  static const coffeeHighlight = Color(0xFFFBE88C);
  static const coffeeMilk = Color(0xFFF7F5F1);
  static const coffeeCoral = Color(0xFFD67C7E);

  static const presetNames = <String, String>{
    'coffee': 'Coffee · тёплый',
    'lime': 'Lime · фирменный',
    'electric': 'Electric · яркий',
    'sage': 'Sage · спокойный',
    'graphite': 'Graphite · строгий',
    'paper': 'Paper · мягкий',
    'midnight': 'Midnight · глубокий',
    'harbor': 'Harbor · морской',
    'forest': 'Forest · природный',
    'velvet': 'Lavender · мягкий',
    'aurora': 'Aurora · вечерний',
    'royal': 'Royal / Nitro · контрастный',
    'sunset': 'Sunset · закатный',
    'rose': 'Rose · пудровый',
    'neon': 'Neon · яркий',
    'crimson': 'Crimson · бордо и синий',
    'dusk': 'Dusk · сумеречный',
    'emerald': 'Emerald · изумрудный',
    'tropic': 'Tropic · тропический',
    'twilight': 'Twilight · пастельный',
    'plum': 'Plum · сливовый',
    'wine': 'Wine · винный',
    'copper': 'Copper · медный',
    'sand': 'Sand · песочный',
    'apricot': 'Apricot · абрикосовый',
    'terracotta': 'Holst · терракотовый',
  };

  static Color accent(String value) => switch (value) {
    'coffee' => coffeeHighlight,
    _ when referencePalettes.containsKey(value) =>
      referencePalettes[value]!.accent,
    'harbor' => referencePalettes['harbor']!.accent,
    'forest' => referencePalettes['forest']!.accent,
    'velvet' => referencePalettes['velvet']!.accent,
    'aurora' => referencePalettes['aurora']!.accent,
    'royal' => referencePalettes['royal']!.accent,
    'electric' => electric,
    'sage' => sage,
    'graphite' => const Color(0xFFBFC9B4),
    'paper' => const Color(0xFFD9E5C8),
    'midnight' => const Color(0xFFB6D86A),
    // Legacy accents remain readable, without reviving the old multicolor UI.
    _ => lime,
  };

  /// Theme used by the running app: [build] plus a transparent scaffold so
  /// the painted [FinanceBackdrop] shows behind every screen.
  static ThemeData app(Brightness brightness, String selected) {
    final theme = build(brightness, selected);
    return theme.copyWith(scaffoldBackgroundColor: Colors.transparent);
  }

  static ThemeData build(Brightness brightness, String selected) {
    if (selected == 'coffee') {
      return _coffee(brightness);
    }
    final reference = referencePalettes[selected];
    if (reference != null) {
      return _reference(brightness, reference);
    }
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
      extensions: [
        FinanceBackdrop.derive(
          dark: dark,
          base: dark ? darkBase : lightBase,
          tint: dark ? Color.lerp(seed, const Color(0xFF1E3A2A), .45)! : seed,
          glow: seed,
          second: dark ? sage : const Color(0xFF9EC5B0),
        ),
        FinanceColors(
          expense: dark ? const Color(0xFFD6B58E) : const Color(0xFF7A6046),
          income: dark ? seed : graphite,
          iconBackground: scheme.surfaceContainerHigh,
          iconForeground: ink,
          brandBackground: scheme.primaryContainer,
          brandForeground: scheme.onPrimaryContainer,
        ),
      ],
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

  /// One component mapping serves all five references. Coffee and the earlier
  /// presets retain their own mappings so existing preferences do not change.
  static ThemeData _reference(Brightness brightness, ReferencePalette palette) {
    final dark = brightness == Brightness.dark;
    final inherited = build(brightness, 'lime');
    final base = dark
        ? palette.base
        : Color.lerp(palette.ink, Colors.white, .84)!;
    final card = dark
        ? palette.card
        : Color.lerp(palette.ink, Colors.white, .95)!;
    final panel = dark
        ? palette.panel
        : Color.lerp(palette.panel, Colors.white, .88)!;
    final ink = dark ? palette.ink : palette.base;
    final inputFill = dark ? Color.lerp(panel, card, .6)! : panel;
    final surfaces = [base, card];
    final mutedInk = _readable(Color.lerp(ink, card, .26)!, surfaces);
    final actionInk = _readable(palette.accent, surfaces);
    final accentInk = _onFill(palette.accent, palette);
    final buttonInk = _onFill(palette.panel, palette);
    final line = Color.lerp(
      palette.panel,
      dark ? palette.ink : palette.base,
      .25,
    )!;
    final subtleLine = dark
        ? palette.panel
        : Color.lerp(palette.panel, Colors.white, .68)!;
    final inverse = dark ? palette.ink : palette.card;
    final inverseInk = _onFill(inverse, palette);
    final colors = FinanceColors(
      income: _readable(palette.accent, surfaces),
      expense: _readable(palette.signal, surfaces),
      iconBackground: panel,
      iconForeground: _onFill(panel, palette),
      brandBackground: card,
      brandForeground: ink,
    );
    final scheme = inherited.colorScheme.copyWith(
      primary: actionInk,
      onPrimary: _onFill(actionInk, palette),
      primaryContainer: panel,
      onPrimaryContainer: colors.iconForeground,
      secondary: palette.panel,
      onSecondary: buttonInk,
      secondaryContainer: panel,
      onSecondaryContainer: ink,
      tertiary: palette.signal,
      onTertiary: _onFill(palette.signal, palette),
      tertiaryContainer: dark
          ? Color.lerp(palette.signal, card, .72)!
          : Color.lerp(palette.signal, Colors.white, .9)!,
      onTertiaryContainer: ink,
      surface: card,
      onSurface: ink,
      onSurfaceVariant: mutedInk,
      surfaceContainerLowest: base,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: panel,
      surfaceContainerHighest: dark
          ? Color.lerp(palette.panel, palette.signal, .22)!
          : Color.lerp(palette.panel, Colors.white, .8)!,
      outline: line,
      outlineVariant: subtleLine,
      surfaceTint: Colors.transparent,
      inverseSurface: inverse,
      onInverseSurface: inverseInk,
      inversePrimary: _readable(palette.accent, [inverse]),
      error: dark ? const Color(0xFFFFB4AB) : const Color(0xFF9C3331),
      onError: dark ? const Color(0xFF5F1411) : Colors.white,
      errorContainer: dark ? const Color(0xFF5F1411) : const Color(0xFFFFDAD6),
      onErrorContainer: dark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF5F1411),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    Color selectedInk(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) ? accentInk : ink;
    Color selectedFill(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) ? palette.accent : card;
    Color dayInk(Set<WidgetState> states) =>
        states.contains(WidgetState.disabled)
        ? mutedInk.withValues(alpha: .4)
        : selectedInk(states);
    Color dayFill(Set<WidgetState> states) =>
        states.contains(WidgetState.selected)
        ? palette.accent
        : Colors.transparent;
    return inherited.copyWith(
      colorScheme: scheme,
      canvasColor: card,
      cardColor: card,
      dividerColor: subtleLine,
      primaryColor: palette.accent,
      focusColor: palette.accent.withValues(alpha: .16),
      hoverColor: palette.accent.withValues(alpha: .06),
      highlightColor: palette.accent.withValues(alpha: .12),
      splashColor: palette.accent.withValues(alpha: .12),
      scaffoldBackgroundColor: base,
      extensions: [
        colors,
        FinanceBackdrop.derive(
          dark: dark,
          base: base,
          tint: dark ? palette.panel : palette.accent,
          glow: palette.accent,
          second: palette.signal,
        ),
      ],
      textTheme: inherited.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: inherited.appBarTheme.copyWith(foregroundColor: ink),
      iconTheme: IconThemeData(color: colors.iconForeground),
      dividerTheme: inherited.dividerTheme.copyWith(color: subtleLine),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: inherited.textTheme.headlineSmall?.copyWith(color: ink),
        contentTextStyle: inherited.textTheme.bodyMedium?.copyWith(
          color: mutedInk,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: inherited.bottomSheetTheme.copyWith(
        backgroundColor: card,
        dragHandleColor: line,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: inverse,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(color: inverseInk),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: ink),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        textColor: ink,
        iconColor: _readable(palette.accent, surfaces),
        selectedColor: actionInk,
        selectedTileColor: Color.alphaBlend(
          palette.accent.withValues(alpha: .12),
          card,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: actionInk,
        unselectedLabelColor: mutedInk,
        indicatorColor: actionInk,
        dividerColor: subtleLine,
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(card),
        textStyle: WidgetStatePropertyAll(TextStyle(color: ink)),
        hintStyle: WidgetStatePropertyAll(TextStyle(color: mutedInk)),
      ),
      searchViewTheme: SearchViewThemeData(
        backgroundColor: card,
        headerTextStyle: TextStyle(color: ink),
        headerHintStyle: TextStyle(color: mutedInk),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: inherited.inputDecorationTheme.copyWith(
        fillColor: inputFill,
        labelStyle: TextStyle(color: _readable(mutedInk, [inputFill])),
        hintStyle: TextStyle(color: _readable(mutedInk, [inputFill])),
        prefixIconColor: colors.iconForeground,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: subtleLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: actionInk, width: 1.5),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: actionInk,
        selectionColor: palette.accent.withValues(alpha: .25),
        selectionHandleColor: actionInk,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.panel,
          foregroundColor: buttonInk,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
          shape: shape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.panel,
          foregroundColor: buttonInk,
          surfaceTintColor: Colors.transparent,
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: actionInk),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: subtleLine),
          shape: shape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _readable(palette.accent, surfaces),
        ),
      ),
      chipTheme: inherited.chipTheme.copyWith(
        backgroundColor: card,
        selectedColor: palette.accent,
        secondarySelectedColor: palette.accent,
        side: BorderSide(color: subtleLine),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(color: selectedInk(states)),
        ),
        secondaryLabelStyle: TextStyle(color: accentInk),
        checkmarkColor: accentInk,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(selectedInk),
          backgroundColor: WidgetStateProperty.resolveWith(selectedFill),
          side: WidgetStatePropertyAll(BorderSide(color: subtleLine)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accentInk : mutedInk,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? palette.accent : panel,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? palette.accent : null,
        ),
        checkColor: WidgetStatePropertyAll(accentInk),
        side: BorderSide(color: line),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? actionInk : mutedInk,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: actionInk,
        thumbColor: actionInk,
        inactiveTrackColor: subtleLine,
        overlayColor: palette.accent.withValues(alpha: .12),
        valueIndicatorColor: palette.panel,
        valueIndicatorTextStyle: TextStyle(color: buttonInk),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: palette.accent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: selectedInk(states)),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected) ? actionInk : mutedInk,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: card,
        indicatorColor: palette.accent,
        selectedIconTheme: IconThemeData(color: accentInk),
        unselectedIconTheme: IconThemeData(color: mutedInk),
        selectedLabelTextStyle: TextStyle(color: actionInk),
        unselectedLabelTextStyle: TextStyle(color: mutedInk),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: actionInk,
        unselectedItemColor: mutedInk,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: actionInk,
        linearTrackColor: subtleLine,
      ),
      snackBarTheme: inherited.snackBarTheme.copyWith(
        backgroundColor: inverse,
        contentTextStyle: TextStyle(color: inverseInk),
        actionTextColor: _readable(palette.accent, [inverse]),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: card,
        headerForegroundColor: ink,
        weekdayStyle: TextStyle(color: mutedInk),
        dayForegroundColor: WidgetStateProperty.resolveWith(dayInk),
        dayBackgroundColor: WidgetStateProperty.resolveWith(dayFill),
        todayForegroundColor: WidgetStateProperty.resolveWith(selectedInk),
        todayBackgroundColor: WidgetStateProperty.resolveWith(dayFill),
        todayBorder: BorderSide(color: actionInk),
        yearForegroundColor: WidgetStateProperty.resolveWith(dayInk),
        yearBackgroundColor: WidgetStateProperty.resolveWith(dayFill),
        rangePickerBackgroundColor: card,
        rangePickerSurfaceTintColor: Colors.transparent,
        rangePickerHeaderBackgroundColor: card,
        rangePickerHeaderForegroundColor: ink,
        rangeSelectionBackgroundColor: palette.accent.withValues(alpha: .16),
        dividerColor: subtleLine,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: card,
        dialBackgroundColor: panel,
        dialHandColor: palette.accent,
        dialTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentInk
              : colors.iconForeground,
        ),
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? palette.accent : panel,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentInk
              : colors.iconForeground,
        ),
        dayPeriodColor: WidgetStateColor.resolveWith(selectedFill),
        dayPeriodTextColor: WidgetStateColor.resolveWith(selectedInk),
        entryModeIconColor: actionInk,
        helpTextStyle: TextStyle(color: mutedInk),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.panel,
        foregroundColor: buttonInk,
      ),
    );
  }

  static double _contrast(Color foreground, Color background) {
    final a = foreground.computeLuminance(), b = background.computeLuminance();
    return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
  }

  static Color _onFill(Color fill, ReferencePalette palette) {
    final candidate =
        _contrast(palette.base, fill) >= _contrast(palette.ink, fill)
        ? palette.base
        : palette.ink;
    if (_contrast(candidate, fill) >= 4.5) return candidate;
    return _contrast(Colors.black, fill) >= _contrast(Colors.white, fill)
        ? Colors.black
        : Colors.white;
  }

  /// Preserve hue whenever possible; move only text toward white/black until
  /// it reaches AA on all surfaces where the same semantic amount is displayed.
  static Color _readable(Color original, List<Color> backgrounds) {
    bool passes(Color value) =>
        backgrounds.every((bg) => _contrast(value, bg) >= 4.5);
    if (passes(original)) return original;
    double worst(Color value) => backgrounds
        .map((bg) => _contrast(value, bg))
        .reduce((a, b) => a < b ? a : b);
    final target = worst(Colors.white) > worst(Colors.black)
        ? Colors.white
        : Colors.black;
    for (var step = 1; step <= 100; step++) {
      final value = Color.lerp(original, target, step / 100)!;
      if (passes(value)) return value;
    }
    return target;
  }

  static ThemeData _coffee(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final inherited = build(brightness, 'lime');
    final ink = dark ? coffeeMilk : coffeeBase;
    final secondaryInk = dark
        ? const Color(0xFFBEAD99)
        : const Color(0xFF6E5C48);
    final card = dark ? coffeeCard : const Color(0xFFFEFCF8);
    final base = dark ? coffeeBase : coffeeMilk;
    final elevated = dark ? const Color(0xFF30251B) : const Color(0xFFEDE7DF);
    final outline = dark ? const Color(0xFF665541) : const Color(0xFFCFC4B7);
    final scheme = inherited.colorScheme.copyWith(
      primary: coffeeHighlight,
      onPrimary: coffeeBase,
      primaryContainer: dark
          ? const Color(0xFF3E3420)
          : const Color(0xFFF2E8C6),
      onPrimaryContainer: ink,
      secondary: coffeeTaupe,
      onSecondary: coffeeMilk,
      secondaryContainer: elevated,
      onSecondaryContainer: ink,
      tertiary: dark ? const Color(0xFFC1A98B) : const Color(0xFF6E5C48),
      onTertiary: dark ? coffeeBase : coffeeMilk,
      surface: card,
      onSurface: ink,
      onSurfaceVariant: secondaryInk,
      surfaceContainerLowest: base,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: elevated,
      surfaceContainerHighest: dark
          ? const Color(0xFF403021)
          : const Color(0xFFE1D7C9),
      outline: dark ? const Color(0xFF9B856B) : const Color(0xFF806A52),
      outlineVariant: outline,
      error: dark ? coffeeCoral : const Color(0xFF9F4448),
      onError: dark ? coffeeBase : coffeeMilk,
      errorContainer: dark ? const Color(0xFF4B2524) : const Color(0xFFF4DDDA),
      onErrorContainer: dark
          ? const Color(0xFFF7D1CF)
          : const Color(0xFF6B2429),
      inverseSurface: dark ? coffeeMilk : coffeeCard,
      onInverseSurface: dark ? coffeeBase : coffeeMilk,
      inversePrimary: dark ? const Color(0xFF6E5C48) : coffeeHighlight,
    );
    final colors = FinanceColors(
      expense: dark ? coffeeCoral : const Color(0xFF9F4448),
      income: dark ? coffeeHighlight : const Color(0xFF66532A),
      iconBackground: dark ? coffeeTaupe : const Color(0xFFE7DDD0),
      iconForeground: dark ? coffeeMilk : const Color(0xFF5E4831),
      brandBackground: dark ? coffeeCard : const Color(0xFFEDE4D8),
      brandForeground: ink,
    );
    Color selectedInk(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) ? coffeeBase : ink;
    Color selectedFill(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) ? coffeeHighlight : card;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    return inherited.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: base,
      extensions: [
        colors,
        // Espresso: warm brown top, lemon and coral glows instead of black.
        FinanceBackdrop.derive(
          dark: dark,
          base: base,
          tint: dark ? coffeeTaupe : coffeeHighlight,
          glow: coffeeHighlight,
          second: coffeeCoral,
        ),
      ],
      textTheme: inherited.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: inherited.appBarTheme.copyWith(foregroundColor: ink),
      iconTheme: IconThemeData(color: colors.iconForeground),
      dividerTheme: inherited.dividerTheme.copyWith(color: outline),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: inherited.textTheme.headlineSmall?.copyWith(color: ink),
        contentTextStyle: inherited.textTheme.bodyMedium?.copyWith(
          color: secondaryInk,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: inherited.bottomSheetTheme.copyWith(
        backgroundColor: card,
        dragHandleColor: scheme.outline,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: inherited.inputDecorationTheme.copyWith(
        fillColor: elevated,
        labelStyle: TextStyle(color: secondaryInk),
        hintStyle: TextStyle(color: secondaryInk),
        prefixIconColor: secondaryInk,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: coffeeTaupe, width: 1.5),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: dark ? coffeeHighlight : coffeeTaupe,
        selectionColor: coffeeHighlight.withValues(alpha: .28),
        selectionHandleColor: coffeeTaupe,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: coffeeTaupe,
          foregroundColor: coffeeMilk,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: coffeeTaupe,
          foregroundColor: coffeeMilk,
          surfaceTintColor: Colors.transparent,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? coffeeMilk : const Color(0xFF6E5C48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: outline),
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: colors.iconForeground),
      ),
      chipTheme: inherited.chipTheme.copyWith(
        backgroundColor: card,
        selectedColor: coffeeHighlight,
        secondarySelectedColor: coffeeHighlight,
        side: BorderSide(color: outline),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(color: selectedInk(states)),
        ),
        secondaryLabelStyle: const TextStyle(color: coffeeBase),
        checkmarkColor: coffeeBase,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(selectedInk),
          backgroundColor: WidgetStateProperty.resolveWith(selectedFill),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? coffeeBase : secondaryInk,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? coffeeHighlight
              : elevated,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? coffeeHighlight : null,
        ),
        checkColor: const WidgetStatePropertyAll(coffeeBase),
        side: BorderSide(color: scheme.outline),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (dark ? coffeeHighlight : coffeeTaupe)
              : secondaryInk,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: coffeeHighlight,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: selectedInk(states)),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ink),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: card,
        indicatorColor: coffeeHighlight,
        selectedIconTheme: const IconThemeData(color: coffeeBase),
        unselectedIconTheme: IconThemeData(color: secondaryInk),
        selectedLabelTextStyle: TextStyle(
          color: dark ? coffeeHighlight : coffeeBase,
        ),
        unselectedLabelTextStyle: TextStyle(color: secondaryInk),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: dark ? coffeeHighlight : coffeeBase,
        unselectedItemColor: secondaryInk,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: coffeeTaupe,
        linearTrackColor: elevated,
      ),
      snackBarTheme: inherited.snackBarTheme.copyWith(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: dark ? const Color(0xFF6E5C48) : coffeeHighlight,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: card,
        headerForegroundColor: ink,
        weekdayStyle: TextStyle(color: secondaryInk),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? secondaryInk.withValues(alpha: .45)
              : selectedInk(states),
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? coffeeHighlight
              : Colors.transparent,
        ),
        todayForegroundColor: WidgetStateProperty.resolveWith(selectedInk),
        todayBorder: const BorderSide(color: coffeeTaupe),
        yearForegroundColor: WidgetStateProperty.resolveWith(selectedInk),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? coffeeHighlight
              : Colors.transparent,
        ),
        rangePickerBackgroundColor: card,
        rangePickerSurfaceTintColor: Colors.transparent,
        rangePickerHeaderBackgroundColor: card,
        rangePickerHeaderForegroundColor: ink,
        rangeSelectionBackgroundColor: coffeeHighlight.withValues(alpha: .16),
        dividerColor: outline,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: card,
        dialBackgroundColor: elevated,
        dialHandColor: coffeeHighlight,
        dialTextColor: WidgetStateColor.resolveWith(selectedInk),
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? coffeeHighlight
              : elevated,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(selectedInk),
        dayPeriodColor: WidgetStateColor.resolveWith(selectedFill),
        dayPeriodTextColor: WidgetStateColor.resolveWith(selectedInk),
        entryModeIconColor: secondaryInk,
        helpTextStyle: TextStyle(color: secondaryInk),
      ),
    );
  }
}
