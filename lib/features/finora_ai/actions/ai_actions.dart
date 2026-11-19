import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/voice_command_parser.dart';
import '../../../domain/voice_entry_parser.dart';

enum AiActionKind {
  openScreen,
  showEntries,
  setTheme,
  createEntry,
  editLastCategory,
  planDebts,
  reviewWeek,
  assistantMemory,
}

enum AiActionRisk { readOnly, preference, financialDraft }

enum AiActionSource { deterministic, model, restored }

class AiActionDescriptor {
  const AiActionDescriptor(this.kind, this.title, this.risk, this.requiredData);
  final AiActionKind kind;
  final String title;
  final AiActionRisk risk;
  final List<String> requiredData;
}

/// The same registry describes capabilities to UI, diagnostics and the model;
/// it is metadata, never executable code supplied by a model.
abstract final class AppActionRegistry {
  static const descriptors = <String, AiActionDescriptor>{
    'open_screen': AiActionDescriptor(
      AiActionKind.openScreen,
      'Открыть раздел',
      AiActionRisk.readOnly,
      [],
    ),
    'show_entries': AiActionDescriptor(
      AiActionKind.showEntries,
      'Показать операции',
      AiActionRisk.readOnly,
      ['entries'],
    ),
    'set_theme': AiActionDescriptor(
      AiActionKind.setTheme,
      'Изменить тему',
      AiActionRisk.preference,
      ['preferences'],
    ),
    'create_entry': AiActionDescriptor(
      AiActionKind.createEntry,
      'Заполнить операцию',
      AiActionRisk.financialDraft,
      ['accounts', 'categories'],
    ),
    'edit_last_category': AiActionDescriptor(
      AiActionKind.editLastCategory,
      'Исправить категорию',
      AiActionRisk.financialDraft,
      ['entries', 'categories'],
    ),
    'plan_debts': AiActionDescriptor(
      AiActionKind.planDebts,
      'Составить план погашения',
      AiActionRisk.financialDraft,
      ['accounts', 'recurring', 'entries'],
    ),
    'review_week': AiActionDescriptor(
      AiActionKind.reviewWeek,
      'Недельный разбор',
      AiActionRisk.readOnly,
      ['entries', 'recurring'],
    ),
    'assistant_memory': AiActionDescriptor(
      AiActionKind.assistantMemory,
      'Предпочтения и сценарии',
      AiActionRisk.preference,
      [],
    ),
  };

  static AiActionDescriptor forKind(AiActionKind kind) =>
      descriptors.values.firstWhere((d) => d.kind == kind);
}

/// A capability, not model text. Only [AiActionSession] can construct one.
/// It is bound to the trusted user turn, exact arguments and ledger snapshot.
class AiPendingAction {
  AiPendingAction._({
    required this.id,
    required this.requestId,
    required this.kind,
    required this.arguments,
    required this.fingerprint,
    required this.summary,
    required this.createdAt,
    required this.draftId,
    required this.source,
    this.command,
    this.entry,
  });

  final String id, requestId, fingerprint, summary;
  final String draftId;
  final AiActionSource source;
  final AiActionKind kind;
  AiActionRisk get risk => AppActionRegistry.forKind(kind).risk;
  final Map<String, Object?> arguments;
  final DateTime createdAt;
  final VoiceCommand? command;

  /// A draft only; the editor and controller remain the sole save path.
  final FinanceEntry? entry;
}

class AiActionResolution {
  const AiActionResolution(
    this.message, {
    this.pending,
    this.needsClarification = false,
  });
  final String message;
  final AiPendingAction? pending;
  final bool needsClarification;
}

class AiActionException implements Exception {
  const AiActionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Deliberately small whitelist over Finora's existing commands and editors.
/// No model-provided user, entry ID, SQL, execution flag or confirmation exists.
class AiActionSession {
  static const promptSchema = '''
Actions (one at a time, never claim success):
open_screen args {screen:home|operations|analytics|settings|accounts|goals|budgets|calendar|categories|recurring}
show_entries args {kind?:expense|income,period?:today|yesterday|this_week|this_month|last_month|all,categoryId?:string,accountId?:string}
set_theme args {mode:dark|light|system}
create_entry args {kind:expense|income,amountMinor:integer kopecks,categoryId?:string,accountId?:string,date?:today|yesterday|day_before_yesterday|YYYY-MM-DD,payee?:string}
edit_last_category args {categoryId:string} (only latest own expense; editor confirms identity).
plan_debts args {accountId?:string,budgetMinor?:integer,reserveMinor?:integer,horizonDays?:integer1..90}: draft repayment plan, only explicitly named parameters; never bank transfers.
review_week args {}: review the current week's actual financial data.
assistant_memory args {}: open confirmed preferences and saved scenarios, never write model guesses.
Only IDs in objects are allowed. Missing/ambiguous account or category must be clarified. An action never confirms itself. No delete, bulk, transfer or arbitrary code capability. User corrections amend only unfinishedAction. After a form opens it is no longer unfinished.
''';

  static final _negated = RegExp(
    r'(^|\s)(?:не\s+(?:(?:надо|нужно|хочу)\s+)?(?:добав[а-яa-z]*|запис[а-яa-z]*|сохраня[а-яa-z]*|меня[а-яa-z]*|спис[а-яa-z]*|созда[а-яa-z]*|откры[а-яa-z]*|показы[а-яa-z]*|покаж[а-яa-z]*|включ[а-яa-z]*|выключ[а-яa-z]*|переключ[а-яa-z]*|помен[а-яa-z]*|измен[а-яa-z]*|удал[а-яa-z]*|дел[а-яa-z]*|перевед[а-яa-z]*|планир[а-яa-z]*|распредел[а-яa-z]*|рассчит[а-яa-z]*|состав[а-яa-z]*)|ничего\s+не\s+[а-яa-z]+)',
    caseSensitive: false,
  );
  static final _cancelled = RegExp(
    r'(^|\s)(?:отмена|отмени[а-яa-z]*|стоп|забудь|не\s+надо)(?:\s|[.!?,]|$)',
    caseSensitive: false,
  );
  static final _writeIntent = RegExp(
    r'(^|\s)(?:добав[а-яa-z]*|запиш[а-яa-z]*|запис[а-яa-z]*|потрат[а-яa-z]*|купил[а-яa-z]*|получ[а-яa-z]*|оплат[а-яa-z]*|спиш[а-яa-z]*|спис[а-яa-z]*)(?:\s|[.!?,]|$)|^(?:расход|доход)(?:\s|[.!?,]|$)',
    caseSensitive: false,
  );
  final _settled = <String>{};
  Map<String, dynamic>? _draft;
  final _trustedTurns = <String>[];
  AiPendingAction? _pending;
  DateTime? _draftSince;
  String? _draftId;
  final _turnTimes = <DateTime>[];

