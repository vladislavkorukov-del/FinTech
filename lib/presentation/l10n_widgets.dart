import 'package:flutter/material.dart' as m;

import 'i18n.dart';

/// 1.37: the app's [Text] — the same widget, but its line is shown in the
/// chosen language ([AppLanguage]); Russian is the source. Every screen
/// imports Flutter's material library without `Text` and uses this one.
class Text extends m.Text {
  const Text(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final source = data;
    if (AppLanguage.code == 'ru' || source == null) return super.build(context);
    final shown = AppLanguage.t(source);
    if (shown == source) return super.build(context);
    return m.Text(
      shown,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      semanticsIdentifier: semanticsIdentifier,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

/// 1.37: [m.InputDecoration] whose label, hint, helper and error lines are
/// shown in the chosen language.
class InputDecoration extends m.InputDecoration {
  const InputDecoration({
    super.icon,
    super.iconColor,
    super.label,
    super.labelText,
    super.labelStyle,
    super.floatingLabelStyle,
    super.helper,
    super.helperText,
    super.helperStyle,
    super.helperMaxLines,
    super.hintText,
    super.hint,
    super.hintStyle,
    super.hintTextDirection,
    super.hintMaxLines,
    super.hintFadeDuration,
    super.maintainHintSize = true,
    super.maintainLabelSize = false,
    super.error,
    super.errorText,
    super.errorStyle,
    super.errorMaxLines,
    super.floatingLabelBehavior,
    super.floatingLabelAlignment,
    super.isCollapsed,
    super.isDense,
    super.contentPadding,
    super.prefixIcon,
    super.prefixIconConstraints,
    super.prefix,
    super.prefixText,
    super.prefixStyle,
    super.prefixIconColor,
    super.suffixIcon,
    super.suffix,
    super.suffixText,
    super.suffixStyle,
    super.suffixIconColor,
    super.suffixIconConstraints,
    super.counter,
    super.counterText,
    super.counterStyle,
    super.filled,
    super.fillColor,
    super.focusColor,
    super.hoverColor,
    super.errorBorder,
    super.focusedBorder,
    super.focusedErrorBorder,
    super.disabledBorder,
    super.enabledBorder,
    super.border,
    super.enabled = true,
    super.semanticCounterText,
    super.alignLabelWithHint,
    super.constraints,
    super.visualDensity,
  });

  static String? _t(String? s) => s == null ? null : AppLanguage.t(s);

  @override
  String? get labelText => _t(super.labelText);
  @override
  String? get hintText => _t(super.hintText);
  @override
  String? get helperText => _t(super.helperText);
  @override
  String? get errorText => _t(super.errorText);
}
