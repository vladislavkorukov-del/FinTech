import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/controller.dart';
import '../../../presentation/haptics.dart';
import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/common.dart' show showError;
import '../../../presentation/widgets/finora_orb.dart';
import '../../../presentation/widgets/profile_avatar.dart';
import '../../../services/voice_input_service.dart';
import '../services/finora_ai.dart';
import '../memory/personal_memory.dart';
import '../actions/ai_actions.dart';
import '../actions/ai_action_executor.dart';
import '../local_model/assistant_history.dart';
import '../local_model/assistant_diagnostics.dart';
import '../local_model/local_assistant.dart';
import '../local_model/local_runtime.dart';
import '../local_model/model_protocol.dart';
import '../local_model/qwen_chat.dart';
import 'local_model_screen.dart';
import '../memory/assistant_preferences.dart';
import '../../../services/user_error.dart';
import '../../../presentation/widgets/grouped_list.dart' show confirmWithFinora;
import '../services/finora_ai_snapshot.dart';
import '../widgets/ai_chat_widgets.dart';
import 'analysis_sheet.dart';

/// The Finora AI window: a welcome with suggestions and a big input, a
/// listening view with her orb, and a chat. Every answer is built from the
/// engines' facts (see [FinoraAi.answer]); the analysis sheet shows the same
/// facts without words.
class FinoraAiScreen extends StatefulWidget {
  const FinoraAiScreen({
    super.key,
    this.leading,
    this.embedded = false,
    this.initialQuestion,
    this.onTab,
  });

  /// Shown at the start of the header (the app menu when embedded).
  final Widget? leading;

  /// Part of the main shell (no back button of its own).
  final bool embedded;

  /// Asked as soon as the window is ready (from Settings → «Finora AI»).
  final String? initialQuestion;
  final void Function(int)? onTab;

  @override
  State<FinoraAiScreen> createState() => _FinoraAiScreenState();
}

enum _Mode { welcome, listening, chat }

class _FinoraAiScreenState extends State<FinoraAiScreen> {
  final _ai = FinoraAi.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <(String, bool)>[];
  final _history = AssistantHistory();
  final _local = LocalAssistant.instance;
  final _actions = AiActionSession();
  final _qwen = QwenChat();
  late final Future<void> _ready = _prepare();
  AiPendingAction? _pendingAction;
  int _generation = 0;
  String _streamed = '';
  String _status = '';
  bool _historyWritable = true;
  List<ScenarioStep> _lastScenarioSteps = [];

  Future<void> _prepare() async {
    await _ai.ready();
    await _local.ready();
    try {
      final old = await _history.load();
      if (mounted) {
        _actions.primaryAccountId = _ai.memory.preferences.primaryAccountId;
        final restored = _history.session;
        if (restored != null) {
          _actions.restoreSession(restored, FinanceScope.of(context).data);
        }
        if (_actions.unfinishedAction != null) {
          _status =
              'Можно продолжить недавнее уточнение. Подтверждение потребуется заново.';
        }
      }
      if (mounted && old.isNotEmpty) {
        setState(() {
          _messages.addAll(old);
          _mode = _Mode.chat;
        });
      }
    } catch (_) {
      _historyWritable = false;
      // Preserve a damaged history file rather than silently replacing it.
      if (mounted) {
        setState(
          () => _status = 'История чата не прочитана. Исходный файл сохранён.',
        );
      }
    }
  }

  Future<void> _saveHistory({bool requireSuccess = false}) async {
    if (!_historyWritable) {
      if (requireSuccess) {
        throw const FormatException(
          'Не удалось сохранить подтверждение. Действие не запущено.',
        );
      }
      return;
    }
    try {
      await _history.save(_messages, session: _actions.exportSession());
    } catch (_) {
      if (requireSuccess) {
        throw const FormatException(
          'Не удалось сохранить подтверждение. Действие не запущено.',
        );
      }
      if (mounted) {
        setState(() => _status = 'Не удалось сохранить историю чата.');
      }
    }
  }

  void _stop() {
    _generation++;
    _actions.cancel();
    _pendingAction = null;
    unawaited(_local.runtime.cancel().catchError((Object _) {}));
    if (mounted) {
      setState(() {
        _thinking = false;
        _streamed = '';
        _status = 'Ответ остановлен.';
      });
    }
    AssistantDiagnostics.instance.record('cancelled');
    unawaited(_saveHistory());
  }