  /// Set only from the person's confirmed preference, not a model argument.
  String? primaryAccountId;

  /// The person's short names for places, written in full («Кб» →
  /// «Красное&Белое»); set by the chat from Finora's memory.
  String Function(String payee)? payeeResolver;

  /// The category the person's memory settled for a place (strong votes
  /// only); fills a draft whose category was not named.
  String? Function(String payee, EntryKind kind)? rememberedCategory;
  int _sequence = 0;
  bool _confirmationInFlight = false;

  AiPendingAction? get pending => _pending;

  /// Call as soon as a trusted user turn arrives, before asynchronous inference.
  /// Buttons from a preceding turn immediately lose their authority.
  void beginUserTurn(String text, {DateTime? now}) {
    _pending = null;
    _expire(now ?? DateTime.now());
    if (prohibitsAction(text) ||
        _freshCreationRequested(text) ||
        _isTopicChange(text)) {
      cancel();
    }
  }

  String? get unfinishedDraftId => _draftId;

  Map<String, Object?>? get unfinishedAction => _draft == null
      ? null
      : {
          'action': _draft!['action'],
          'args': Map<String, dynamic>.from(_draft!['args'] as Map),
        };

  void cancel() {
    _pending = null;
    _draft = null;
    _draftSince = null;
    _draftId = null;
    _trustedTurns.clear();
    _turnTimes.clear();
  }

  static bool prohibitsAction(String text) =>
      _negated.hasMatch(_normal(text)) || _cancelled.hasMatch(_normal(text));

  /// At most a handful of names/IDs, never operations, comments or full DB.
  /// The account collection is local to the current FinanceScope; this app has
  /// no per-account remote ACL. Archived objects are never exposed as targets.
  Map<String, Object?> context(FinanceData data, String userText) {
    final text = _normal(userText);
    final accounts = data.accounts.where((a) => !a.archived).toList();
    accounts.sort(
      (a, b) => _mentioned(text, b.name).compareTo(_mentioned(text, a.name)),
    );
    final categories = data.categories.where((c) => !c.archived).toList();
    categories.sort(
      (a, b) => _mentioned(text, b.name).compareTo(_mentioned(text, a.name)),
    );
    return {
      'accounts': [
        for (final a in accounts.take(8))
          {'id': a.id, 'name': a.name, 'currency': a.currency},
      ],
      'categories': [
        for (final c in categories.take(10))
          {'id': c.id, 'name': c.name, 'kind': c.kind.name},
      ],
      if (_draft != null) 'unfinishedAction': unfinishedAction,
    };
  }

  /// Existing reliable voice parsers may bypass inference, but never validation
  /// or user review. Unsupported commands remain with the existing assistant.
  AiActionResolution? resolveDeterministic(
    String userText, {
    required FinanceData data,
    DateTime? now,
    String? requestId,
  }) {
    final clock = (now ?? DateTime.now()).toLocal();
    if (prohibitsAction(userText)) {
      cancel();
      return const AiActionResolution('Действие отменено. Ничего не изменено.');
    }
    _expire(clock);
    if (_draft != null &&
        (_freshCreationRequested(userText) || _isTopicChange(userText))) {
      cancel();
    }
    AiActionResolution resolveArgs(String action, Map<String, Object?> args) =>
        resolve(
          jsonEncode({'action': action, 'args': args}),
          userText: userText,
          data: data,
          now: clock,
          requestId: requestId,
          source: AiActionSource.deterministic,
        );
    final text = _normal(userText);
    final namedAccounts = _namedAccounts(userText, data);
    final namedCategories = data.categories
        .where((c) => !c.archived && _nameInText(c.name, userText))
        .toList();
    final amount = _trustedAmountIn(userText, data);
    if (_debtPlanningRequested(userText)) return resolveArgs('plan_debts', {});
    if (_weeklyReviewRequested(userText)) return resolveArgs('review_week', {});
    if (_memoryRequested(userText)) return resolveArgs('assistant_memory', {});
    final correctingEntry = _draft?['action'] == 'create_entry';
    // Scoped follow-up does not invent fields from the new utterance. Only
    // independently recognized corrections amend the still-open draft.
    if (correctingEntry) {
      final selectionIssue = _accountSelectionIssue(userText, data);
      if (selectionIssue != null) {
        return AiActionResolution(selectionIssue, needsClarification: true);
      }
      final changes = <String, Object?>{
        if (namedAccounts.length == 1) 'accountId': namedAccounts.single,
        if (namedCategories.length == 1)
          'categoryId': namedCategories.single.id,
        'amountMinor': ?amount,
        if (_dateInTurn(userText) case final String date) 'date': date,
      };
      if (changes.isNotEmpty) return resolveArgs('create_entry', changes);
    }
    Map<String, Object?> entryArgs() {
      final draft = VoiceEntryParser.parse(
        userText,
        categories: data.categories,
        history: data.entries,
        now: clock,
      );
      // The place is read without the account words: «с основной карты»
      // is not a shop.
      final place = VoiceEntryParser.parse(
        _withoutAccounts(userText, data),
        categories: data.categories,
        history: data.entries,
        now: clock,
      );
      // The place as heard («Кб»); written in full when the draft is built.
      final payee = place.payee.trim();
      final payeeHeard =
          payee.isNotEmpty && _normal(userText).contains(_normal(payee));
      final remembered = namedCategories.length == 1 || !payeeHeard
          ? null
          : rememberedCategory?.call(payee, draft.kind);
      return {
        'kind': draft.kind.name,
        'amountMinor': amount!,
        if (namedAccounts.length == 1) 'accountId': namedAccounts.single,
        if (namedCategories.length == 1)
          'categoryId': namedCategories.single.id
        else
          'categoryId': ?remembered,
        if (payeeHeard) 'payee': payee,
        'date': _dateInTurn(text) ?? 'today',
      };
    }

    // The legacy generic command parser treats «добавь … наличные» as account
    // creation. An explicit operation or named expense category is a narrower
    // intent; still use its existing entry parser and the same safe validator.
    final explicitEntry = RegExp(
      r'(^|\s)(?:расход[а-я]*|доход[а-я]*|потрат[а-я]*|купил[а-я]*|получ[а-я]*|спиш[а-я]*)(?:\s|$)',
    ).hasMatch(text);
    final anotherEntity = RegExp(
      r'(^|\s)(?:цел[а-я]*|мечт[а-я]*|счет[а-я]*|карт[а-я]*|категори[а-я]*|бюджет[а-я]*|подписк[а-я]*|кредит[а-я]*)(?:\s|$)',
    ).hasMatch(text);
    if (_writeRequested(text) &&
        amount != null &&
        (explicitEntry || namedCategories.length == 1 && !anotherEntity)) {
      return resolveArgs('create_entry', entryArgs());
    }
    final command = VoiceCommandParser.parse(
      [userText],
      categories: data.categories,
      accounts: data.accounts,
      now: clock,
      weekStart: data.preferences.weekStart,
    );
    switch (command) {
      case OpenScreenCommand():
        if (command.screen == VoiceScreen.more ||
            command.screen == VoiceScreen.members ||
            command.screen == VoiceScreen.importAccounts) {
          return null;
        }
        return resolveArgs('open_screen', {'screen': command.screen.name});
      case ThemeCommand():
        if (command.mode == null || command.hasColor) return null;
        return resolveArgs('set_theme', {'mode': command.mode});
      case ShowEntriesCommand():
        if (command.kind == EntryKind.transfer) return null;
        String? period;
        if (command.start == null && command.end == null) {
          period = 'all';
        } else {
          for (final candidate in _periodNames.keys.where((p) => p != 'all')) {
            final range = _range(candidate, clock, data.preferences.weekStart)!;
            bool sameDay(DateTime? a, DateTime b) =>
                a != null &&
                a.year == b.year &&
                a.month == b.month &&
                a.day == b.day;
            if (sameDay(command.start, range.$1) &&
                sameDay(command.end, range.$2)) {
              period = candidate;
            }
          }
        }
        if (period == null) return null;
        return resolveArgs('show_entries', {
          if (command.kind != null && command.kind != EntryKind.transfer)
            'kind': command.kind!.name,
          'period': period,
          if (command.categoryId != null) 'categoryId': command.categoryId,
          if (command.accountId != null) 'accountId': command.accountId,
        });
      default:
        if (command != null && command is! UnknownCommand) return null;
        break;
    }
    if (_writeRequested(text) && amount != null) {
      return resolveArgs('create_entry', entryArgs());
    }
    return null;
  }

