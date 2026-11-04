import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Compact, accessible amount entry; text is kept decimal until domain parsing.
class AmountPad extends StatelessWidget {
  const AmountPad({super.key, required this.controller});
  final TextEditingController controller;
  void _input(String key) {
    var value = controller.text;
    if (key == '⌫') {
      value = value.isEmpty ? '' : value.substring(0, value.length - 1);
    } else if (key == ',') {
      if (value.contains(',') || value.contains('.')) {
        return;
      }
      value = '${value.isEmpty ? '0' : value},';
    } else {
      final candidate = '$value$key';
      if (!RegExp(r'^\d{0,14}([.,]\d{0,2})?$').hasMatch(candidate)) {
        return;
      }
      value = value == '0' ? key : candidate;
    }
    HapticFeedback.selectionClick();
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 3,
    mainAxisSpacing: 6,
    crossAxisSpacing: 6,
    childAspectRatio: 2.1,
    children: [
      for (final key in [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        ',',
        '0',
        '⌫',
      ])
        _DigitButton(label: key, onTap: () => _input(key)),
    ],
  );
}

class _DigitButton extends StatefulWidget {
  const _DigitButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_DigitButton> createState() => _DigitButtonState();
}

class _DigitButtonState extends State<_DigitButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label == '⌫'
        ? 'Удалить цифру'
        : widget.label == ','
        ? 'Десятичный разделитель'
        : widget.label,
    child: Listener(
      onPointerDown: (_) => setState(() => pressed = true),
      onPointerUp: (_) => setState(() => pressed = false),
      onPointerCancel: (_) => setState(() => pressed = false),
      child: AnimatedScale(
        scale: pressed ? .94 : 1,
        duration: const Duration(milliseconds: 100),
        child: Material(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: widget.label == '⌫'
                  ? const Icon(Icons.backspace_outlined, size: 21)
                  : Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
