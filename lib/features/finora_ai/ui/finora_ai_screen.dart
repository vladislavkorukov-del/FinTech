import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/controller.dart';
import '../../../presentation/haptics.dart';
import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/common.dart' show showError;
import '../../../presentation/widgets/finora_orb.dart';
import '../../../presentation/widgets/profile_avatar.dart';
import '../../../services/voice_input_service.dart';
import '../responses/response_layer.dart';
import '../services/finora_ai.dart';
import '../services/finora_ai_snapshot.dart';
import '../widgets/ai_chat_widgets.dart';
import 'analysis_sheet.dart';

/// The Finora AI window: a welcome with suggestions and a big input, a
/// listening view with her orb, and a chat. Every answer is built from the
/// engines' facts (see [FinoraAi.answer]); the analysis sheet shows the same
/// facts without words.
class FinoraAiScreen extends StatefulWidget {
  const FinoraAiScreen({super.key, this.leading, this.embedded = false});

  /// Shown at the start of the header (the app menu when embedded).
  final Widget? leading;

  /// Part of the main shell (no back button of its own).
  final bool embedded;

  @override
  State<FinoraAiScreen> createState() => _FinoraAiScreenState();
}

enum _Mode { welcome, listening, chat }

class _FinoraAiScreenState extends State<FinoraAiScreen> {
  final _ai = FinoraAi.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <(String, bool)>[];
  late final Future<void> _ready = _ai.ready();
  _Mode _mode = _Mode.welcome;
  bool _thinking = false;
  String _heard = '';
  Object? _dataSeen;
  FinoraAiSnapshot? _snapshot;

  static const suggestions = [
    'Почему трачу больше?',
    'Прогноз до конца месяца',
    'Сколько останется?',
    'Мои подписки',
    'Уложусь в бюджеты?',
    'Предложи бюджет',
  ];

  @override
  void dispose() {
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
    final s = _snap(FinanceScope.of(context));
    Haptics.light();
    setState(() {
      _messages.add((text, true));
      _input.clear();
      _mode = _Mode.chat;
      _thinking = true;
    });
    // The facts are ready at once; a short beat reads as «thinking».
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    setState(() {
      _messages.add((_ai.answer(text, s).text, false));
      _thinking = false;
    });
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

  void _close() => setState(() {
    _messages.clear();
    _mode = _Mode.welcome;
    _thinking = false;
  });

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
    final first = s.insights.firstOrNull;
    return Column(
      key: const ValueKey('ai-welcome'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(s, chat: false),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * .12),
              const Text(
                'Чем займёмся\nсегодня?',
                style: TextStyle(
                  color: AiLook.ink,
                  fontSize: 36,
                  height: 1.08,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                first == null
                    ? ResponseLayer.notEnough
                    : ResponseLayer.insight(s, first),
                key: const ValueKey('finora-ai-headline'),
                style: TextStyle(
                  color: AiLook.soft(.72),
                  fontSize: 14.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 108,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
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
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: ShapeDecoration(
                        color: AiLook.soft(.08),
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.lock_shield,
                            size: 14,
                            color: AiLook.soft(.6),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Финора · на устройстве',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AiLook.soft(.7),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
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
    builder: (context, v, _) => v.text.trim().isEmpty
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
              if (_thinking)
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: Text(
                    'Финора считает…',
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
