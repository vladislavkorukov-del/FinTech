import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../../features/finora_ai/ui/ai_help_screen.dart';
import '../controller.dart';
import '../l10n_widgets.dart';
import '../widgets/common.dart';
import '../widgets/entry_tile.dart';
import 'achievements_screen.dart';
import 'management.dart';
import 'settings.dart';
import 'transactions.dart';
import 'voice_help.dart';

/// One thing the search can find and open.
class SearchHit {
  const SearchHit(this.title, this.subtitle, this.icon, this.open);
  final String title, subtitle;
  final IconData icon;
  final void Function(BuildContext context) open;
}

/// Search across the whole app, like a phone's search: sections and
/// features, settings, operations, accounts, categories, dreams, payments,
/// budgets and shopping items. Opened from the side panel's magnifier.
class AppSearchScreen extends StatefulWidget {
  const AppSearchScreen({super.key, required this.onPlace});

  /// Switches the main screen's tab (0 home, 1 operations, 3 analytics,
  /// 4 more, 5 Finora AI).
  final ValueChanged<int> onPlace;

  /// Matching ignores case and «ё».
  static bool matches(String text, String query) =>
      _fold(text).contains(_fold(query));

  static String _fold(String s) => s.toLowerCase().replaceAll('ё', 'е').trim();

  @override
  State<AppSearchScreen> createState() => _AppSearchScreenState();
}

