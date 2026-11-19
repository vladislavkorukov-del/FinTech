/// Paid features, prepared for later (nothing is sold yet).
///
/// - [PaidFeature.catalog] lists the features that *can* be made paid; each
///   has a gate in the app ([Entitlements.allows]).
/// - Which of them are paid, and whether the paywall is enforced at all, is
///   decided in developer mode ([DeveloperSettings]) and saved with the
///   preferences. Out of the box nothing is enforced, so every feature
///   stays free and nothing changes for the person.
/// - [PurchaseProvider] is the seam for a real store (Google Play Billing)
///   later; today only [NoPurchaseProvider] exists, which never charges.
///   No payment SDK, server or network call is in the app.
library;

/// A feature that can be put behind Finora Plus.
class PaidFeature {
  const PaidFeature(this.id, this.title, this.description);
  final String id, title, description;

  static const batchEntries = 'batch_entries';
  static const scanImport = 'scan_import';
  static const debtPlanner = 'debt_planner';
  static const localAi = 'local_ai';
  static const shopping = 'shopping';
  static const budgets = 'budgets';

  static const catalog = [
    PaidFeature(
      batchEntries,
      'Несколько операций',
      'Добавление списком и несколькими строками',
    ),
    PaidFeature(
      scanImport,
      'Скриншоты из банка',
      'Распознавание операций с изображения',
    ),
    PaidFeature(
      debtPlanner,
      'План погашения долгов',
      'Стратегии, график и прогноз закрытия',
    ),
    PaidFeature(localAi, 'Локальная модель Qwen', 'Свободный диалог офлайн'),
    PaidFeature(shopping, 'Список покупок', 'Списки, история и подсказки'),
    PaidFeature(budgets, 'Бюджеты', 'Лимиты по категориям и прогноз'),
  ];

  static PaidFeature? byId(String id) =>
      catalog.where((f) => f.id == id).firstOrNull;
}

/// Developer mode and the paywall switches (saved in the preferences).
class DeveloperSettings {
  const DeveloperSettings({
    this.enabled = false,
    this.enforcePaywall = false,
    this.paidFeatures = const {},
    this.simulatedPlus = false,
  });

  /// Developer mode is on (opened by three long presses on the version).
  final bool enabled;

  /// The paywall is checked at all. Off — every feature is free.
  final bool enforcePaywall;

  /// Features marked as paid (ids from [PaidFeature.catalog]).
  final Set<String> paidFeatures;

  /// Pretend Finora Plus is bought (to try the app as a subscriber).
  final bool simulatedPlus;

  DeveloperSettings copyWith({
    bool? enabled,
    bool? enforcePaywall,
    Set<String>? paidFeatures,
    bool? simulatedPlus,
  }) => DeveloperSettings(
    enabled: enabled ?? this.enabled,
    enforcePaywall: enforcePaywall ?? this.enforcePaywall,
    paidFeatures: paidFeatures ?? this.paidFeatures,
    simulatedPlus: simulatedPlus ?? this.simulatedPlus,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'enforcePaywall': enforcePaywall,
    'paidFeatures': paidFeatures.toList()..sort(),
    'simulatedPlus': simulatedPlus,
  };

  factory DeveloperSettings.fromJson(Object? json) {
    if (json is! Map) return const DeveloperSettings();
    return DeveloperSettings(
      enabled: json['enabled'] == true,
      enforcePaywall: json['enforcePaywall'] == true,
      paidFeatures: {
        for (final id in json['paidFeatures'] as List? ?? const [])
          if (id is String && PaidFeature.byId(id) != null) id,
      },
      simulatedPlus: json['simulatedPlus'] == true,
    );
  }
}

/// Whether a feature may be used now.
abstract final class Entitlements {
  static bool allows(
    DeveloperSettings s,
    String featureId, {
    bool plus = false,
  }) {
    if (!s.enforcePaywall) return true;
    if (!s.paidFeatures.contains(featureId)) return true;
    return plus || s.simulatedPlus;
  }

  /// The features that are locked right now.
  static List<PaidFeature> locked(DeveloperSettings s, {bool plus = false}) => [
    for (final f in PaidFeature.catalog)
      if (!allows(s, f.id, plus: plus)) f,
  ];
}

/// A product in a store.
class PlusProduct {
  const PlusProduct(this.id, this.title, this.priceLabel);
  final String id, title, priceLabel;
}

sealed class PurchaseResult {
  const PurchaseResult();
}

class PurchaseUnavailable extends PurchaseResult {
  const PurchaseUnavailable(this.reason);
  final String reason;
}

class PurchaseDone extends PurchaseResult {
  const PurchaseDone(this.productId);
  final String productId;
}

/// The store seam. A real implementation (Google Play Billing) will list
/// products, buy and restore; the app asks only through this.
abstract class PurchaseProvider {
  Future<List<PlusProduct>> products();
  Future<PurchaseResult> buy(String productId);
  Future<bool> hasPlus();
}

/// Today's provider: nothing to buy, never charges.
class NoPurchaseProvider implements PurchaseProvider {
  const NoPurchaseProvider();
  static const reason = 'Оплата пока не подключена.';
  @override
  Future<List<PlusProduct>> products() async => const [];
  @override
  Future<PurchaseResult> buy(String productId) async =>
      const PurchaseUnavailable(reason);
  @override
  Future<bool> hasPlus() async => false;
}
