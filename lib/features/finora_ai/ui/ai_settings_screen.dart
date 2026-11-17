import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/models.dart';
import '../../../presentation/controller.dart';
import '../../../presentation/haptics.dart';
import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/grouped_list.dart';
import '../services/finora_ai.dart';

/// Settings → «Настройки Finora AI»: what she may do by herself. Everything
/// stays on the phone; these switches only decide how much Finora fills in
/// on her own and whether she learns. Resetting her personalization asks
/// first and never touches the operations.
class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({super.key});

  static const levels = {
    AiAutomation.suggestOnly: (
      'Только предлагать',
      'Ничего не заполняет без вашего нажатия',
    ),
    AiAutomation.smart: (
      'Умно',
      'Заполняет то, в чём уверена, остальное предлагает',
    ),
    AiAutomation.automatic: (
      'Автоматически',
      'Заполняет всё, в чём достаточно уверена',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final ai = c.data.preferences.ai;
    Future<void> set(AiSettings next) => c.mutate(
      (d) => d.copyWith(preferences: d.preferences.copyWith(ai: next)),
    );
    Widget toggle(
      String key,
      IconData icon,
      Color color,
      String title,
      String subtitle,
      bool value,
      AiSettings Function(bool) apply, {
      bool enabled = true,
    }) => GroupedRow(
      key: ValueKey('ai-setting-$key'),
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(
        value: value,
        onChanged: enabled ? (v) => set(apply(v)) : null,
      ),
    );
    final on = ai.enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки Finora AI')),
      body: ListView(
        key: const ValueKey('ai-settings'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          GroupedSection(
            footer:
                'Всё считается на телефоне, без интернета. Данные никуда не '
                'отправляются.',
            children: [
              toggle(
                'enabled',
                Icons.auto_awesome_outlined,
                TileColors.orange,
                'Finora AI',
                'Подсказки и автоматические действия',
                ai.enabled,
                (v) => ai.copyWith(enabled: v),
              ),
            ],
          ),
          GroupedSection(
            title: 'Категории',
            children: [
              toggle(
                'auto',
                Icons.category_outlined,
                TileColors.green,
                'Автоматическая категоризация',
                'Сама выбирает категорию по магазину',
                ai.autoCategorize,
                (v) => ai.copyWith(autoCategorize: v),
                enabled: on,
              ),
              toggle(
                'suggest',
                Icons.lightbulb_outline_rounded,
                TileColors.teal,
                'Предлагать категории',
                'Три варианта, когда не уверена',
                ai.suggestCategories,
                (v) => ai.copyWith(suggestCategories: v),
                enabled: on,
              ),
            ],
          ),
          GroupedSection(
            title: 'Уровень автоматизации',
            footer:
                'Удаление и другие рискованные действия всегда требуют '
                'вашего подтверждения.',
            children: [
              for (final e in levels.entries)
                GroupedRow(
                  key: ValueKey('ai-level-${e.key.name}'),
                  icon: e.key == ai.automation
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: TileColors.indigo,
                  title: e.value.$1,
                  subtitle: e.value.$2,
                  onTap: on
                      ? () {
                          Haptics.light();
                          set(ai.copyWith(automation: e.key));
                        }
                      : null,
                ),
            ],
          ),
          GroupedSection(
            title: 'Обучение и подсказки',
            children: [
              toggle(
                'personalization',
                Icons.school_outlined,
                TileColors.purple,
                'Персонализация',
                'Учится на ваших выборах и исправлениях',
                ai.personalization,
                (v) => ai.copyWith(personalization: v),
                enabled: on,
              ),
              toggle(
                'insights',
                Icons.visibility_outlined,
                TileColors.blue,
                'Умные наблюдения',
                '«Что я заметила» в окне Finora AI',
                ai.insights,
                (v) => ai.copyWith(insights: v),
                enabled: on,
              ),
            ],
          ),
          GroupedSection(
            footer:
                'Финора забудет, чему научилась: выборы категорий по '
                'магазинам, исправления и ответы на подсказки. Операции '
                'останутся.',
            children: [
              GroupedRow(
                key: const ValueKey('ai-reset'),
                icon: Icons.restart_alt_rounded,
                color: TileColors.red,
                title: 'Сбросить персонализацию Finora',
                onTap: () async {
                  final sure = await confirmWithFinora(
                    context,
                    title: 'Сбросить персонализацию?',
                    message:
                        'Финора забудет выборы категорий, исправления и '
                        'ответы на подсказки. Ваши операции не изменятся.',
                    action: 'Сбросить',
                    destructive: true,
                  );
                  if (!sure) return;
                  await FinoraAi.instance.resetPersonalization();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Персонализация сброшена')),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
