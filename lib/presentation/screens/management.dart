import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/payment_plan.dart';
import '../../domain/service_catalog.dart';
import '../../domain/service_recognizer.dart';
import '../../domain/voice_entry_parser.dart';
import '../widgets/bank_picker.dart';
import '../widgets/savings_pace.dart';
import '../widgets/service_badge.dart';
import '../../domain/finance_engine.dart';
import '../controller.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../widgets/amount_format.dart';
import '../widgets/common.dart';
import '../widgets/finora_orb.dart';
import '../widgets/grouped_list.dart';
import 'account_import_screen.dart';
import 'entry_editor.dart';
import 'settings.dart';
import '../l10n_widgets.dart';

part 'management_accounts.dart';
part 'management_categories.dart';
part 'management_budgets.dart';
part 'management_goals.dart';
part 'management_recurring.dart';
part 'management_payments.dart';
part 'management_shopping.dart';
part 'management_calendar.dart';
part 'management_family.dart';
part 'management_more.dart';

void openFinancePage(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
Future<void> _attempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      showError(context, e);
    }
  }
}

TextEditingController _text([String value = '']) =>
    TextEditingController(text: value);
String _date(DateTime date, FinanceController c) => DateFormat(
  c.data.preferences.dateFormat,
  AppLanguage.intl,
).format(date.toLocal());
String _amount(int value) => groupAmount(
  '${value < 0 ? '-' : ''}${value.abs() ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}',
);
Widget _field(
  TextEditingController controller,
  String label, {
  bool amount = false,
  int? maxLength,
  String? help,
  String? hint,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      // 1.37: an example of what to write.
      hintText: hint,
      floatingLabelBehavior: hint == null ? null : FloatingLabelBehavior.always,
      helperText: help,
      counterText: '',
    ),
    maxLength: maxLength,
    keyboardType: amount
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : TextInputType.text,
    inputFormatters: amount ? const [AmountGroupingFormatter()] : null,
    validator: (v) => v == null || v.trim().isEmpty ? 'Заполните поле' : null,
  ),
);
Widget _select<T>(
  String label,
  T value,
  Map<T, String> options,
  void Function(T) change, {
  bool enabled = true,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items:
        {...options, if (!options.containsKey(value)) value: value.toString()}
            .entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
    onChanged: enabled
        ? (v) {
            if (v != null) {
              change(v);
            }
          }
        : null,
  ),
);
Widget _optional(
  TextEditingController controller,
  String label, {
  int? maxLength,
  String? hint,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: hint == null ? null : FloatingLabelBehavior.always,
      counterText: '',
    ),
    maxLength: maxLength,
  ),
);
Widget _colors(int value, void Function(int) change) => Wrap(
  spacing: 10,
  runSpacing: 10,
  children: categoryColors
      .map(
        (c) => Semantics(
          label: 'Цвет ${c.toRadixString(16)}',
          selected: c == value,
          button: true,
          child: InkWell(
            onTap: () => change(c),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: value == c ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              child: value == c
                  ? const Icon(Icons.check, size: 20, color: Colors.black)
                  : null,
            ),
          ),
        ),
      )
      .toList(),
);
Future<void> _edit(
  BuildContext context, {
  required String title,
  List<TextEditingController> controllers = const [],
  required List<Widget> Function(StateSetter set) fields,
  required Future<void> Function() save,
  Future<void> Function()? delete,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _Editor(
    title: title,
    controllers: controllers,
    fields: fields,
    save: save,
    delete: delete,
  ),
);

class _Editor extends StatefulWidget {
  const _Editor({
    required this.title,
    required this.controllers,
    required this.fields,
    required this.save,
    this.delete,
  });
  final String title;
  final List<TextEditingController> controllers;
  final List<Widget> Function(StateSetter) fields;
  final Future<void> Function() save;
  final Future<void> Function()? delete;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.save();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 22),
                ...widget.fields((fn) {
                  setState(fn);
                }),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить'),
                ),
                if (widget.delete != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!await confirm(
                              context,
                              'Удалить запись?',
                              'Это действие нельзя отменить.',
                            )) {
                              return;
                            }
                            setState(() => _busy = true);
                            try {
                              await widget.delete!();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                showError(context, e);
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _busy = false);
                              }
                            }
                          },
                    child: Text(
                      'Удалить',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
