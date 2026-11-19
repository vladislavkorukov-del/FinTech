import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/services.dart';

import '../../domain/amount_expression.dart';
import 'amount_format.dart';
import '../l10n_widgets.dart';

/// Compact, accessible amount entry with a calculator: digits, a comma,
/// `+ − × ÷`, `%`, `=` and clear. While a calculation is typed, the line
/// above the keys shows it and [controller] already holds the result (so
/// the form always sees a plain amount); `=` keeps just the result. Text is
/// kept decimal until domain parsing; the arithmetic is in whole kopecks
/// ([AmountExpression]).
class AmountPad extends StatefulWidget {
  const AmountPad({super.key, required this.controller});
  final TextEditingController controller;

  static const keys = [
    '7', '8', '9', '÷', //
    '4', '5', '6', '×', //
    '1', '2', '3', '−', //
    ',', '0', '⌫', '+', //
    'C', '00', '%', '=', //
  ];

  /// [minor] as the field shows it: «570», «123,45», «−20».
  static String format(int minor) {
    final whole = (minor.abs() ~/ 100).toString();
    final cents = minor.abs() % 100;
    final text =
        '${minor < 0 ? '-' : ''}$whole${cents == 0 ? '' : ',${cents.toString().padLeft(2, '0')}'}';
    return groupAmount(text);
  }

  @override
  State<AmountPad> createState() => _AmountPadState();
}

class _AmountPadState extends State<AmountPad> {
  /// What has been typed, without spaces («450+120», «1200×3»).
  String _expr = '';

  /// The text this pad last put into the controller; anything else there
  /// came from outside (voice, a scan, a suggestion) and restarts the
  /// calculation from it.
  String? _written;

  @override
  void initState() {
    super.initState();
    _adopt();
    widget.controller.addListener(_outside);
  }

  @override
  void didUpdateWidget(AmountPad old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_outside);
      widget.controller.addListener(_outside);
      _adopt();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_outside);
    super.dispose();
  }

  void _adopt() {
    _expr = widget.controller.text.replaceAll(RegExp('[ \u00A0\u202F]'), '');
    _written = widget.controller.text;
  }

  void _outside() {
    if (widget.controller.text != _written) setState(_adopt);
  }

  bool get _calculation => AmountExpression.isCalculation(_expr);

  /// The number being typed at the end of the expression.
  String get _tail => RegExp(r'[\d,]*%?$').firstMatch(_expr)?.group(0) ?? '';

  static bool _isOp(String ch) => AmountExpression.operators.contains(ch);

  void _input(String key) {
    var e = _expr;
    final last = e.isEmpty ? '' : e[e.length - 1];
    switch (key) {
      case '⌫':
        e = e.isEmpty ? '' : e.substring(0, e.length - 1);
      case 'C':
        e = '';
      case '=':
        if (!_calculation) return;
        final v = AmountExpression.evaluate(e);
        if (v == null) return;
        e = AmountPad.format(v).replaceAll(RegExp('[ \u00A0\u202F]'), '');
      case ',':
        if (_tail.contains(',') || _tail.endsWith('%')) return;
        e = _tail.isEmpty ? '${e}0,' : '$e,';
      case '%':
        if (!RegExp(r'\d$').hasMatch(e)) return;
        e = '$e%';
      case '+' || '−' || '×' || '÷':
        if (e.isEmpty) return;
        if (last == ',') e = e.substring(0, e.length - 1);
        if (_isOp(last)) e = e.substring(0, e.length - 1);
        if (e.isEmpty) return;
        e = '$e$key';
      default:
        if (_tail.endsWith('%')) return;
        final number = '$_tail$key';
        if (!RegExp(r'^\d{0,14}(,\d{0,2})?$').hasMatch(number)) return;
        // «0» then a digit replaces the zero.
        if (_tail == '0') e = e.substring(0, e.length - 1);
        e = '$e$key';
    }
    HapticFeedback.selectionClick();
    String shown;
    if (AmountExpression.isCalculation(e)) {
      final v = AmountExpression.evaluate(e);
      shown = v == null ? '' : AmountPad.format(v);
    } else {
      shown = groupAmount(e);
    }
    setState(() {
      _expr = e;
      _written = shown;
    });
    widget.controller.value = TextEditingValue(
      text: shown,
      selection: TextSelection.collapsed(offset: shown.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          child: _calculation
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 4),
                  child: Text(
                    '${AmountExpression.pretty(_expr)} =',
                    key: const ValueKey('amount-expression'),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        LayoutBuilder(
          builder: (context, box) {
            // Keys about 1.75 : 1, but never taller than 54 px (a wide
            // screen or landscape).
            final width = (box.maxWidth - 18) / 4;
            final height = (width / 1.75).clamp(38.0, 54.0);
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: width / height,
              children: [
                for (final key in AmountPad.keys)
                  _DigitButton(
                    label: key,
                    accent:
                        _isOp(key) || key == '=' || key == '%' || key == 'C',
                    onTap: () => _input(key),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DigitButton extends StatefulWidget {
  const _DigitButton({
    required this.label,
    required this.onTap,
    this.accent = false,
  });
  final String label;
  final bool accent;
  final VoidCallback onTap;
  @override
  State<_DigitButton> createState() => _DigitButtonState();
}

class _DigitButtonState extends State<_DigitButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: switch (widget.label) {
      '⌫' => 'Удалить цифру',
      ',' => 'Десятичный разделитель',
      '+' => 'Плюс',
      '−' => 'Минус',
      '×' => 'Умножить',
      '÷' => 'Разделить',
      '%' => 'Процент',
      '=' => 'Равно',
      'C' => 'Очистить',
      _ => widget.label,
    },
    child: Listener(
      onPointerDown: (_) => setState(() => pressed = true),
      onPointerUp: (_) => setState(() => pressed = false),
      onPointerCancel: (_) => setState(() => pressed = false),
      child: AnimatedScale(
        scale: pressed ? .94 : 1,
        duration: const Duration(milliseconds: 100),
        child: Material(
          color: widget.accent
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .1)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: widget.label == '⌫'
                  ? const Icon(Icons.backspace_outlined, size: 21)
                  : Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: widget.accent
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
