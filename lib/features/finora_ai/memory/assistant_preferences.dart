import '../../../domain/finance_engine.dart';

enum AssistantReportFormat { brief, detailed }

/// Only explicitly confirmed settings belong here. No model-derived facts or
/// historical balances are saved in preferences or reusable scenarios.
class PlannerPreferences {
  PlannerPreferences({
    this.sourceAccountId,
    this.currency = 'RUB',
    this.budgetMinor,
    this.reserveMinor = 0,
    this.horizonDays = 28,
  }) {
    if (sourceAccountId != null &&
            (sourceAccountId!.isEmpty || sourceAccountId!.length > 160) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        budgetMinor != null &&
            (budgetMinor! <= 0 || budgetMinor! > FinanceEngine.maxMinor) ||
        reserveMinor < 0 ||
        reserveMinor > FinanceEngine.maxMinor ||
        horizonDays < 7 ||
        horizonDays > 90) {
      throw const FormatException('Некорректные параметры планировщика');
    }
  }
  final String? sourceAccountId;
  final String currency;
  final int? budgetMinor;
  final int reserveMinor, horizonDays;

  factory PlannerPreferences.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'sourceAccountId',
      'currency',
      'budgetMinor',
      'reserveMinor',
      'horizonDays',
    });
    return PlannerPreferences(
      sourceAccountId: _optionalString(json, 'sourceAccountId'),
      currency: _string(json, 'currency', fallback: 'RUB'),
      budgetMinor: _optionalInt(json, 'budgetMinor'),
      reserveMinor: _int(json, 'reserveMinor', fallback: 0),
      horizonDays: _int(json, 'horizonDays', fallback: 28),
    );
  }
  Map<String, dynamic> toJson() => {
    'sourceAccountId': sourceAccountId,
    'currency': currency,
    'budgetMinor': budgetMinor,
    'reserveMinor': reserveMinor,
    'horizonDays': horizonDays,
  };
}

class AssistantPreferences {
  AssistantPreferences({
    this.primaryAccountId,
    this.planningWeekday = DateTime.monday,
    this.reportFormat = AssistantReportFormat.brief,
    PlannerPreferences? plannerParams,
  }) : plannerParams = plannerParams ?? PlannerPreferences() {
    if (planningWeekday < 1 ||
        planningWeekday > 7 ||
        primaryAccountId != null &&
            (primaryAccountId!.isEmpty || primaryAccountId!.length > 160)) {
      throw const FormatException('Некорректные предпочтения ассистента');
    }
  }
  final String? primaryAccountId;
  final int planningWeekday;
  final AssistantReportFormat reportFormat;
  final PlannerPreferences plannerParams;
  AssistantPreferences copyWith({
    String? primaryAccountId,
    bool clearPrimaryAccount = false,
    int? planningWeekday,
    AssistantReportFormat? reportFormat,
    PlannerPreferences? plannerParams,
  }) => AssistantPreferences(
    primaryAccountId: clearPrimaryAccount
        ? null
        : primaryAccountId ?? this.primaryAccountId,
    planningWeekday: planningWeekday ?? this.planningWeekday,
    reportFormat: reportFormat ?? this.reportFormat,
    plannerParams: plannerParams ?? this.plannerParams,
  );
  factory AssistantPreferences.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'primaryAccountId',
      'planningWeekday',
      'reportFormat',
      'plannerParams',
    });
    final report = _string(json, 'reportFormat', fallback: 'brief');
    if (!AssistantReportFormat.values.any((v) => v.name == report)) {
      throw const FormatException('Неизвестный формат отчёта');
    }
    return AssistantPreferences(
      primaryAccountId: _optionalString(json, 'primaryAccountId'),
      planningWeekday: _int(json, 'planningWeekday', fallback: DateTime.monday),
      reportFormat: AssistantReportFormat.values.byName(report),
      plannerParams: json['plannerParams'] == null
          ? null
          : PlannerPreferences.fromJson(_map(json['plannerParams'])),
    );
  }
  Map<String, dynamic> toJson() => {
    'primaryAccountId': primaryAccountId,
    'planningWeekday': planningWeekday,
    'reportFormat': reportFormat.name,
    'plannerParams': plannerParams.toJson(),
  };
}

enum ScenarioStepType { summary, upcomingPayments, debtPlan, showEntries }