  /// Call only with the final, uncancelled model output. Partial JSON, unknown
  /// fields and invented IDs fail closed. A new turn invalidates old approval.
  AiActionResolution resolve(
    String completeJson, {
    required String userText,
    required FinanceData data,
    DateTime? now,
    String? requestId,
    AiActionSource source = AiActionSource.model,
  }) {
    final clock = (now ?? DateTime.now()).toLocal();
    final key = requestId ?? _hash('$userText\n$completeJson');
    _pending = null;
    if (_settled.contains(key)) {
      return const AiActionResolution('Это действие уже было обработано.');
    }
    if (prohibitsAction(userText)) {
      cancel();
      return const AiActionResolution('Действие отменено. Ничего не изменено.');
    }
    _expire(clock);
    if (_draft != null &&
        (_freshCreationRequested(userText) || _isTopicChange(userText))) {
      cancel();
    }
    try {
      if (completeJson.length > 12000) {
        throw const AiActionException('Слишком длинная команда.');
      }
      final decoded = jsonDecode(completeJson);
      if (decoded is! Map<String, dynamic>) {
        throw const AiActionException('Некорректная команда.');
      }
      _keys(decoded, {'action', 'args'});
      final name = _string(decoded, 'action', required: true)!;
      if (!AppActionRegistry.descriptors.containsKey(name)) {
        throw const AiActionException(
          'Это действие не входит в разрешённые команды.',
        );
      }
      final inputArgs = decoded['args'];
      if (inputArgs is! Map<String, dynamic>) {
        throw const AiActionException('Некорректные аргументы команды.');
      }
      if (_draft?['action'] != name) {
        cancel();
        _draftSince = clock;
        _draftId = const Uuid().v4();
      }
      _trustedTurns.add(userText);
      _turnTimes.add(clock);
      if (_trustedTurns.length > 8) {
        throw const AiActionException(
          'Уточнение устарело. Повторите действие целиком.',
        );
      }
      final args = <String, dynamic>{
        if (_draft != null)
          ...Map<String, dynamic>.from(_draft!['args'] as Map),
        ...inputArgs,
      };
      _draft = {'action': name, 'args': args};
      _draftSince ??= clock;
      final action = _validate(name, args, data, clock, key, source: source);
      _pending = action;
      return AiActionResolution(action.summary, pending: action);
    } on _Clarify catch (e) {
      return AiActionResolution(e.message, needsClarification: true);
    } on AiActionException catch (e) {
      cancel();
      return AiActionResolution(e.message);
    } on FormatException {
      cancel();
      return const AiActionResolution(
        'Команда повреждена. Ничего не изменено.',
      );
    }
  }

