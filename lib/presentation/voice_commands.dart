import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/voice_command_parser.dart';
import 'widgets/common.dart';
import 'controller.dart';
import 'screens/account_import_screen.dart';
import 'screens/management.dart';
import 'screens/settings.dart';
import 'screens/transactions.dart';
import 'theme/app_theme.dart';

/// Carries out a spoken command (Finance 1.23). [onTab] switches the main
/// screen's tab: 0 home, 1 operations, 3 analytics, 4 more.
abstract final class VoiceCommands {
  static const prompt =
      'Финора слушает: «Пятёрочка 450», «покажи расходы '
      'за июнь», «хочу машину за 2 млн», «поменяй тему на зелёную»';

  static Future<void> run(
    BuildContext context,
    VoiceCommand command, {
    required void Function(int tab) onTab,
  }) async {
    final c = FinanceScope.of(context);
    void say(String text) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    Future<void> push(Widget screen) => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );

    switch (command) {
      case ThemeCommand():
        final prefs = c.data.preferences;
        final accent = command.mode != null && !command.hasColor
            ? prefs.accent
            : pickAccent(command, prefs.accent);
        final mode = command.mode ?? prefs.theme;
        await c.preferences(prefs.copyWith(theme: mode, accent: accent));
        if (!context.mounted) return;
        final modeName = switch (mode) {
          'light' => 'светлая',
          'system' => 'как в системе',
          _ => 'тёмная',
        };
        final name = AppTheme.presetNames[accent] ?? accent;
        say('Тема: $name, $modeName.');
      case ShowEntriesCommand():
        await push(
          TransactionsScreen(
            initialKind: command.kind,
            categoryId: command.categoryId,
            accountId: command.accountId,
            initialRange: command.start == null
                ? null
                : DateTimeRange(start: command.start!, end: command.end!),
            title: command.title,
          ),
        );
      case OpenScreenCommand():
        switch (command.screen) {
          case VoiceScreen.home:
            onTab(0);
          case VoiceScreen.operations:
            onTab(1);
          case VoiceScreen.analytics:
            onTab(3);
          case VoiceScreen.more:
            onTab(4);
          case VoiceScreen.settings:
            await push(const SettingsScreen());
          case VoiceScreen.accounts:
            await push(const AccountsScreen());
          case VoiceScreen.goals:
            await push(const GoalsScreen());
          case VoiceScreen.budgets:
            await push(const BudgetsScreen());
          case VoiceScreen.calendar:
            await push(const CalendarScreen());
          case VoiceScreen.categories:
            await push(const CategoriesScreen());
          case VoiceScreen.members:
            await push(const MembersScreen());
          case VoiceScreen.recurring:
            await push(const RecurringScreen());
          case VoiceScreen.importAccounts:
            await push(const AccountImportScreen());
        }
      case CreateGoalCommand():
        final target = command.targetMinor;
        if (target == null || target <= 0) {
          say(
            'Сколько стоит «${command.name}»? Скажите, например: «хочу '
            'машину за 2 миллиона».',
          );
          return;
        }
        final goal = Goal(
          id: c.id(),
          name: command.name,
          currency: c.currency,
          targetMinor: target,
          deadline: command.deadline,
          color: categoryColors[c.data.goals.length % categoryColors.length],
        );
        await c.mutate((d) => d.copyWith(goals: [...d.goals, goal]));
        if (!context.mounted) return;
        added(
          context,
          'Мечта «${goal.name}» на ${money(target, goal.currency)} добавлена.',
          () => c.mutate(
            (d) => d.copyWith(
              goals: d.goals.where((g) => g.id != goal.id).toList(),
            ),
          ),
        );
        await push(const GoalsScreen());
      case CreateAccountCommand():
        final account = Account(
          id: c.id(),
          name: command.name,
          type: command.type,
          currency: c.currency,
          bank: command.bank,
          openingMinor: command.openingMinor,
          color: categoryColors[c.data.accounts.length % categoryColors.length],
        );
        await c.saveAccount(account);
        if (!context.mounted) return;
        added(
          context,
          'Счёт «${account.name}» добавлен, остаток '
          '${money(account.openingMinor, account.currency)}.',
          () => c.deleteAccount(account.id),
        );
        await push(const AccountsScreen());
      case CreateBudgetCommand():
        final existing = c.data.budgets
            .where((b) => b.categoryId == command.categoryId)
            .firstOrNull;
        final budget = Budget(
          id: existing?.id ?? c.id(),
          name: existing?.name ?? command.name,
          currency: c.currency,
          categoryId: command.categoryId,
          limitMinor: command.limitMinor,
        );
        await c.saveBudget(budget);
        if (!context.mounted) return;
        added(
          context,
          '${existing == null ? 'Бюджет' : 'Новый лимит'} «${budget.name}»: '
          '${money(budget.limitMinor, budget.currency)} в месяц.',
          () => existing == null
              ? c.mutate(
                  (d) => d.copyWith(
                    budgets: d.budgets.where((b) => b.id != budget.id).toList(),
                  ),
                )
              : c.saveBudget(existing),
        );
        await push(const BudgetsScreen());
      case CreateCategoryCommand():
        final kind = command.kind ?? EntryKind.expense;
        final same = c.data.categories.where(
          (x) =>
              x.kind == kind &&
              x.name.toLowerCase() == command.name.toLowerCase(),
        );
        if (same.isNotEmpty) {
          say('Категория «${command.name}» уже есть.');
          return;
        }
        final color =
            categoryColors[c.data.categories.length % categoryColors.length];
        final category = Category(
          id: c.id(),
          name: command.name,
          kind: kind,
          color: color,
          background: Color.alphaBlend(
            Color(color).withValues(alpha: .16),
            Theme.of(context).colorScheme.surface,
          ).toARGB32(),
          order: c.data.categories.where((x) => x.kind == kind).length,
        );
        await c.saveCategory(category);
        if (!context.mounted) return;
        added(
          context,
          'Категория ${kind == EntryKind.income ? 'доходов' : 'расходов'} '
          '«${category.name}» добавлена.',
          () => c.deleteCategory(category.id),
        );
        await push(const CategoriesScreen());
      case CreateRecurringCommand():
        final amount = command.amountMinor;
        if (amount == null || amount <= 0) {
          say(
            'Сколько стоит «${command.name}»? Скажите, например: «подписка '
            'Яндекс Плюс 399 в месяц».',
          );
          return;
        }
        final active = c.data.accounts.where((a) => !a.archived).toList();
        if (active.isEmpty) {
          say('Сначала добавьте счёт: «добавь карту Сбер».');
          return;
        }
        final account =
            active.where((a) => a.id == command.accountId).firstOrNull ??
            active.first;
        final category =
            command.categoryId ??
            c.data.categories
                .where((x) => !x.archived && x.kind == command.kind)
                .firstOrNull
                ?.id;
        if (category == null) {
          say('Сначала создайте категорию для этого типа операции.');
          return;
        }
        final rule = RecurringRule(
          id: c.id(),
          name: command.name,
          accountId: account.id,
          currency: account.currency,
          categoryId: category,
          serviceId: command.serviceId,
          kind: command.kind,
          amountMinor: amount,
          frequency: command.frequency,
          paymentType: command.paymentType,
          nextDate: command.nextDate,
        );
        await c.saveRecurring(rule);
        if (!context.mounted) return;
        final when = switch (command.frequency) {
          'daily' => 'в день',
          'weekly' => 'в неделю',
          'yearly' => 'в год',
          _ => 'в месяц',
        };
        added(
          context,
          '«${rule.name}»: ${money(amount, rule.currency)} $when, следующий '
          'платёж ${_date(rule.nextDate)}.',
          () => c.mutate(
            (d) => d.copyWith(
              recurring: d.recurring.where((r) => r.id != rule.id).toList(),
            ),
          ),
        );
        await push(const RecurringScreen());
      case UnknownCommand():
        say(
          'Не понял «${command.heard}». Скажите, например: «покажи расходы '
          'за июнь», «открой настройки», «сделай тему синей».',
        );
    }
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  /// Confirms what was added by voice, with a way to take it back.
  static void added(
    BuildContext context,
    String text,
    Future<void> Function() undo,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('voice-added'),
          content: Text(text),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () => undo().catchError((Object _) {}),
          ),
        ),
      );
  }

  /// The theme whose accent is closest to the color asked for. When the
  /// current theme already fits, the next fitting shade is taken, so
  /// «зелёную» always changes something.
  static String pickAccent(ThemeCommand command, String current) {
    final preset = command.preset;
    if (preset != null && AppTheme.presetNames.containsKey(preset)) {
      return preset;
    }
    final ids = AppTheme.presetNames.keys.toList();
    if (command.anyOther) {
      return ids[(ids.indexOf(current) + 1) % ids.length];
    }
    double score(String id) {
      final hsv = HSVColor.fromColor(AppTheme.accent(id));
      if (command.gray) return hsv.saturation * 100;
      final d = (hsv.hue - command.hue!).abs() % 360;
      final distance = d > 180 ? 360 - d : d;
      // A nearly gray accent does not read as a color.
      return distance + (hsv.saturation < .15 ? 60 : 0);
    }

    final ranked = [...ids]..sort((a, b) => score(a).compareTo(score(b)));
    final limit = command.gray ? 20.0 : 35.0;
    final fitting = ranked.where((id) => score(id) <= limit).toList();
    if (fitting.isEmpty) return ranked.first;
    // The closest shade, or the next closest when that one is on already.
    return fitting.first == current && fitting.length > 1
        ? fitting[1]
        : fitting.first;
  }
}