class _AppSearchScreenState extends State<AppSearchScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  /// Sections, features and settings: fixed, with words they answer to.
  List<(SearchHit, String)> _places() {
    void place(BuildContext context, int tab) {
      Navigator.pop(context);
      widget.onPlace(tab);
    }

    SearchHit page(String t, String s, IconData i, Widget Function() p) =>
        SearchHit(t, s, i, (c) => _push(c, p()));
    const settings = 'Настройки';
    return [
      (
        SearchHit(
          'Главная',
          'Раздел',
          CupertinoIcons.house,
          (c) => place(c, 0),
        ),
        'дом баланс счета обзор',
      ),
      (
        SearchHit(
          'Операции',
          'Раздел',
          CupertinoIcons.doc_text,
          (c) => place(c, 1),
        ),
        'расходы доходы переводы история',
      ),
      (
        SearchHit(
          'Аналитика',
          'Раздел',
          CupertinoIcons.chart_bar,
          (c) => place(c, 3),
        ),
        'статистика диаграмма категории отчёт',
      ),
      (
        SearchHit(
          'Finora AI',
          'Раздел',
          CupertinoIcons.sparkles,
          (c) => place(c, 5),
        ),
        'ассистент чат прогноз вопрос ии ai',
      ),
      (
        SearchHit(
          'Ещё',
          'Раздел',
          CupertinoIcons.ellipsis_circle,
          (c) => place(c, 4),
        ),
        'прочее меню',
      ),
      (
        page(
          'Список покупок',
          'Функции',
          CupertinoIcons.cart,
          () => const ShoppingScreen(),
        ),
        'покупки продукты магазин',
      ),
      (
        page(
          'Платежи и подписки',
          'Функции',
          CupertinoIcons.arrow_2_circlepath,
          () => const RecurringScreen(),
        ),
        'кредит ипотека аренда подписка регулярные обязательные',
      ),
      (
        page(
          'Календарь',
          'Функции',
          CupertinoIcons.calendar,
          () => const CalendarScreen(),
        ),
        'даты платежей',
      ),
      (
        page(
          'Бюджеты',
          'Функции',
          CupertinoIcons.chart_pie,
          () => const BudgetsScreen(),
        ),
        'лимит',
      ),
      (
        page(
          'Мечты',
          'Функции',
          CupertinoIcons.star,
          () => const GoalsScreen(),
        ),
        'цели накопления копилка',
      ),
      (
        page(
          'Достижения',
          'Функции',
          CupertinoIcons.rosette,
          () => const AchievementsScreen(),
        ),
        'награды серии',
      ),
      (
        page(
          'Счета',
          'Функции',
          CupertinoIcons.creditcard,
          () => const AccountsScreen(),
        ),
        'карты кошелёк наличные вклад',
      ),
      (
        page(
          'Категории',
          'Функции',
          CupertinoIcons.tag,
          () => const CategoriesScreen(),
        ),
        'подкатегории',
      ),
      (
        page(
          'Семья',
          'Функции',
          CupertinoIcons.person_2,
          () => const MembersScreen(),
        ),
        'участники члены семьи',
      ),
      (
        page(
          'Настройки',
          settings,
          CupertinoIcons.gear,
          () => const SettingsScreen(),
        ),
        'параметры',
      ),
      for (final (title, words) in const [
        ('Внешний вид и темы', 'тема тёмная светлая цвет оформление'),
        ('Язык', 'english language'),
        ('Валюта и форматы', 'рубли формат чисел дата начало месяца недели'),
        ('Уведомления', 'напоминания push'),
        ('Защита и PIN', 'пароль блокировка отпечаток биометрия код'),
        (
          'Резервные копии',
          'бэкап сохранить восстановить экспорт импорт csv json',
        ),
        ('Вибрация', 'тактильный отклик haptic'),
        ('Отзываться на «Финора»', 'голос wake word'),
        ('Сбросить все данные', 'удалить очистить'),
        ('Короткое обучение', 'тур помощь'),
      ])
        (
          page(
            title,
            settings,
            CupertinoIcons.gear,
            () => const SettingsScreen(),
          ),
          words,
        ),
      (
        page(
          'Голосовые команды',
          settings,
          CupertinoIcons.mic,
          () => const VoiceHelpScreen(),
        ),
        'голос сказать финоре',
      ),
      (
        page(
          'Что умеет Finora AI',
          settings,
          CupertinoIcons.sparkles,
          () => const AiHelpScreen(),
        ),
        'возможности вопросы',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final q = _query.text.trim();
    bool hit(String s) => AppSearchScreen.matches(s, q);
    final places = q.isEmpty
        ? [for (final (h, _) in _places().take(5)) h]
        : [
            for (final (h, words) in _places())
              if (hit(h.title) || hit(words)) h,
          ];
    final entries = q.length < 2
        ? const <FinanceEntry>[]
        : (c.data.entries
                  .where(
                    (e) =>
                        hit(e.payee) ||
                        hit(e.note) ||
                        hit(c.category(e.categoryId)?.name ?? '') ||
                        e.tags.any(hit),
                  )
                  .toList()
                ..sort((a, b) => b.date.compareTo(a.date)))
              .take(30)
              .toList();
    final things = q.length < 2
        ? const <SearchHit>[]
        : [
            for (final a in c.data.accounts.where((a) => hit(a.name)))
              SearchHit(
                a.name,
                'Счёт · ${money(FinanceEngine.balance(a, c.data.entries), a.currency)}',
                CupertinoIcons.creditcard,
                (ctx) => _push(ctx, TransactionsScreen(accountId: a.id)),
              ),
            for (final k in c.data.categories.where(
              (k) => !k.archived && hit(k.name),
            ))
              SearchHit(
                k.name,
                k.kind == EntryKind.income ? 'Категория дохода' : 'Категория',
                CupertinoIcons.tag,
                (ctx) => _push(ctx, TransactionsScreen(categoryId: k.id)),
              ),
            for (final g in c.data.goals.where((g) => hit(g.name)))
              SearchHit(
                g.name,
                'Мечта · ${money(g.targetMinor, g.currency)}',
                CupertinoIcons.star,
                (ctx) => _push(ctx, const GoalsScreen()),
              ),
            for (final r in c.data.recurring.where((r) => hit(r.name)))
              SearchHit(
                r.name,
                '${r.paymentType == 'subscription' ? 'Подписка' : 'Платёж'} · '
                '${money(r.amountMinor, r.currency)}',
                CupertinoIcons.arrow_2_circlepath,
                (ctx) => r.totalMinor != null || r.isLoan
                    ? openPaymentPlan(ctx, r.id)
                    : showRecurringEditor(ctx, rule: r),
              ),
            for (final b in c.data.budgets.where((b) => hit(b.name)))
              SearchHit(
                b.name,
                'Бюджет · ${money(b.limitMinor, b.currency)}',
                CupertinoIcons.chart_pie,
                (ctx) => _push(ctx, const BudgetsScreen()),
              ),
            for (final s in c.data.shopping.where((s) => hit(s.name)))
              SearchHit(
                s.name,
                s.done ? 'Куплено' : 'В списке покупок',
                CupertinoIcons.cart,
                (ctx) => _push(ctx, const ShoppingScreen()),
              ),
          ];
    final scheme = Theme.of(context).colorScheme;
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
      child: Text(
        t.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: .6,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    Widget row(SearchHit h, int i) => ListTile(
      key: ValueKey('search-hit-${h.title}'),
      leading: Icon(h.icon, color: scheme.primary),
      title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        h.subtitle,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      onTap: () => h.open(context),
    );
    final nothing =
        q.isNotEmpty && places.isEmpty && entries.isEmpty && things.isEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            key: const ValueKey('app-search-field'),
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: searchDecoration(
              context,
              'Поиск по Finora',
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Очистить',
                      onPressed: () => setState(_query.clear),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
        ),
      ),
      body: nothing
          ? const EmptyState(
              'Ничего не нашлось',
              'Попробуйте другое слово: магазин, категорию, счёт или '
                  'название настройки.',
              icon: Icons.search_off_rounded,
            )
          : ListView(
              key: const ValueKey('app-search-results'),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (places.isNotEmpty) ...[
                  header(q.isEmpty ? 'Разделы' : 'Разделы и настройки'),
                  for (var i = 0; i < places.length; i++) row(places[i], i),
                ],
                if (things.isNotEmpty) ...[
                  header('В ваших данных'),
                  for (var i = 0; i < things.length; i++) row(things[i], i),
                ],
                if (entries.isNotEmpty) ...[
                  header('Операции'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (final e in entries)
                          EntryTile(e, showDate: true, swipe: false),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