class ScenarioStep {
  ScenarioStep({required this.type, Map<String, dynamic> parameters = const {}})
    : parameters = Map.unmodifiable(parameters) {
    switch (type) {
      case ScenarioStepType.summary:
        _keys(parameters, {'period'});
        if (parameters['period'] != null &&
            !{'week', 'month'}.contains(parameters['period'])) {
          throw const FormatException('Неизвестный период обзора');
        }
      case ScenarioStepType.upcomingPayments:
        _keys(parameters, {'withinDays'});
        final days = _int(parameters, 'withinDays', fallback: 28);
        if (days < 1 || days > 90) {
          throw const FormatException('Период платежей от 1 до 90 дней');
        }
      case ScenarioStepType.debtPlan:
        _keys(parameters, {
          'sourceAccountId',
          'currency',
          'budgetMinor',
          'reserveMinor',
          'horizonDays',
          'planningWeekday',
        });
        final weekday = _int(
          parameters,
          'planningWeekday',
          fallback: DateTime.monday,
        );
        if (weekday < 1 || weekday > 7) {
          throw const FormatException('Некорректный день планирования');
        }
        PlannerPreferences.fromJson(
          Map<String, dynamic>.from(parameters)..remove('planningWeekday'),
        );
      case ScenarioStepType.showEntries:
        _keys(parameters, {'kind', 'period', 'categoryId', 'accountId'});
        if (parameters['kind'] != null &&
                !{'expense', 'income'}.contains(parameters['kind']) ||
            parameters['period'] != null &&
                !{
                  'today',
                  'yesterday',
                  'this_week',
                  'this_month',
                  'last_month',
                  'all',
                }.contains(parameters['period'])) {
          throw const FormatException('Некорректные фильтры сценария');
        }
        _optionalString(parameters, 'categoryId');
        _optionalString(parameters, 'accountId');
    }
  }
  final ScenarioStepType type;
  final Map<String, dynamic> parameters;
  factory ScenarioStep.fromJson(Map<String, dynamic> json) {
    _keys(json, {'type', 'parameters'});
    final type = _string(json, 'type');
    if (!ScenarioStepType.values.any((v) => v.name == type)) {
      throw const FormatException('Неизвестная команда сохранённого сценария');
    }
    return ScenarioStep(
      type: ScenarioStepType.values.byName(type),
      parameters: json['parameters'] == null ? {} : _map(json['parameters']),
    );
  }
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'parameters': parameters,
  };
}

class SavedAssistantScenario {
  SavedAssistantScenario({
    required this.id,
    required this.name,
    required List<ScenarioStep> steps,
    List<String> requiredData = const ['finance'],
    required this.updatedAt,
    this.version = 1,
  }) : steps = List.unmodifiable(steps),
       requiredData = List.unmodifiable({
         ...requiredData,
         for (final step in steps) ..._dataFor(step.type),
       }) {
    if (version != 1 ||
        id.isEmpty ||
        id.length > 160 ||
        name.trim().isEmpty ||
        name.length > 80 ||
        steps.isEmpty ||
        steps.length > 8 ||
        requiredData.any(
          (d) => !{
            'finance',
            'accounts',
            'debts',
            'recurring',
            'categories',
          }.contains(d),
        )) {
      throw const FormatException('Некорректный сохранённый сценарий');
    }
  }
  final String id, name;
  final List<ScenarioStep> steps;
  final List<String> requiredData;
  final int version;
  final DateTime updatedAt;
  SavedAssistantScenario copyWith({
    String? name,
    List<ScenarioStep>? steps,
    DateTime? updatedAt,
  }) => SavedAssistantScenario(
    id: id,
    name: name ?? this.name,
    steps: steps ?? this.steps,
    requiredData: requiredData,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version,
  );
  factory SavedAssistantScenario.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'id',
      'name',
      'steps',
      'requiredData',
      'updatedAt',
      'version',
    });
    if (json['steps'] is! List ||
        json['requiredData'] != null && json['requiredData'] is! List) {
      throw const FormatException('Некорректные шаги сценария');
    }
    final date = DateTime.tryParse(_string(json, 'updatedAt'));
    if (date == null) throw const FormatException('Некорректная дата сценария');
    return SavedAssistantScenario(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      version: _int(json, 'version', fallback: 1),
      updatedAt: date,
      steps: [
        for (final step in json['steps'] as List)
          ScenarioStep.fromJson(_map(step)),
      ],
      requiredData: [
        for (final d in json['requiredData'] as List? ?? ['finance'])
          if (d is String)
            d
          else
            throw const FormatException('Некорректные данные сценария'),
      ],
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'steps': [for (final s in steps) s.toJson()],
    'requiredData': requiredData,
    'version': version,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

List<String> _dataFor(ScenarioStepType type) => switch (type) {
  ScenarioStepType.summary => const ['finance'],
  ScenarioStepType.upcomingPayments => const [
    'finance',
    'recurring',
    'accounts',
  ],
  ScenarioStepType.debtPlan => const [
    'finance',
    'debts',
    'recurring',
    'accounts',
  ],
  ScenarioStepType.showEntries => const ['finance', 'accounts', 'categories'],
};

void _keys(Map<String, dynamic> json, Set<String> allowed) {
  if (json.keys.any((k) => !allowed.contains(k))) {
    throw const FormatException('Неизвестные параметры ассистента');
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Ожидались параметры объекта');
  return Map<String, dynamic>.from(value);
}

String _string(Map<String, dynamic> json, String key, {String? fallback}) {
  final value = json[key] ?? fallback;
  if (value is! String) {
    throw const FormatException('Некорректное текстовое поле');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty || value.length > 160) {
    throw const FormatException('Некорректный идентификатор');
  }
  return value;
}

int _int(Map<String, dynamic> json, String key, {required int fallback}) {
  final value = json[key] ?? fallback;
  if (value is! int) throw const FormatException('Ожидалось целое число');
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) {
    throw const FormatException('Ожидалась сумма в целых копейках');
  }
  return value;
}