  AiPendingAction _validate(
    String name,
    Map<String, dynamic> args,
    FinanceData d,
    DateTime now,
    String requestId, {
    AiActionSource source = AiActionSource.model,
  }) {
    VoiceCommand? command;
    FinanceEntry? entry;
    late AiActionKind kind;
    late String summary;
    final user = _trustedTurns.join('\n');
    switch (name) {
      case 'open_screen':
        _keys(args, {'screen'});
        const screens = {
          'home': VoiceScreen.home,
          'operations': VoiceScreen.operations,
          'analytics': VoiceScreen.analytics,
          'settings': VoiceScreen.settings,
          'accounts': VoiceScreen.accounts,
          'goals': VoiceScreen.goals,
          'budgets': VoiceScreen.budgets,
          'calendar': VoiceScreen.calendar,
          'categories': VoiceScreen.categories,
          'recurring': VoiceScreen.recurring,
        };
        final screen = _string(args, 'screen', required: true)!;
        if (!screens.containsKey(screen)) {
          throw const AiActionException('Этот раздел не поддерживается.');
        }
        if (!_trustedTurns.any(
          (turn) =>
              _navigationRequested(turn) ||
              _normal(turn) == _normal(_screenNames[screen]!),
        )) {
          throw const AiActionException('Открытие раздела не запрошено.');
        }
        command = OpenScreenCommand(user, screens[screen]!);
        kind = AiActionKind.openScreen;
        summary = 'Открыть раздел «${_screenNames[screen]}»?';
      case 'show_entries':
        _keys(args, {'kind', 'period', 'categoryId', 'accountId'});
        if (!_trustedTurns.any(
          (turn) =>
              _navigationRequested(turn) ||
              RegExp(
                r'^(?:расход[а-я]*|доход[а-я]*|операци[а-я]*|трат[а-я]*)(?:\s|$)',
              ).hasMatch(_normal(turn)),
        )) {
          throw const AiActionException('Показ операций не запрошен.');
        }
        final entryKind = _kind(args, optional: true);
        final category = _category(args, d, entryKind, optional: true);
        final account = _account(args, d, optional: true);
        final period = _string(args, 'period') ?? 'this_month';
        final range = _range(period, now, d.preferences.weekStart);
        command = ShowEntriesCommand(
          user,
          kind: entryKind,
          start: range?.$1,
          end: range?.$2,
          categoryId: category?.id,
          accountId: account?.id,
          title: 'Операции${category == null ? '' : ' · ${category.name}'}',
        );
        kind = AiActionKind.showEntries;
        summary =
            'Показать операции: ${entryKind?.name == 'income'
                ? 'доходы'
                : entryKind == null
                ? 'все типы'
                : 'расходы'}'
            '${category == null ? '' : ', ${category.name}'}${account == null ? '' : ', ${account.name}'} · ${_periodNames[period]}?';
      case 'set_theme':
        _keys(args, {'mode'});
        final mode = _string(args, 'mode', required: true)!;
        if (!{'dark', 'light', 'system'}.contains(mode)) {
          throw const AiActionException('Неизвестная тема.');
        }
        if (!RegExp(r'тем|оформлен', caseSensitive: false).hasMatch(user) ||
            !RegExp(
              r'(^|\s)(?:включ[а-я]*|сделай|сделать|помен[а-я]*|измени[а-я]*|установ[а-я]*|переключ[а-я]*|выбери)(?:\s|$)',
              caseSensitive: false,
            ).hasMatch(user)) {
          throw const AiActionException('Изменение темы не запрошено.');
        }
        command = ThemeCommand(user, mode: mode);
        kind = AiActionKind.setTheme;
        summary =
            'Установить ${switch (mode) {
              'dark' => 'тёмную тему',
              'light' => 'светлую тему',
              _ => 'системную тему',
            }}?';
      case 'create_entry':
        _keys(args, {
          'kind',
          'amountMinor',
          'categoryId',
          'accountId',
          'date',
          'payee',
        });
        if (!_trustedTurns.any((turn) => _writeRequested(_normal(turn)))) {
          throw const AiActionException('Добавление операции не запрошено.');
        }
        final selectionIssue = _accountSelectionIssue(_trustedTurns.last, d);
        if (selectionIssue != null) throw _Clarify(selectionIssue);
        final entryKind = _kind(args)!;
        final rawAmount = args['amountMinor'];
        if (rawAmount == null) throw const _Clarify('Какую сумму записать?');
        if (rawAmount is! int ||
            rawAmount <= 0 ||
            rawAmount > FinanceEngine.maxMinor) {
          throw const AiActionException(
            'Сумма должна быть положительным целым числом копеек.',
          );
        }
        final latestAmount = _trustedTurns.reversed
            .map((turn) => _trustedAmountIn(turn, d))
            .whereType<int>()
            .firstOrNull;
        if (latestAmount == null || latestAmount != rawAmount) {
          throw const AiActionException(
            'Сумма не совпадает с последним уточнением. Повторите её цифрами.',
          );
        }
        final account = _account(args, d)!;
        final currencies = <String>{};
        for (final pair in const {
          'RUB': r'(?:\bRUB\b|руб|₽)',
          'USD': r'(?:\bUSD\b|доллар|\$)',
          'EUR': r'(?:\bEUR\b|евро|€)',
          'CNY': r'(?:\bCNY\b|юан)',
          'TRY': r'(?:\bTRY\b|лир)',
          'GEL': r'(?:\bGEL\b|лари)',
        }.entries) {
          if (RegExp(pair.value, caseSensitive: false).hasMatch(user)) {
            currencies.add(pair.key);
          }
        }
        if (currencies.length > 1 ||
            currencies.isNotEmpty && currencies.single != account.currency) {
          throw const _Clarify(
            'Валюта в сообщении не совпадает с валютой счёта. Уточните счёт и сумму в его валюте.',
          );
        }
        final mentionedAccounts = _latestNamedAccounts(d);
        if (mentionedAccounts.isEmpty) {
          throw const _Clarify(
            'Назовите счёт для операции. Я не буду выбирать его за вас.',
          );
        }
        if (mentionedAccounts.length != 1 ||
            !mentionedAccounts.contains(account.id)) {
          throw const _Clarify('Неоднозначный счёт. Уточните его название.');
        }
        final category = _category(args, d, entryKind)!;
        final requestedDate = _trustedTurns.reversed
            .map(_dateInTurn)
            .whereType<String>()
            .firstOrNull;
        final rawDate = _string(args, 'date') ?? requestedDate ?? 'today';
        if (requestedDate != null && rawDate != requestedDate) {
          throw const AiActionException(
            'Дата не совпадает с последним уточнением. Повторите её.',
          );
        }
        var dateClock = _turnTimes.firstOrNull ?? now;
        for (var i = _trustedTurns.length - 1; i >= 0; i--) {
          if (_dateInTurn(_trustedTurns[i]) != null) {
            dateClock = _turnTimes[i];
            break;
          }
        }
        final date = _date(rawDate, dateClock, user);
        final heardPayee = _string(args, 'payee') ?? '';
        if (heardPayee.isNotEmpty &&
            !_normal(user).contains(_normal(heardPayee))) {
          throw const AiActionException(
            'Получатель не найден в вашем сообщении.',
          );
        }
        // A short name the person taught is written in full.
        final payee = heardPayee.isEmpty
            ? heardPayee
            : (payeeResolver?.call(heardPayee) ?? heardPayee);
        entry = FinanceEntry(
          id: '',
          kind: entryKind,
          amountMinor: rawAmount,
          currency: account.currency,
          accountId: account.id,
          categoryId: category.id,
          date: date,
          payee: payee,
        );
        kind = AiActionKind.createEntry;
        summary =
            '${entryKind == EntryKind.expense ? 'Расход' : 'Доход'}: ${_amount(rawAmount)} ${account.currency}\n'
            '${payee.isEmpty ? '' : '$payee${payee != heardPayee ? ' («$heardPayee»)' : ''}\n'}'
            '${category.name} · ${account.name}\n${_formatDate(date)}\n'
            'Открыть заполненную форму? Сохранение — только вашей кнопкой.';
      case 'edit_last_category':
        _keys(args, {'categoryId'});
        if (!RegExp(
          r'(исправ|помен|измен|категори).*(последн|покупк)|(последн|покупк).*(исправ|помен|измен|категори)',
          caseSensitive: false,
        ).hasMatch(user)) {
          throw const AiActionException(
            'Изменение последней покупки не запрошено.',
          );
        }
        final own =
            d.entries
                .where((e) => e.memberId == 'me' && e.kind == EntryKind.expense)
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        if (own.isEmpty) {
          throw const AiActionException(
            'Собственных расходов для изменения нет.',
          );
        }
        final old = own.first;
        final category = _category(args, d, EntryKind.expense)!;
        final account = d.accounts
            .where((a) => a.id == old.accountId && !a.archived)
            .firstOrNull;
        if (account == null) {
          throw const AiActionException('Счёт последней покупки недоступен.');
        }
        entry = old.copyWith(categoryId: category.id, subcategory: null);
        kind = AiActionKind.editLastCategory;
        summary =
            'Последний собственный расход: ${_amount(old.amountMinor)} ${old.currency}'
            '\n${_formatDate(old.date)}${old.payee.isEmpty ? '' : ' · ${old.payee}'} · ${account.name}'
            '\nНовая категория: ${category.name}. Открыть форму изменения?';
      case 'plan_debts':
        _keys(args, {
          'accountId',
          'budgetMinor',
          'reserveMinor',
          'horizonDays',
        });
        if (!_trustedTurns.any(_debtPlanningRequested)) {
          throw const AiActionException('План погашения не запрошен.');
        }
        final account = _account(args, d, optional: true);
        if (account != null && !_latestNamedAccounts(d).contains(account.id)) {
          throw const _Clarify(
            'Назовите счёт для плана. Я не буду выбирать его за вас.',
          );
        }
        for (final field in ['budgetMinor', 'reserveMinor']) {
          final value = args[field];
          if (value == null) continue;
          if (value is! int ||
              value < (field == 'budgetMinor' ? 1 : 0) ||
              value > FinanceEngine.maxMinor) {
            throw const AiActionException(
              'Некорректная сумма параметра плана.',
            );
          }
          final trusted = _trustedTurns.reversed
              .map(
                (turn) => _labelledMoney(
                  turn,
                  field == 'budgetMinor'
                      ? r'бюджет[а-я]*|на погашение|на выплаты'
                      : r'резерв[а-я]*|оставить|оставь',
                ),
              )
              .whereType<int>()
              .firstOrNull;
          if (trusted != value) {
            throw const _Clarify(
              'Укажите бюджет и резерв явно. Условия плана не будут придуманы.',
            );
          }
        }
        final horizon = args['horizonDays'];
        if (horizon != null) {
          if (horizon is! int || horizon < 1 || horizon > 90) {
            throw const AiActionException('Период плана — от 1 до 90 дней.');
          }
          final trusted =
              RegExp(
                    r'(?:на|за)\s+(\d+)\s*(дн[а-я]*|недел[а-я]*)',
                    caseSensitive: false,
                  )
                  .allMatches(user)
                  .map(
                    (m) =>
                        int.parse(m[1]!) *
                        (m[2]!.toLowerCase().startsWith('недел') ? 7 : 1),
                  );
          if (!trusted.contains(horizon)) {
            throw const _Clarify('На сколько дней составить план?');
          }
        }
        kind = AiActionKind.planDebts;
        summary =
            'Открыть черновик плана погашения по актуальным долгам? Даты, бюджет и источник средств будут проверены до сохранения.';
      case 'review_week':
        _keys(args, {});
        if (!_trustedTurns.any(_weeklyReviewRequested)) {
          throw const AiActionException('Недельный разбор не запрошен.');
        }
        kind = AiActionKind.reviewWeek;
        summary =
            'Открыть недельный разбор по актуальным операциям и платежам?';
      case 'assistant_memory':
        _keys(args, {});
        if (!_trustedTurns.any(_memoryRequested)) {
          throw const AiActionException('Управление памятью не запрошено.');
        }
        kind = AiActionKind.assistantMemory;
        summary = 'Открыть подтверждённые предпочтения и сохранённые сценарии?';
      default:
        throw const AiActionException(
          'Это действие не входит в разрешённые команды.',
        );
    }
    return AiPendingAction._(
      id: '${++_sequence}:${_hash(jsonEncode(args))}',
      requestId: requestId,
      kind: kind,
      draftId: _draftId ?? const Uuid().v4(),
      source: source,
      arguments: Map.unmodifiable(args),
      fingerprint: fingerprint(d),
      summary: summary,
      createdAt: now,
      command: command,
      entry: entry,
    );
  }

  /// Validates exact identity/arguments after an asynchronous confirmation.
  /// A changed ledger or later clarification invalidates the old capability.
  bool isCurrent(AiPendingAction action, FinanceData data, {DateTime? now}) =>
      identical(_pending, action) &&
      !_settled.contains(action.requestId) &&
      fingerprint(data) == action.fingerprint &&
      (now ?? DateTime.now()).toLocal().difference(action.createdAt) >=
          Duration.zero &&
      (now ?? DateTime.now()).toLocal().difference(action.createdAt) <
          const Duration(minutes: 5);

  bool isConsumed(String requestId) => _settled.contains(requestId);

  bool consume(AiPendingAction action, FinanceData data, {DateTime? now}) {
    if (!isCurrent(action, data, now: now)) return false;
    _settled.add(action.requestId);
    // Bounded session-only idempotency; writes are never automatic. A form owns
    // its ID and saving twice replaces that entry via the existing controller.
    if (_settled.length > 100) _settled.remove(_settled.first);
    cancel();
    return true;
  }

  /// Prevents double taps from stacking dialogs. Cancellation invalidates the
  /// capability immediately; the dialog owner releases this separate lease.
  bool beginConfirmation(
    AiPendingAction action,
    FinanceData data, {
    DateTime? now,
  }) {
    if (_confirmationInFlight || !isCurrent(action, data, now: now)) {
      return false;
    }
    _confirmationInFlight = true;
    return true;
  }

  void endConfirmation() => _confirmationInFlight = false;

  static String fingerprint(FinanceData d) => _hash(
    jsonEncode({
      'accounts': d.accounts.map((a) => a.toJson()).toList(),
      'categories': d.categories.map((a) => a.toJson()).toList(),
      'entries': d.entries.map((a) => a.toJson()).toList(),
      'recurring': d.recurring.map((a) => a.toJson()).toList(),
      'budgets': d.budgets.map((a) => a.toJson()).toList(),
      'goals': d.goals.map((a) => a.toJson()).toList(),
      'members': d.members.map((a) => a.toJson()).toList(),
      'baseCurrency': d.preferences.baseCurrency,
      'weekStart': d.preferences.weekStart,
      'monthStart': d.preferences.monthStart,
      'theme': d.preferences.theme,
      'accent': d.preferences.accent,
    }),
  );

  static Account? _account(
    Map<String, dynamic> args,
    FinanceData d, {
    bool optional = false,
  }) {
    final id = _string(args, 'accountId');
    if (id == null) {
      if (optional) return null;
      throw const _Clarify('С какого счёта? Назовите нужный счёт.');
    }
    final account = d.accounts
        .where((a) => a.id == id && !a.archived)
        .firstOrNull;
    if (account == null) {
      throw const AiActionException(
        'Счёт не найден или архивирован. Выберите существующий счёт.',
      );
    }
    return account;
  }

  Set<String> _latestNamedAccounts(FinanceData data) {
    for (final turn in _trustedTurns.reversed) {
      final matching = _namedAccounts(turn, data);
      if (matching.isNotEmpty) return matching;
    }
    return {};
  }

  Set<String> _namedAccounts(String text, FinanceData data) {
    final named = data.accounts
        .where(
          (a) =>
              !a.archived &&
              (_nameInText(a.name, text) || _lastFourMentioned(a, text)),
        )
        .map((a) => a.id)
        .toSet();
    if (named.isNotEmpty) return named;
    final primary = data.accounts
        .where((a) => a.id == primaryAccountId && !a.archived)
        .firstOrNull;
    if (primary != null &&
        RegExp(r'основн[а-я]*', caseSensitive: false).hasMatch(text)) {
      return {primary.id};
    }
    return {};
  }

  static final _cardDigits = RegExp(
    r'((?:карт[а-я]*|счет[а-я]*|номер[а-я]*|заканчива[а-я]*|оканчива[а-я]*)\s*(?:на\s*)?(?:[•*хx]+)?\s*)(\d{4})(?!\d)',
  );

  static bool _lastFourMentioned(Account account, String text) {
    if (!RegExp(r'^\d{4}$').hasMatch(account.lastFour)) return false;
    final n = _normal(text);
    return n == account.lastFour ||
        _cardDigits.allMatches(n).any((m) => m[2] == account.lastFour);
  }

  String? _accountSelectionIssue(String text, FinanceData data) {
    final n = _normal(text);
    for (final match in _cardDigits.allMatches(n)) {
      if (!data.accounts.any((a) => !a.archived && a.lastFour == match[2])) {
        return 'Карта с такими цифрами не найдена. Назовите существующий счёт.';
      }
    }
    if (RegExp(r'основн[а-я]*').hasMatch(n) &&
        _namedAccounts(text, data).isEmpty) {
      return 'Основной счёт не выбран. Укажите существующий счёт.';
    }
    return null;
  }

  void _expire(DateTime clock) {
    if (_draftSince != null &&
        (clock.difference(_draftSince!) >= const Duration(minutes: 5) ||
            clock.isBefore(_draftSince!))) {
      cancel();
    }
  }

  static bool _isTopicChange(String text) => RegExp(
    r'^(?:почему|сколько|какой|какая|какие|когда|зачем|как|что|привет|спасибо|покажи|открой|расскажи|включи|выключи|перейди|планируй|посчитай)(?:\s|[?!.,]|$)',
    caseSensitive: false,
  ).hasMatch(_normal(text));

  static bool _debtPlanningRequested(String text) {
    final t = _normal(text);
    return !prohibitsAction(t) &&
        RegExp(r'долг|кредит|займ|задолж').hasMatch(t) &&
        RegExp(r'план|распредел|график|посчитай|рассчитай|погаш').hasMatch(t);
  }

  static bool _weeklyReviewRequested(String text) {
    final t = _normal(text);
    return !prohibitsAction(t) &&
        RegExp(r'недел').hasMatch(t) &&
        RegExp(r'обзор|разбор|итог|сводк|покажи|подведи').hasMatch(t);
  }

  static bool _memoryRequested(String text) {
    final t = _normal(text);
    return !prohibitsAction(t) &&
        RegExp(r'памят|предпочтени|сценари').hasMatch(t) &&
        (RegExp(r'открой|покажи|сохран|измени|настро|управ|мои').hasMatch(t));
  }

  static int? _labelledMoney(String text, String labels) {
    final match = RegExp(
      '(?:$labels)\\s*(?:[:=]|в размере)?\\s*([0-9][0-9 \u00a0]*(?:[,.][0-9]{1,2})?)',
      caseSensitive: false,
    ).firstMatch(text);
    return match == null ? null : VoiceEntryParser.amountIn(match[1]!)?.minor;
  }

  static String? _dateInTurn(String text) =>
      _relativeDateIn(text) ??
      RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(text)?.group(0);

  static int? _trustedAmountIn(String text, FinanceData data) {
    var t = _normal(text).replaceAll(RegExp(r'\d{4}-\d{2}-\d{2}'), ' ');
    // Card/account identifiers select an object, never a transaction amount,
    // even when the four digits do not match an existing card.
    t = t.replaceAllMapped(_cardDigits, (m) => m[1]!);
    if (data.accounts.any(
      (a) => _lastFourMentioned(a, t) && _normal(t) == a.lastFour,
    )) {
      return null;
    }
    final corrections = RegExp(r'(?:^|[\s,])а\s+').allMatches(t).toList();
    if (corrections.isNotEmpty) {
      final last = corrections.last;
      final after = t.substring(last.end).trimLeft();
      if (RegExp(r'^не\s+').hasMatch(after)) {
        t = t.substring(0, last.start);
        final earlier = RegExp(r'(?:^|[\s,])а\s+').allMatches(t).toList();
        if (earlier.isNotEmpty) t = t.substring(earlier.last.end);
      } else {
        t = after;
      }
    }
    t = t.replaceAll(RegExp(r'[\s,;.!?]+$'), '');
    return VoiceEntryParser.amountIn(t)?.minor;
  }

  Map<String, Object?> exportSession({DateTime? now}) {
    _expire((now ?? DateTime.now()).toLocal());
    return {
      'version': 1,
      'consumedRequestIds': _settled.toList(growable: false),
      if (_draft?['action'] == 'create_entry' && _draftId != null)
        'draft': {
          'action': 'create_entry',
          'draftId': _draftId,
          'createdAt': _draftSince!.toIso8601String(),
          'args': Map<String, dynamic>.from(_draft!['args'] as Map),
          'trustedTurns': [
            for (var i = 0; i < _trustedTurns.length; i++)
              {'text': _trustedTurns[i], 'at': _turnTimes[i].toIso8601String()},
          ],
        },
    };
  }

  /// Restores a bounded draft, never a confirmation or executable capability.
  /// Even a complete restored draft requires a new trusted turn and UI review.
  bool restoreSession(
    Map<String, dynamic> json,
    FinanceData data, {
    DateTime? now,
  }) {
    cancel();
    _confirmationInFlight = false;
    final clock = (now ?? DateTime.now()).toLocal();
    try {
      _keys(json, {'version', 'consumedRequestIds', 'draft'});
      if (json['version'] != 1) return false;
      final consumed = json['consumedRequestIds'] ?? [];
      if (consumed is! List ||
          consumed.length > 100 ||
          consumed.any(
            (id) =>
                id is! String ||
                !RegExp(r'^[a-zA-Z0-9:_.-]{1,200}$').hasMatch(id),
          )) {
        return false;
      }
      _settled.addAll(consumed.cast<String>());
      while (_settled.length > 100) {
        _settled.remove(_settled.first);
      }
      final saved = json['draft'];
      if (saved == null) return true;
      if (saved is! Map<String, dynamic>) return false;
      _keys(saved, {'action', 'draftId', 'createdAt', 'args', 'trustedTurns'});
      if (saved['action'] != 'create_entry') return false;
      final id = saved['draftId'];
      final created = DateTime.tryParse('${saved['createdAt']}')?.toLocal();
      if (id is! String ||
          !RegExp(r'^[a-zA-Z0-9-]{12,80}$').hasMatch(id) ||
          created == null ||
          clock.isBefore(created) ||
          clock.difference(created) >= const Duration(minutes: 5) ||
          data.entries.any((e) => e.id == 'assistant:$id')) {
        return false;
      }
      final args = saved['args'];
      final turns = saved['trustedTurns'];
      if (args is! Map<String, dynamic> ||
          turns is! List ||
          turns.isEmpty ||
          turns.length > 8) {
        return false;
      }
      _keys(args, {
        'kind',
        'amountMinor',
        'accountId',
        'categoryId',
        'date',
        'payee',
      });
      for (final raw in turns) {
        if (raw is! Map<String, dynamic>) return false;
        _keys(raw, {'text', 'at'});
        final text = raw['text'];
        final at = DateTime.tryParse('${raw['at']}')?.toLocal();
        if (text is! String ||
            text.isEmpty ||
            text.length > 1200 ||
            prohibitsAction(text) ||
            at == null ||
            at.isBefore(created) ||
            at.isAfter(clock) ||
            _turnTimes.isNotEmpty && at.isBefore(_turnTimes.last)) {
          cancel();
          return false;
        }
        _trustedTurns.add(text);
        _turnTimes.add(at);
      }
      if (!_writeRequested(_normal(_trustedTurns.first))) {
        cancel();
        return false;
      }
      final kind = _kind(args, optional: true);
      _account(args, data, optional: true);
      _category(args, data, kind, optional: true);
      final amount = args['amountMinor'];
      if (amount != null &&
          (amount is! int ||
              amount <= 0 ||
              amount > FinanceEngine.maxMinor ||
              amount !=
                  _trustedTurns.reversed
                      .map((t) => _trustedAmountIn(t, data))
                      .whereType<int>()
                      .firstOrNull)) {
        cancel();
        return false;
      }
      if (args['date'] != null) {
        _date(_string(args, 'date')!, created, _trustedTurns.join('\n'));
      }
      _draft = {
        'action': 'create_entry',
        'args': Map<String, dynamic>.from(args),
      };
      _draftId = id;
      _draftSince = created;
      try {
        _validate(
          'create_entry',
          Map<String, dynamic>.from(args),
          data,
          clock,
          'restore-check',
          source: AiActionSource.restored,
        );
      } on _Clarify {
        /* Missing fields remain a draft, never an approval. */
      }
      _pending = null;
      return true;
    } catch (_) {
      cancel();
      return false;
    }
  }

  static bool _nameInText(String name, String text) {
    final words = _normal(text).split(RegExp(r'[^а-яa-z0-9]+'));
    final nameWords = _normal(
      name,
    ).split(RegExp(r'[^а-яa-z0-9]+')).where((w) => w.isNotEmpty).toList();
    if (nameWords.isEmpty) return false;
    return nameWords.every((word) {
      final russian = RegExp(r'^[а-я]+$').hasMatch(word);
      final stem = russian && word.length >= 5
          ? word.substring(0, word.length - (word.length >= 7 ? 2 : 1))
          : word;
      return words.any(
        (w) => w == word || (stem.length >= 4 && w.startsWith(stem)),
      );
    });
  }

  static bool _writeRequested(String text) =>
      !RegExp(
        r'^(?:почему|сколько|когда|зачем|как|что|откуда)(?:\s|[.!?,]|$)',
      ).hasMatch(text) &&
      !RegExp(
        r'^(?:комментарий|описание|цитата|инструкция)(?:\s|:)',
        caseSensitive: false,
      ).hasMatch(text) &&
      _writeIntent.hasMatch(
        text.replaceAll(RegExp(r'«[^»]*»|"[^"]*"|“[^”]*”'), ' '),
      );

  static bool _navigationRequested(String text) => RegExp(
    r'(^|\s)(?:открой|открыть|откроем|покажи|покажите|показать|перейди|перейти|переключи)(?:\s|$)',
  ).hasMatch(_normal(text));

  static bool _freshCreationRequested(String text) =>
      RegExp(
        r'^(?:добав[а-я]*|запиш[а-я]*|запис[а-я]*|расход|доход|потрат[а-я]*|купил[а-я]*|получ[а-я]*|оплат[а-я]*)(?:\s|$)',
      ).hasMatch(_normal(text)) &&
      VoiceEntryParser.amountIn(text) != null;

  static String? _relativeDateIn(String text) {
    final normal = _normal(text);
    if (RegExp(r'(^|\s)позавчера(?:\s|[.,!?]|$)').hasMatch(normal)) {
      return 'day_before_yesterday';
    }
    if (RegExp(r'(^|\s)вчера(?:\s|[.,!?]|$)').hasMatch(normal)) {
      return 'yesterday';
    }
    if (RegExp(r'(^|\s)сегодня(?:\s|[.,!?]|$)').hasMatch(normal)) {
      return 'today';
    }
    return null;
  }

  /// [text] without the words of account names (and the «с»/«со»/«из»
  /// before them) and the request verbs («добавь», «запиши»), for reading
  /// the place of an operation.
  static String _withoutAccounts(String text, FinanceData d) {
    final stems = <String>{
      for (final a in d.accounts)
        for (final w in a.name.toLowerCase().replaceAll('ё', 'е').split(
          RegExp(r'[^\p{L}\p{N}]+', unicode: true),
        ))
          if (w.length >= 4) w.substring(0, 4),
    };
    final verb = RegExp(
      r'^(?:добав|запиш|запис|потрат|оплат|спиш|спис)[а-я]*[,.!]?$',
    );
    final words = text.split(RegExp(r'\s+'));
    final out = <String>[];
    for (final w in words) {
      final k = w.toLowerCase().replaceAll('ё', 'е');
      if (verb.hasMatch(k)) continue;
      if (k.length >= 4 && stems.contains(k.substring(0, 4))) {
        if (out.isNotEmpty &&
            const {'с', 'со', 'из', 'на'}.contains(out.last.toLowerCase())) {
          out.removeLast();
        }
        continue;
      }
      out.add(w);
    }
    return out.join(' ');
  }

  static Category? _category(
    Map<String, dynamic> args,
    FinanceData d,
    EntryKind? kind, {
    bool optional = false,
  }) {
    final id = _string(args, 'categoryId');
    if (id == null) {
      if (optional) return null;
      throw const _Clarify('Какую категорию выбрать?');
    }
    final category = d.categories
        .where(
          (c) => c.id == id && !c.archived && (kind == null || c.kind == kind),
        )
        .firstOrNull;
    if (category == null) {
      throw const AiActionException(
        'Категория не найдена или не подходит типу операции.',
      );
    }
    return category;
  }

  static EntryKind? _kind(Map<String, dynamic> args, {bool optional = false}) {
    final value = _string(args, 'kind');
    if (value == null && optional) return null;
    if (value == null) throw const _Clarify('Это доход или расход?');
    return switch (value) {
      'expense' => EntryKind.expense,
      'income' => EntryKind.income,
      _ => throw const AiActionException(
        'Допустимы только доход и расход. Переводы открывайте обычной формой.',
      ),
    };
  }

  static DateTime _date(String value, DateTime now, String user) {
    final today = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final normal = _normal(user);
    final offset = switch (value) {
      'today' => 0,
      'yesterday' => 1,
      'day_before_yesterday' => 2,
      _ => null,
    };
    if (offset != null) {
      if (offset == 1 &&
              !RegExp(r'(^|\s)вчера(?:\s|[.,!?]|$)').hasMatch(normal) ||
          offset == 2 && !normal.contains('позавчера')) {
        throw const AiActionException(
          'Дата не подтверждается вашим сообщением.',
        );
      }
      // Calendar arithmetic preserves the user's local day across DST.
      return DateTime(
        today.year,
        today.month,
        today.day - offset,
        today.hour,
        today.minute,
      );
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null || !normal.contains(value)) {
      throw const AiActionException(
        'Укажите дату в формате ГГГГ-ММ-ДД или «вчера».',
      );
    }
    final date = DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      now.hour,
      now.minute,
    );
    if (date.year != int.parse(match[1]!) ||
        date.month != int.parse(match[2]!) ||
        date.day != int.parse(match[3]!)) {
      throw const AiActionException('Такой даты нет.');
    }
    return date;
  }

  static (DateTime, DateTime)? _range(
    String period,
    DateTime now,
    int weekStart,
  ) {
    final day = DateTime(now.year, now.month, now.day);
    return switch (period) {
      'all' => null,
      'today' => (day, day),
      'yesterday' => (
        DateTime(now.year, now.month, now.day - 1),
        DateTime(now.year, now.month, now.day - 1),
      ),
      'this_month' => (
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1, 0),
      ),
      'last_month' => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0),
      ),
      'this_week' => (
        DateTime(now.year, now.month, now.day - (now.weekday - weekStart) % 7),
        DateTime(
          now.year,
          now.month,
          now.day - (now.weekday - weekStart) % 7 + 6,
        ),
      ),
      _ => throw const AiActionException('Неизвестный период.'),
    };
  }

  static String? _string(
    Map<String, dynamic> map,
    String key, {
    bool required = false,
  }) {
    final value = map[key];
    if (value == null && !required) return null;
    if (value is! String || value.isEmpty || value.length > 200) {
      throw AiActionException('Некорректное поле «$key».');
    }
    return value;
  }

  static void _keys(Map<String, dynamic> map, Set<String> allowed) {
    if (map.keys.any((k) => !allowed.contains(k))) {
      throw const AiActionException('Команда содержит неизвестные поля.');
    }
  }

  static String _normal(String text) =>
      text.toLowerCase().replaceAll('ё', 'е').trim();
  static int _mentioned(String text, String name) =>
      text.contains(_normal(name)) ? 1 : 0;
  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static String _amount(int minor) =>
      '${minor ~/ 100},${(minor % 100).toString().padLeft(2, '0')}';
  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  static const _screenNames = {
    'home': 'Главная',
    'operations': 'Операции',
    'analytics': 'Аналитика',
    'settings': 'Настройки',
    'accounts': 'Счета',
    'goals': 'Мечты',
    'budgets': 'Бюджеты',
    'calendar': 'Календарь',
    'categories': 'Категории',
    'recurring': 'Регулярные платежи',
  };
  static const _periodNames = {
    'today': 'сегодня',
    'yesterday': 'вчера',
    'this_week': 'эта неделя',
    'this_month': 'этот месяц',
    'last_month': 'прошлый месяц',
    'all': 'всё время',
  };
}

class _Clarify implements Exception {
  const _Clarify(this.message);
  final String message;
}
