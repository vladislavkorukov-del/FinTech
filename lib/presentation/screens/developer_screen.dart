import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../domain/app_version.dart';
import '../../domain/models.dart';
import '../../domain/monetization.dart';
import '../../features/finora_ai/memory/personal_memory.dart';
import '../../features/finora_ai/services/finora_ai.dart';
import '../../features/finora_ai/ui/local_model_diagnostics_screen.dart';
import '../controller.dart';
import '../haptics.dart';
import '../l10n_widgets.dart';
import '../widgets/grouped_list.dart';

/// The store the app asks about purchases. Only [NoPurchaseProvider] exists
/// today: nothing is sold, nothing is charged.
PurchaseProvider purchases = const NoPurchaseProvider();

/// Whether [featureId] may be used; otherwise shows the Finora Plus sheet
/// and returns false.
Future<bool> ensureFeature(BuildContext context, String featureId) async {
  final c = FinanceScope.of(context);
  if (Entitlements.allows(c.data.preferences.developer, featureId)) {
    return true;
  }
  await showPaywall(context, featureId);
  return context.mounted &&
      Entitlements.allows(
        FinanceScope.of(context).data.preferences.developer,
        featureId,
      );
}

/// The Finora Plus sheet for a locked feature. Payment is not connected
/// yet: the sheet says so; in developer mode it can switch test Plus on.
Future<void> showPaywall(BuildContext context, String featureId) {
  final feature = PaidFeature.byId(featureId);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final c = FinanceScope.of(sheet);
      final dev = c.data.preferences.developer;
      final scheme = Theme.of(sheet).colorScheme;
      return SafeArea(
        child: Padding(
          key: const ValueKey('paywall'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                size: 44,
                color: scheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'Finora Plus',
                textAlign: TextAlign.center,
                style: Theme.of(sheet).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                feature == null
                    ? 'Эта функция входит в Finora Plus.'
                    : '«${feature.title}» входит в Finora Plus. ${feature.description}.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('paywall-buy'),
                onPressed: () async {
                  final result = await purchases.buy('finora_plus');
                  if (!sheet.mounted) return;
                  final text = switch (result) {
                    PurchaseUnavailable(:final reason) =>
                      '$reason Функция станет доступна позже.',
                    PurchaseDone() => 'Готово',
                  };
                  ScaffoldMessenger.of(
                    sheet,
                  ).showSnackBar(SnackBar(content: Text(text)));
                },
                child: const Text('Оформить Plus'),
              ),
              if (dev.enabled) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('paywall-test-plus'),
                  onPressed: () async {
                    await c.preferences(
                      c.data.preferences.copyWith(
                        developer: dev.copyWith(simulatedPlus: true),
                      ),
                    );
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                  child: const Text('Включить Plus для теста'),
                ),
              ],
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Не сейчас'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Shows [child] when [featureId] is allowed, otherwise a locked page with
/// the Finora Plus offer. Put inside a paid screen, so every way into it is
/// covered.
class FeatureGate extends StatelessWidget {
  const FeatureGate({super.key, required this.featureId, required this.child});
  final String featureId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    if (Entitlements.allows(c.data.preferences.developer, featureId)) {
      return child;
    }
    final feature = PaidFeature.byId(featureId);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: ValueKey('feature-locked-$featureId'),
      appBar: AppBar(title: Text(feature?.title ?? 'Finora Plus')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 48, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                'Входит в Finora Plus',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(feature?.description ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(
                key: const ValueKey('feature-locked-more'),
                onPressed: () => showPaywall(context, featureId),
                child: const Text('Подробнее'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Developer mode: the paid-features switches, diagnostics and facts about
/// the build and the data. Opened by three long presses on the version in
/// «О приложении»; nothing here touches the person's operations.
class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final p = c.data.preferences;
    final dev = p.developer;
    Future<void> save(DeveloperSettings value) =>
        c.preferences(c.data.preferences.copyWith(developer: value));
    final memory = FinoraAi.instance.memory;
    return Scaffold(
      appBar: AppBar(title: const Text('Режим разработчика')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          GroupedSection(
            title: 'Платные функции',
            footer:
                'Готовая система для будущей подписки Finora Plus. Пока '
                'оплата не подключена: включённая проверка закрывает отмеченные '
                'функции экраном Plus. Выключите проверку — всё снова бесплатно.',
            children: [
              GroupedRow(
                key: const ValueKey('dev-enforce'),
                icon: Icons.shield_moon_outlined,
                color: TileColors.orange,
                title: 'Проверять подписку',
                subtitle: dev.enforcePaywall
                    ? 'Отмеченные функции закрыты без Plus'
                    : 'Выключено — всё бесплатно',
                trailing: Switch.adaptive(
                  value: dev.enforcePaywall,
                  onChanged: (v) => save(dev.copyWith(enforcePaywall: v)),
                ),
                onTap: () =>
                    save(dev.copyWith(enforcePaywall: !dev.enforcePaywall)),
              ),
              GroupedRow(
                key: const ValueKey('dev-simulated-plus'),
                icon: Icons.workspace_premium_outlined,
                color: TileColors.purple,
                title: 'Тестовый Plus',
                subtitle: 'Как будто подписка куплена',
                trailing: Switch.adaptive(
                  value: dev.simulatedPlus,
                  onChanged: (v) => save(dev.copyWith(simulatedPlus: v)),
                ),
                onTap: () =>
                    save(dev.copyWith(simulatedPlus: !dev.simulatedPlus)),
              ),
            ],
          ),
          GroupedSection(
            title: 'Что сделать платным',
            children: [
              for (final f in PaidFeature.catalog)
                GroupedRow(
                  key: ValueKey('dev-paid-${f.id}'),
                  icon: dev.paidFeatures.contains(f.id)
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  color: dev.paidFeatures.contains(f.id)
                      ? TileColors.orange
                      : TileColors.gray,
                  title: f.title,
                  subtitle: f.description,
                  trailing: Switch.adaptive(
                    value: dev.paidFeatures.contains(f.id),
                    onChanged: (v) => save(
                      dev.copyWith(
                        paidFeatures: v
                            ? {...dev.paidFeatures, f.id}
                            : ({...dev.paidFeatures}..remove(f.id)),
                      ),
                    ),
                  ),
                  onTap: () => showPaywall(context, f.id),
                ),
            ],
          ),
          GroupedSection(
            title: 'Диагностика',
            children: [
              GroupedRow(
                key: const ValueKey('dev-local-model'),
                icon: Icons.memory_rounded,
                color: TileColors.indigo,
                title: 'Локальная модель',
                subtitle: 'Журнал и проверки Qwen',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const LocalModelDiagnosticsScreen(),
                  ),
                ),
              ),
            ],
          ),
          GroupedSection(
            title: 'Сборка и данные',
            children: [
              _fact('Версия', appVersion),
              _fact('Операций', '${c.data.entries.length}'),
              _fact(
                'Счетов / категорий',
                '${c.data.accounts.length} / ${c.data.categories.length}',
              ),
              _fact('Платежей и долгов', '${c.data.recurring.length}'),
              _fact(
                'Память AI',
                'схема ${PersonalMemory.version} · '
                    '${memory.merchants.length} мест · '
                    '${memory.aliases.length} сокращений',
              ),
              _fact(
                'Классификатор',
                FinoraAi.instance.model == null
                    ? 'не загружен'
                    : '${FinoraAi.instance.model!.version} · признаки '
                          '${FinoraAi.instance.model!.preprocessingVersion}',
              ),
            ],
          ),
          GroupedSection(
            children: [
              GroupedRow(
                key: const ValueKey('dev-off'),
                icon: Icons.logout_rounded,
                color: TileColors.red,
                title: 'Выключить режим разработчика',
                destructive: true,
                onTap: () async {
                  // Leaving developer mode keeps the paywall choices but
                  // drops the test subscription.
                  await save(
                    dev.copyWith(enabled: false, simulatedPlus: false),
                  );
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _fact(String title, String value) => GroupedRow(
    icon: Icons.info_outline_rounded,
    color: TileColors.gray,
    title: title,
    value: value,
  );
}

/// Developer mode on (or the screen opened again) after three long presses
/// on the version.
Future<void> openDeveloperMode(BuildContext context) async {
  final c = FinanceScope.of(context);
  final dev = c.data.preferences.developer;
  if (!dev.enabled) {
    await c.preferences(
      c.data.preferences.copyWith(developer: dev.copyWith(enabled: true)),
    );
    Haptics.success();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Режим разработчика включён')));
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const DeveloperScreen()),
  );
}

/// The developer-mode flag.
extension DeveloperFlag on AppPreferences {
  bool get developerMode => developer.enabled;
}
