import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:image_picker/image_picker.dart';

import '../../domain/account_import_parser.dart';
import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../../services/receipt_image_store.dart';
import '../../services/receipt_ocr_service.dart';
import '../controller.dart';
import '../widgets/common.dart';
import '../l10n_widgets.dart';

/// Moves accounts over from another finance app (Finance 1.21): a screenshot
/// of its account list → names and balances → reviewed → added as accounts
/// with those opening balances. Nothing is added without the person's tap,
/// and the screenshot is deleted afterwards.
class AccountImportScreen extends StatefulWidget {
  const AccountImportScreen({
    super.key,
    this.startPicking = true,
    this.initialPath,
  });

  /// Opens the gallery right away.
  final bool startPicking;

  /// A screenshot to read right away instead of opening the gallery.
  final String? initialPath;
  @override
  State<AccountImportScreen> createState() => _AccountImportScreenState();
}

class _Row {
  _Row(AccountDraft d, {required this.exists})
    : name = TextEditingController(text: d.name),
      amount = TextEditingController(text: decimalMinor(d.amountMinor)),
      currency = d.currency,
      lastFour = d.lastFour,
      bank = d.bank,
      selected = !exists;
  final TextEditingController name, amount;
  final String currency, lastFour, bank;
  final bool exists;
  bool selected;
}

class _AccountImportScreenState extends State<AccountImportScreen> {
  final _images = ReceiptImageStore();
  final _ocr = ReceiptOcrService();
  final _rows = <_Row>[];
  bool _busy = false, _read = false;

  @override
  void initState() {
    super.initState();
    if (widget.startPicking || widget.initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pick(initialPath: widget.initialPath);
      });
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.name.dispose();
      r.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _pick({String? initialPath}) async {
    if (_busy) return;
    final c = FinanceScope.of(context);
    setState(() => _busy = true);
    String? path;
    try {
      path = initialPath == null
          ? await _images.pick(ImageSource.gallery)
          : await _images.copy(XFile(initialPath));
      if (path == null || !mounted) return;
      final result = await _ocr.recognize(path);
      final drafts = AccountImportParser.parse(
        result.text,
        lines: result.lines,
        defaultCurrency: c.currency,
      );
      String key(String s) => s.toLowerCase().replaceAll('ё', 'е').trim();
      final existing = c.data.accounts.map((a) => key(a.name)).toSet();
      if (!mounted) return;
      setState(() {
        _read = true;
        _rows.addAll([
          for (final d in drafts)
            _Row(d, exists: existing.contains(key(d.name))),
        ]);
      });
      if (drafts.isEmpty && mounted) {
        showError(
          context,
          'Счета на скриншоте не найдены. Нужен экран со списком счетов и '
          'суммами, например «Наличные 12 500 ₽».',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      // The screenshot is not kept.
      if (path != null) await _images.discardIfUnused(path, c.data);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final c = FinanceScope.of(context);
    final chosen = _rows.where((r) => r.selected).toList();
    final accounts = <Account>[];
    for (final r in chosen) {
      final name = r.name.text.trim();
      if (name.isEmpty) continue;
      int amount;
      try {
        amount = FinanceEngine.parseMinor(
          r.amount.text.replaceAll(' ', '').replaceAll('−', '-'),
        );
      } catch (_) {
        showError(context, 'Проверьте сумму у счёта «$name».');
        return;
      }
      accounts.add(
        Account(
          id: c.id(),
          name: name,
          type: AccountImportParser.typeFor(name, amount, r.lastFour),
          currency: r.currency,
          bank: r.bank,
          lastFour: r.lastFour,
          openingMinor: amount,
          color: categoryColors[accounts.length % categoryColors.length],
        ),
      );
    }
    if (accounts.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      await c.mutate((d) => d.copyWith(accounts: [...d.accounts, ...accounts]));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлено счетов: ${accounts.length}.')),
      );
      Navigator.pop(context, accounts.length);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _rows.where((r) => r.selected).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Перенос счетов')),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('account-import'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              'Сделайте скриншот списка счетов в другом приложении — Дзен-мани, '
              'CoinKeeper, Monefy, банк. Мы возьмём названия и остатки.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey('account-import-pick'),
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.image_outlined),
              label: Text(_read ? 'Добавить ещё скриншот' : 'Выбрать скриншот'),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
                  child: Row(
                    children: [
                      Checkbox(
                        key: ValueKey('account-import-select-$i'),
                        value: _rows[i].selected,
                        onChanged: (v) =>
                            setState(() => _rows[i].selected = v ?? false),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              key: ValueKey('account-import-name-$i'),
                              controller: _rows[i].name,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Название',
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              key: ValueKey('account-import-amount-$i'),
                              controller: _rows[i].amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: 'Остаток, ${_rows[i].currency}',
                              ),
                            ),
                            if (_rows[i].exists)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Такой счёт уже есть',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_rows.isNotEmpty) ...[
              const SizedBox(height: 6),
              FilledButton(
                key: const ValueKey('account-import-add'),
                onPressed: _busy || count == 0 ? null : _add,
                child: Text('Добавить счетов: $count'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
