import '../../../domain/models.dart';

/// Links the model's canonical classes to the person's own categories by
/// name, so renamed categories («Еда» for groceries) still work. A class is
/// mapped only when exactly one active category of the right kind fits;
/// otherwise the model's answer for it is not used.
abstract final class CategoryMapper {
  /// Canonical class → name patterns, most specific first.
  static const patterns = <String, List<String>>{
    // Expenses.
    'groceries': [r'продукт|супермаркет|grocer|^еда$|питани'],
    'cafe': [r'кафе|ресторан|фастфуд|кофе|еда вне|cafe|restaurant'],
    'transport': [r'транспорт|такси|проезд|transport|taxi'],
    'car': [r'авто|машин|бензин|топлив|\bcar\b|fuel'],
    'housing': [r'жиль|аренд|ипотек|квартир|rent|housing'],
    'utilities': [r'коммунал|жкх|связь|интернет|utilit'],
    'health': [r'здоров|медиц|врач|health|medic'],
    'pharmacy': [r'аптек|лекарств|pharm', r'здоров|health'],
    'entertainment': [r'развлеч|досуг|кино|entertain|leisure'],
    'subscriptions': [r'подписк|subscript'],
    'shopping': [r'покупк|шопинг|маркетплейс|товар|shopping'],
    'clothes': [r'одежд|обув|clothes', r'покупк|shopping'],
    'gifts': [r'подар|gift'],
    'travel': [r'путешеств|отпуск|поездк|travel|trip'],
    'education': [r'образован|обучен|курс|учеб|educat'],
    'kids': [r'дет|ребен|kids|child'],
    'pets': [r'животн|питом|pets?\b|зоо'],
    'taxes': [r'налог|tax'],
    'loans': [r'кредит|займ|долг|loan'],
    'other': [r'прочее|другое|разное|other'],
    // Incomes.
    'salary': [r'зарплат|оклад|salary'],
    'side_job': [r'подработ|фриланс|freelance|side'],
    'business': [r'бизнес|предприним|business'],
    'interest': [r'процент|interest|кэшб|кешб|cashback'],
    'investments': [r'инвест|дивиденд|invest'],
    'refunds': [r'возврат|refund'],
    'gifts_in': [r'подар|gift'],
    'other_in': [r'прочее|другое|other'],
  };

  static const incomeClasses = {
    'salary',
    'side_job',
    'business',
    'interest',
    'investments',
    'refunds',
    'gifts_in',
    'other_in',
  };

  static EntryKind kindOf(String cls) =>
      incomeClasses.contains(cls) ? EntryKind.income : EntryKind.expense;

  /// The person's category for [cls], or null when none or several fit.
  static String? categoryFor(String cls, List<Category> categories) {
    final kind = kindOf(cls);
    final active = categories
        .where((c) => c.kind == kind && !c.archived)
        .toList();
    for (final p in patterns[cls] ?? const <String>[]) {
      final re = RegExp(p, caseSensitive: false);
      final hits = active.where((c) {
        final name = c.name.toLowerCase().replaceAll('ё', 'е').trim();
        return re.hasMatch(name);
      }).toList();
      if (hits.length == 1) return hits.single.id;
      if (hits.length > 1) return null;
    }
    return null;
  }
}
