import 'amount_expression.dart';
import 'models.dart';
import 'voice_entry_parser.dart';

/// One row of «Несколько операций»: what is known so far. Saved only when
/// the person taps «Сохранить все».
class BatchDraft {
  BatchDraft({
    this.kind = EntryKind.expense,
    this.amountMinor,
    this.payee = '',
    this.categoryId,
    this.serviceId,
  });
  EntryKind kind;
  int? amountMinor;
  String payee;
  String? categoryId;
  String? serviceId;

  bool get ready => amountMinor != null && amountMinor! > 0;
}

/// A list typed or pasted line by line — «кб 500», «такси 350», «зарплата
/// +90 000», «обед 450+120» — read into [BatchDraft]s with the same parser
/// as the voice form. A «+» in front of the sum or the word «доход» makes it
/// income. Lines without a sum are kept (the person fills it in).
abstract final class BatchEntries {
  static List<BatchDraft> parse(
    String text, {
    required List<Category> categories,
    List<FinanceEntry> history = const [],
    String Function(String payee)? resolvePayee,
    String? Function(String payee, EntryKind kind)? rememberedCategory,
    DateTime? now,
  }) {
    final out = <BatchDraft>[];
    for (final raw in text.split(RegExp(r'[\n;]+'))) {
      var line = raw.trim().replaceFirst(RegExp(r'^[-•*·]\s*'), '');
      if (line.isEmpty) continue;
      var income = false;
      // «+90000» or «зарплата +90 000»: income.
      final plus = RegExp(r'(^|\s)\+\s*(?=\d)');
      if (plus.hasMatch(line)) {
        income = true;
        line = line.replaceFirst(plus, ' ').trim();
      }
      // A calculation in the line («450+120», «3×250») is worked out first.
      int? calculated;
      final expr = RegExp(
        r'(\d[\d\s.,]*(?:\s*[+×*/÷−-]\s*\d[\d\s.,]*%?)+)',
      ).firstMatch(line);
      if (expr != null && AmountExpression.isCalculation(expr[1]!)) {
        calculated = AmountExpression.evaluate(expr[1]!);
        if (calculated != null) {
          line = line.replaceRange(expr.start, expr.end, ' ').trim();
        }
      }
      final d = VoiceEntryParser.parse(
        calculated == null ? line : '$line ${_plain(calculated)}',
        categories: categories,
        history: history,
        now: now,
      );
      final kind = income ? EntryKind.income : d.kind;
      var payee = d.payee;
      var category = d.categoryId;
      if (resolvePayee != null && payee.isNotEmpty) {
        final full = resolvePayee(payee);
        if (full != payee) {
          payee = full;
          category =
              VoiceEntryParser.categoryFor(full, kind, categories) ?? category;
        }
      }
      if (payee.isNotEmpty && rememberedCategory != null) {
        category = rememberedCategory(payee, kind) ?? category;
      }
      // A category of the other kind does not fit.
      if (category != null &&
          !categories.any((c) => c.id == category && c.kind == kind)) {
        category = null;
      }
      out.add(
        BatchDraft(
          kind: kind,
          amountMinor: d.amountMinor,
          payee: payee,
          categoryId: category,
          serviceId: d.serviceId,
        ),
      );
    }
    return out;
  }

  /// [minor] as a sum the voice parser reads: «570», «123,45».
  static String _plain(int minor) {
    final whole = minor ~/ 100;
    final cents = minor % 100;
    return cents == 0 ? '$whole' : '$whole,${cents.toString().padLeft(2, '0')}';
  }
}
