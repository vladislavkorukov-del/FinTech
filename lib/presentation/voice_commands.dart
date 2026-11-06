import 'package:flutter/material.dart';

import '../domain/voice_command_parser.dart';
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
      'Скажите операцию или команду: «Пятёрочка 450», «покажи расходы '
      'за июнь», «поменяй тему на зелёную»';

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
      case UnknownCommand():
        say(
          'Не понял «${command.heard}». Скажите, например: «покажи расходы '
          'за июнь», «открой настройки», «сделай тему синей».',
        );
    }
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