  _Mode _mode = _Mode.welcome;
  bool _thinking = false;
  String _heard = '';
  Object? _dataSeen;
  FinoraAiSnapshot? _snapshot;

  static const suggestions = [
    'Что ты умеешь?',
    'Почему трачу больше?',
    'Прогноз до конца месяца',
    'Сколько останется?',
    'Мои подписки',
    'Недельный разбор',
    'Составь план погашения долгов',
    'Уложусь в бюджеты?',
    'Предложи бюджет',
  ];

  @override
  void initState() {
    super.initState();
    _local.addListener(_localChanged);
    final q = widget.initialQuestion;
    if (q != null) {
      // After the first frame: the window is built and can show the chat.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          _ready.then((_) {
            if (mounted) unawaited(_ask(q));
          }),
        );
      });
    }
  }

  void _localChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    _actions.cancel();
    _local.removeListener(_localChanged);
    unawaited(_local.runtime.unload().catchError((Object _) {}));
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  FinoraAiSnapshot _snap(FinanceController c) {
    if (!identical(_dataSeen, c.data) || _snapshot == null) {
      _dataSeen = c.data;
      _snapshot = _ai.snapshot(c.data);
    }
    return _snapshot!;
  }

  Future<void> _ask(String q) async {
    final text = q.trim();
    if (text.isEmpty || _thinking) return;
    final c = FinanceScope.of(context);
    final s = _snap(c);
    final previous = List<(String, bool)>.of(_messages);
    final generation = ++_generation;
    final requestId =
        'chat-${DateTime.now().microsecondsSinceEpoch}-$generation';
    bool current() => mounted && generation == _generation;
    _actions.primaryAccountId = _ai.memory.preferences.primaryAccountId;
    _actions.beginUserTurn(text);
    Haptics.light();
    setState(() {
      _messages.add((text, true));
      _input.clear();
      _mode = _Mode.chat;
      _thinking = true;
      _pendingAction = null;
      _streamed = '';
      _status = '';
    });
    unawaited(_saveHistory());
    String answer;
    var requestedModel = false;
    try {
      final saveScenario = RegExp(
        r'^(сохрани|сохранить).*(разбор|сценари|обзор)',
        caseSensitive: false,
      ).hasMatch(text);
      final phase4Command = RegExp(
        r'план.*долг|долг.*план|распредели|недельн.*(разбор|обзор)|(разбор|обзор).*недел|предпочтени|память|сценари',
        caseSensitive: false,
      ).hasMatch(text);
      final preferFacts = QwenChat.preferFacts(text) && !phase4Command;
      if (!saveScenario) _lastScenarioSteps = [];
      final deterministic = preferFacts
          ? null
          : _actions.resolveDeterministic(
              text,
              data: c.data,
              requestId: requestId,
            );
      if (saveScenario && !AiActionSession.prohibitsAction(text)) {
        answer = await _saveLastScenario();
      } else if (AiActionSession.prohibitsAction(text)) {
        _actions.cancel();
        answer = 'Действие отменено. Ничего не изменено.';
      } else if (deterministic != null) {
        _pendingAction = deterministic.pending;
        answer = deterministic.message;
      } else if (preferFacts) {
        _actions.cancel();
        // Existing deterministic answers bypass the model and retain exact
        // amounts, forecasts and confidence/empty-history limitations.
        answer = _ai.answer(text, s).text;
      } else if (_local.canGenerate && _local.store?.installedPath != null) {
        requestedModel = true;
        setState(() => _status = 'Загрузка локальной модели…');
        final envelope = await _qwen.ask(
          id: requestId,
          path: _local.store!.installedPath!,
          query: text,
          actionSchema: AiActionSession.promptSchema,
          objectContext: jsonEncode(_actions.context(c.data, text)),
          memory: c.data.preferences.ai.personalization
              ? _ai.memory
              : PersonalMemory(),
          history: previous,
          isCurrent: () => current() && _local.canGenerate,
          onText: (value) {
            if (current()) {
              setState(() {
                _streamed = value;
                _status = '';
              });
            }
          },
        );
        if (!current()) return;
        switch (envelope.kind) {
          case 'fact':
            answer = QwenChat.answerFact(
              envelope.data['intent'] as String,
              _snap(c),
              query: text,
            );
          case 'action':
            final resolution = _actions.resolve(
              jsonEncode({
                'action': envelope.data['action'],
                'args': envelope.data['args'],
              }),
              userText: text,
              data: c.data,
              requestId: requestId,
            );
            _pendingAction = resolution.pending;
            answer = resolution.message;
          default:
            final value = envelope.data['text'] as String;
            answer = safeSmallTalk(value) && value.trim().isNotEmpty
                ? value
                : 'Для точных финансовых данных выберите вопрос из раздела «Анализ». Какой показатель вас интересует?';
        }
      } else {
        answer = _ai.answer(text, s).text;
        if (answer.startsWith('Такого я пока')) {
          answer +=
              '\nСвободный диалог доступен после установки и включения Qwen в настройках ассистента.';
        }
      }
    } on ModelCancelled {
      if (current()) _stop();
      return;
    } catch (e) {
      if (!current()) return;
      _actions.cancel();
      _pendingAction = null;
      // Failure is local. Never send the request to a cloud provider.
      answer = requestedModel
          ? 'Локальная модель не завершила ответ. Базовый режим доступен. ${QwenChat.isKnownQuestion(text) ? _ai.answer(text, s).text : 'Попробуйте короткий вопрос или откройте «Анализ».'}'
          : userErrorMessage(e);
      AssistantDiagnostics.instance.record(
        'fallback',
        values: {'errorType': e.runtimeType.toString()},
      );
    }
    if (!current()) return;
    setState(() {
      _messages.add((answer, false));
      _streamed = '';
      _status = '';
      _thinking = false;
    });
    AssistantDiagnostics.instance.record('visible_answer', visibleText: answer);
    unawaited(_saveHistory());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  Future<void> _executePending() async {
    final action = _pendingAction;
    if (action == null || _thinking) return;
    final generation = ++_generation;
    setState(() {
      _pendingAction = null;
      _thinking = true;
    });
    try {
      final result = await _actions.run(
        context,
        action,
        onTab: widget.onTab,
        onConsumed: () => _saveHistory(requireSuccess: true),
        isCurrent: () => mounted && generation == _generation,
      );
      if (action.kind == AiActionKind.reviewWeek &&
          _actions.isConsumed(action.requestId) &&
          generation == _generation) {
        _lastScenarioSteps = [
          ScenarioStep(
            type: ScenarioStepType.summary,
            parameters: {'period': 'week'},
          ),
        ];
      }
      if (!mounted) return;
      setState(
        () => _messages.add((
          generation == _generation
              ? result
              : 'Результат ранее подтверждённого действия: $result',
          false,
        )),
      );
      AssistantDiagnostics.instance.record(
        'action_result',
        values: {'action': action.kind.name},
        visibleText: result,
      );
      unawaited(_saveHistory());
    } catch (e) {
      if (mounted) showError(context, e);
      AssistantDiagnostics.instance.record(
        'action_error',
        values: {
          'action': action.kind.name,
          'errorType': e.runtimeType.toString(),
        },
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _thinking = false);
      }
    }
  }

  Future<String> _saveLastScenario() async {
    _actions.cancel();
    if (_lastScenarioSteps.isEmpty) {
      return 'Сначала выполните недельный разбор. План погашения можно сохранить как сценарий на экране его черновика.';
    }
    final sure = await confirmWithFinora(
      context,
      title: 'Сохранить недельный разбор?',
      message:
          'Сценарий будет заново получать актуальные данные при вашем запуске. Автозапуск по расписанию не включается.',
      action: 'Сохранить',
    );
    if (!sure || !mounted) return 'Сценарий не сохранён.';
    await _ai.memoryRepository.saveScenario(
      SavedAssistantScenario(
        id: 'weekly-review',
        name: 'Недельный разбор',
        steps: List.of(_lastScenarioSteps),
        updatedAt: DateTime.now(),
      ),
    );
    AssistantDiagnostics.instance.record(
      'scenario_saved',
      values: {'steps': _lastScenarioSteps.length},
    );
    return 'Сценарий «Недельный разбор» сохранён. Просмотр, запуск и изменение — в предпочтениях ассистента.';
  }

  Future<void> _listen() async {
    final back = _mode;
    setState(() {
      _mode = _Mode.listening;
      _heard = '';
    });
    try {
      final heard = await const VoiceInputService().listen(
        prompt: 'Спросите Финору о деньгах',
      );
      if (!mounted) return;
      if (heard.isEmpty) {
        setState(() => _mode = back);
        return;
      }
      setState(() => _heard = heard.first);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) await _ask(_heard);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _mode = back);
      showError(context, e);
    }
  }

  void _close() {
    _stop();
    setState(() {
      _mode = _Mode.welcome;
      _status = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    // Its own block: orange in every theme.
    const accent = AiLook.orange;
    final body = FutureBuilder<void>(
      future: _ready,
      builder: (context, done) {
        if (done.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final s = _snap(c);
        return SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            child: switch (_mode) {
              _Mode.welcome => _welcome(s, accent),
              _Mode.listening => _listening(accent),
              _Mode.chat => _chat(accent),
            },
          ),
        );
      },
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: AiBackdrop(key: const ValueKey('finora-ai'), child: body),
    );
  }

  Widget _header(FinoraAiSnapshot s, {required bool chat}) {
    final name = FinanceScope.of(context).data.preferences.userName.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 0),
      child: Row(
        children: [
          if (!widget.embedded)
            IconButton(
              tooltip: 'Назад',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(CupertinoIcons.back, color: Colors.white),
            )
          else if (widget.leading != null)
            widget.leading!,
          if (!chat) ...[
            const SizedBox(width: 4),
            const ProfileAvatar(size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Финора' : name,
                    style: TextStyle(color: AiLook.soft(.6), fontSize: 12.5),
                  ),
                  const Text(
                    'С возвращением',
                    style: TextStyle(color: AiLook.ink, fontSize: 15),
                  ),
                ],
              ),
            ),
          ] else
            Expanded(
              child: Center(
                child: GlassPill(
                  key: const ValueKey('finora-ai-close'),
                  label: 'Закрыть чат',
                  icon: CupertinoIcons.xmark,
                  onTap: _close,
                ),
              ),
            ),
          GlassIconButton(
            key: const ValueKey('finora-ai-analysis'),
            icon: CupertinoIcons.chart_bar_square,
            tooltip: 'Анализ',
            onTap: () => showAnalysisSheet(
              context,
              s,
              onChanged: () => setState(() => _snapshot = null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcome(FinoraAiSnapshot s, Color accent) {
    return Column(
      key: const ValueKey('ai-welcome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(s, chat: false),
        // Just a quiet question in the middle.
        Expanded(
          child: Center(
            child: Text(
              'Чем могу помочь?',
              key: const ValueKey('finora-ai-headline'),
              style: TextStyle(
                color: AiLook.soft(.92),
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: -.2,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SuggestionCard(
              text: suggestions[i],
              accent: accent,
              onTap: () => _ask(suggestions[i]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _composer(accent, big: true),
      ],
    );
  }

  /// The model picker, as in chat apps: FinAI 1.0 is the one model, local
  /// and offline; cloud models are not connected.
  Future<void> _models() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A0E0A),
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(
                'Модель',
                style: TextStyle(
                  color: AiLook.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              key: const ValueKey('finora-ai-model-finai'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: AiLook.orange.withValues(alpha: .14),
              leading: const Icon(
                CupertinoIcons.sparkles,
                color: AiLook.orange,
              ),
              title: const Text(
                'FinAI 1.0',
                style: TextStyle(
                  color: AiLook.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'На устройстве · без интернета · считает по вашим операциям',
                style: TextStyle(color: AiLook.soft(.6), fontSize: 12.5),
              ),
              trailing: const Icon(
                CupertinoIcons.checkmark_alt,
                color: AiLook.orange,
              ),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
            ListTile(
              onTap: () {
                Navigator.pop(context);
                Navigator.of(this.context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LocalModelScreen(),
                  ),
                );
              },
              leading: const Icon(
                CupertinoIcons.device_phone_portrait,
                color: AiLook.orange,
              ),
              title: const Text(
                'Локальная Qwen',
                style: TextStyle(color: AiLook.ink),
              ),
              subtitle: Text(
                'Скачать, включить или удалить модель',
                style: TextStyle(color: AiLook.soft(.35), fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _composer(Color accent, {required bool big}) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
    child: Container(
      padding: EdgeInsets.fromLTRB(18, big ? 14 : 6, 10, big ? 10 : 6),
      decoration: ShapeDecoration(
        color: AiLook.panel(.34),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(big ? 26 : 22),
          side: BorderSide(color: AiLook.soft(.08)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('finora-ai-question'),
                  controller: _input,
                  minLines: big ? 2 : 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _ask,
                  style: const TextStyle(color: AiLook.ink, fontSize: 15.5),
                  cursorColor: accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    hintText: 'Спросите Финору о деньгах',
                    hintStyle: TextStyle(color: AiLook.soft(.42)),
                  ),
                ),
              ),
              if (!big) ...[const SizedBox(width: 6), _sendOrMic(accent)],
            ],
          ),
          if (big) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                // The active model, tappable like a model picker.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: accent.withValues(alpha: .18),
                      shape: StadiumBorder(
                        side: BorderSide(color: accent.withValues(alpha: .55)),
                      ),
                      child: InkWell(
                        key: const ValueKey('finora-ai-model'),
                        customBorder: const StadiumBorder(),
                        onTap: () {
                          Haptics.light();
                          _models();
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.sparkles,
                                size: 14,
                                color: accent,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _local.label,
                                  style: const TextStyle(
                                    color: AiLook.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                CupertinoIcons.chevron_down,
                                size: 12,
                                color: AiLook.soft(.75),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _sendOrMic(accent),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _sendOrMic(Color accent) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _input,
    builder: (context, v, _) => _thinking
        ? IconButton(
            key: const ValueKey('finora-ai-stop'),
            tooltip: 'Остановить ответ',
            onPressed: _stop,
            icon: Icon(Icons.stop_circle_outlined, color: accent),
          )
        : v.text.trim().isEmpty
        ? MicButton(
            key: const ValueKey('finora-ai-mic'),
            accent: accent,
            onTap: _listen,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AiLook.accent(),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: .45), blurRadius: 18),
              ],
            ),
            child: IconButton(
              key: const ValueKey('finora-ai-send'),
              onPressed: () => _ask(_input.text),
              icon: const Icon(CupertinoIcons.arrow_up, color: Colors.white),
            ),
          ),
  );

  Widget _listening(Color accent) => Column(
    key: const ValueKey('ai-listening'),
    children: [
      const SizedBox(height: 10),
      GlassPill(
        label: 'Закрыть',
        icon: CupertinoIcons.xmark,
        onTap: () => setState(
          () => _mode = _messages.isEmpty ? _Mode.welcome : _Mode.chat,
        ),
      ),
      const Spacer(),
      const FinoraCharacter(
        size: 190,
        moods: [FinoraMood.attention, FinoraMood.happy],
      ),
      const SizedBox(height: 16),
      Text(
        'Финора слушает…',
        style: TextStyle(color: AiLook.soft(.5), fontSize: 12.5),
      ),
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ShaderMask(
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white.withValues(alpha: .35)],
          ).createShader(r),
          child: Text(
            _heard.isEmpty
                ? 'Спросите, например: «сколько останется?»'
                : _heard,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      const Spacer(),
      Padding(
        padding: const EdgeInsets.only(bottom: 26),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.pause_circle, color: AiLook.soft(.5)),
            const SizedBox(width: 40),
            MicButton(accent: accent, onTap: () {}, size: 62, ring: true),
            const SizedBox(width: 40),
            Icon(CupertinoIcons.paperplane, color: AiLook.soft(.5)),
          ],
        ),
      ),
    ],
  );

  Widget _chat(Color accent) {
    final s = _snap(FinanceScope.of(context));
    return Column(
      key: const ValueKey('ai-chat'),
      children: [
        _header(s, chat: true),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            children: [
              for (var i = 0; i < _messages.length; i++)
                ChatMessage(
                  key: ValueKey(
                    _messages[i].$2
                        ? 'finora-ai-question-$i'
                        : 'finora-ai-answer-${i ~/ 2}',
                  ),
                  text: _messages[i].$1,
                  mine: _messages[i].$2,
                  accent: accent,
                ),
              if (_streamed.isNotEmpty)
                ChatMessage(text: _streamed, mine: false, accent: accent),
              if (_pendingAction != null)
                FilledButton.tonal(
                  onPressed: _executePending,
                  child: const Text('Проверить действие'),
                ),
              if (_thinking || _status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: Text(
                    _status.isNotEmpty ? _status : 'Финора отвечает…',
                    style: TextStyle(color: AiLook.soft(.45), fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
        _composer(accent, big: false),
      ],
    );
  }
}
