import 'package:flutter/material.dart';

import '../../../domain/voice_command_parser.dart';
import '../../../presentation/controller.dart';
import '../../../presentation/screens/analytics.dart';
import '../../../presentation/screens/dashboard.dart';
import '../../../presentation/screens/entry_editor.dart';
import '../../../presentation/screens/transactions.dart';
import '../../../presentation/voice_commands.dart';
import '../../../presentation/widgets/grouped_list.dart' show confirmWithFinora;
import 'ai_actions.dart';
import '../services/assistant_scenarios.dart';
import '../services/finora_ai.dart';
import '../ui/debt_planning_screen.dart';
import '../ui/assistant_memory_screen.dart';
import '../ui/scenario_run_screen.dart';

extension AiActionExecution on AiActionSession {
  /// The model cannot call this function. The chat exposes it as an explicit
  /// user button, followed by a confirmation bound to [action.summary].
  Future<String> run(
    BuildContext context,
    AiPendingAction action, {
    required void Function(int tab)? onTab,
    Future<void> Function()? onConsumed,
    bool Function()? isCurrent,
  }) async {
    final c = FinanceScope.of(context);
    if (!beginConfirmation(action, c.data)) {
      return 'Подтверждение уже открыто или команда устарела.';
    }
    try {
      final approved = await confirmWithFinora(
        context,
        title: 'Подтвердите действие',
        message: action.summary,
        action: action.entry == null ? 'Выполнить' : 'Открыть форму',
      );
      if (!approved || !context.mounted) {
        cancel();
        return 'Действие отменено. Ничего не изменено.';
      }
      if (!consume(action, c.data)) {
        return 'Данные или команда изменились во время подтверждения. Повторите запрос.';
      }
      if (onConsumed != null) await onConsumed();
      if (!context.mounted || isCurrent != null && !isCurrent()) {
        return 'Действие отменено до запуска.';
      }
      if (action.kind == AiActionKind.reviewWeek) {
        return AssistantScenarios.summary(
          c.data,
          period: 'week',
          format: FinoraAi.instance.memory.preferences.reportFormat,
        );
      }
      if (action.kind == AiActionKind.planDebts) {
        final p = action.arguments;
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => DebtPlanningScreen(
              initialSourceAccountId: p['accountId'] as String?,
              initialBudgetMinor: p['budgetMinor'] as int?,
              initialReserveMinor: p['reserveMinor'] as int?,
              initialHorizonDays: p['horizonDays'] as int?,
            ),
          ),
        );
        return saved == true
            ? 'План сохранён в календарь как ожидаемые выплаты. Фактические баланс и долг не изменены.'
            : 'Планировщик закрыт. Новые выплаты не сохранялись автоматически.';
      }
      if (action.kind == AiActionKind.assistantMemory) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => AssistantMemoryScreen(
              onRun: (scenario) async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ScenarioRunScreen(scenario: scenario),
                  ),
                );
              },
            ),
          ),
        );
        return 'Предпочтения и сценарии доступны в настройках ассистента.';
      }
      final draft = action.entry;
      if (draft != null) {
        final entry = draft.id.isEmpty
            ? draft.copyWith(id: 'assistant:${action.draftId}')
            : draft;
        if (draft.id.isEmpty && c.data.entries.any((e) => e.id == entry.id)) {
          return 'Эта операция уже сохранена. Повторная запись не создана.';
        }
        final before = c.data.entries
            .where((e) => e.id == entry.id)
            .firstOrNull;
        await showEntryEditor(context, entry: entry, kind: entry.kind);
        final after = c.data.entries.where((e) => e.id == entry.id).firstOrNull;
        if (after == null || identical(before, after)) {
          return 'Форма закрыта без сохранения изменений.';
        }
        return before == null
            ? 'Операция сохранена в приложении.'
            : 'Изменения операции сохранены в приложении.';
      }
      final command = action.command;
      if (command == null) return 'Команда недоступна. Ничего не изменено.';
      // Chats opened from Settings/Help have no shell tab callback. Reuse the
      // actual financial screens on their existing Navigator, rather than a
      // no-op callback that would falsely report successful navigation.
      if (onTab == null && command is OpenScreenCommand) {
        Widget? page;
        switch (command.screen) {
          case VoiceScreen.home:
            void open(Widget screen) => Navigator.of(
              context,
            ).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
            page = Scaffold(
              appBar: AppBar(title: const Text('Главная')),
              body: SafeArea(
                child: Dashboard(
                  onTransactions: () => open(const TransactionsScreen()),
                  onAnalytics: () => open(const AnalyticsScreen()),
                ),
              ),
            );
          case VoiceScreen.operations:
            page = const TransactionsScreen();
          case VoiceScreen.analytics:
            page = const AnalyticsScreen();
          default:
            break;
        }
        if (page != null) {
          final screen = page;
          await Navigator.of(
            context,
          ).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
          return 'Раздел открыт.';
        }
      }
      await VoiceCommands.run(
        context,
        command,
        onTab:
            onTab ??
            (_) => throw StateError('У раздела нет обработчика навигации.'),
      );
      return action.kind == AiActionKind.setTheme
          ? 'Тема изменена в настройках.'
          : 'Раздел открыт.';
    } finally {
      endConfirmation();
    }
  }
}
