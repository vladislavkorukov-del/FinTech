import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../../domain/flow/flow.dart';
import '../../../services/flow_audio.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import 'flow_board.dart';
import 'flow_dialogs.dart';
import 'flow_hud.dart';
import 'flow_screens.dart';
import 'world_components.dart';

class FlowGameScreen extends StatefulWidget {
  const FlowGameScreen({
    super.key,
    required this.level,
    required this.levels,
    this.onExitWorld,
    this.initialReward = 0,
  });
  final FlowLevel level;
  final List<FlowLevel> levels;
  final VoidCallback? onExitWorld;
  final int initialReward;
  @override
  State<FlowGameScreen> createState() => _FlowGameScreenState();
}

class _FlowGameScreenState extends State<FlowGameScreen>
    with WidgetsBindingObserver {
  int? _selected;
  FlowTool? _tool;
  bool _busy = false,
      _paused = false,
      _backgrounded = false,
      _navigating = false;
  String? _feedback;
  late int _earned = widget.initialReward;
  final _audio = FlowAudio();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_audio.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _backgrounded = state != AppLifecycleState.resumed;
      if (_backgrounded) {
        _paused = true;
        _selected = null;
        _tool = null;
      }
    });
    if (_backgrounded) {
      unawaited(
        _audio.configure(
          active: false,
          music: false,
          sound: false,
          haptics: false,
        ),
      );
    }
  }

  bool get _blocked => _busy || _paused || _backgrounded || _navigating;
  void _select(int cell) {
    if (_blocked) return;
    final session = FinanceScope.of(context).data.world.flow.session;
    if (session == null || session.finished) return;
    if (_tool != null) {
      unawaited(_applyTool(_tool!, cell: cell));
      return;
    }
    if (!session.board[cell].movable) {
      setState(() => _feedback = 'Эта клетка пока заблокирована');
      return;
    }
    final previous = _selected;
    if (previous == null || !FlowEngine.neighbors(previous, cell)) {
      setState(() => _selected = previous == cell ? null : cell);
    } else {
      unawaited(_exchange(previous, cell));
    }
  }

  Future<void> _exchange(int from, int to) async {
    if (_blocked || _tool != null) return;
    final c = FinanceScope.of(context);
    final session = c.data.world.flow.session;
    if (session == null || session.finished) return;
    setState(() {
      _busy = true;
      _selected = null;
      _feedback = null;
    });
    final sparks = c.data.world.sparks;
    try {
      final turn = await c.swapFlow(widget.level, session, from, to);
      if (!mounted) return;
      if (turn.accepted) {
        unawaited(_audio.effect(success: turn.session.finished));
      }
      setState(() {
        _earned += c.data.world.sparks - sparks;
        _feedback = turn.accepted
            ? turn.shuffled
                  ? 'Поле перемешано. Ход за перемешивание не потрачен.'
                  : null
            : 'Нет совпадения — ход сохранён';
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseTool(FlowTool tool) async {
    if (_blocked) return;
    if (FinanceScope.of(context).data.world.flow.available(tool) == 0) {
      await _stock(tool);
      return;
    }
    if (tool == FlowTool.hammer || tool == FlowTool.bomb) {
      setState(() {
        _tool = _tool == tool ? null : tool;
        _selected = null;
        _feedback = _tool == null
            ? null
            : 'Выберите клетку: ${flowToolName(tool).toLowerCase()}';
      });
    } else {
      await _applyTool(tool);
    }
  }

  Future<void> _applyTool(FlowTool tool, {int? cell}) async {
    if (_blocked) return;
    final c = FinanceScope.of(context);
    final session = c.data.world.flow.session;
    if (session == null || session.status == FlowStatus.won) return;
    if (c.data.world.flow.available(tool) == 0) {
      await _stock(tool);
      return;
    }
    setState(() => _busy = true);
    final sparks = c.data.world.sparks;
    try {
      final turn = await c.useFlowTool(widget.level, session, tool, cell: cell);
      if (!mounted) return;
      if (turn.accepted) unawaited(_audio.effect());
      setState(() {
        _earned += c.data.world.sparks - sparks;
        if (turn.accepted) {
          _tool = null;
          _selected = null;
          _feedback = null;
        } else {
          _feedback = 'Выберите другую клетку. Усилитель не потрачен.';
        }
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stock(FlowTool tool) async {
    final count = FinanceScope.of(context).data.world.flow.available(tool);
    await showDialog<void>(
      context: context,
      builder: (_) => WorldTheme(
        child: AlertDialog(
          title: Text(flowToolName(tool)),
          content: Text(
            'В запасе: $count.\n\nЭто ограниченный стартовый набор. Усилитель расходуется только при применении. Повтор уровня и перезапуск приложения не пополняют запас. Покупки, реклама и пополнение пока не подключены.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _preference(String key) async {
    if (_busy) return;
    final c = FinanceScope.of(context);
    final flow = c.data.world.flow;
    setState(() => _busy = true);
    try {
      await c.setFlowPreferences(
        music: key == 'music' ? !flow.music : null,
        sound: key == 'sound' ? !flow.sound : null,
        haptics: key == 'haptics' ? !flow.haptics : null,
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replay({bool confirmRestart = false}) async {
    if (_busy || _navigating) return;
    setState(() => _busy = true);
    try {
      if (confirmRestart) {
        final accepted = await confirm(
          context,
          'Начать заново?',
          'Текущая попытка будет заменена. Уже потраченные усилители не возвращаются.',
        );
        if (!accepted || !mounted) return;
      }
      final c = FinanceScope.of(context),
          sparks = FinanceScope.of(context).data.world.sparks;
      await c.startFlow(widget.level, restart: true);
      if (mounted) {
        setState(() {
          _selected = null;
          _tool = null;
          _feedback = null;
          _paused = false;
          _earned = c.data.world.sparks - sparks;
        });
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() {
    if (_busy || _navigating) return;
    setState(() => _navigating = true);
    unawaited(_audio.close());
    Navigator.of(context).pop();
  }

  void _next(FlowLevel next) {
    if (_busy || _navigating) return;
    setState(() => _navigating = true);
    unawaited(_audio.close());
    Navigator.of(context).pushReplacement<void, void>(
      flowPreparationRoute(
        context,
        next,
        widget.levels,
        onExitWorld: widget.onExitWorld,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = FinanceScope.of(context).data.world.flow;
    final session = flow.session;
    if (session == null || session.levelId != widget.level.id) {
      return WorldPage(
        title: 'Finora — Поток',
        children: [
          const EmptyState(
            'Попытка недоступна',
            'Выберите уровень, чтобы начать игру.',
          ),
          FilledButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('К уровням'),
          ),
        ],
      );
    }
    final modal = _paused || _backgrounded || session.finished;
    unawaited(
      _audio.configure(
        active:
            !modal && !_navigating && (ModalRoute.isCurrentOf(context) ?? true),
        music: flow.music,
        sound: flow.sound,
        haptics: flow.haptics,
      ),
    );
    final next = widget.levels
        .where((level) => level.id == widget.level.id + 1)
        .firstOrNull;
    return WorldTheme(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: PopScope(
          canPop: session.finished || _navigating,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !_busy) {
              setState(() {
                _paused = !_paused;
                _selected = null;
                _tool = null;
              });
            }
          },
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    WorldArt.background('garden').asset,
                    fit: BoxFit.cover,
                    cacheWidth: 960,
                    excludeFromSemantics: true,
                  ),
                ),
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xBDDEDCE7)),
                ),
                ExcludeSemantics(
                  excluding: modal,
                  child: AbsorbPointer(
                    absorbing: modal || _busy,
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final landscape = box.maxWidth > box.maxHeight;
                          final hud = FlowTopHud(
                            level: widget.level,
                            session: session,
                            onPause: () => setState(() {
                              _paused = true;
                              _selected = null;
                              _tool = null;
                            }),
                          );
                          final tools = FlowBottomTools(
                            flow: flow,
                            selected: _tool,
                            enabled: !_blocked && !session.finished,
                            onUse: (tool) => unawaited(_chooseTool(tool)),
                            onMore: (tool) => unawaited(_stock(tool)),
                            columns: landscape ? 2 : 4,
                          );
                          Widget board(double side) => Center(
                            child: SizedBox.square(
                              dimension: math.max(80, side),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4EDF5),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFD4B592),
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x324B2346),
                                      blurRadius: 14,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: FlowBoard(
                                    session: session,
                                    selected: _selected,
                                    enabled: !_blocked && !session.finished,
                                    onSelect: _select,
                                    onExchange: (from, to) =>
                                        unawaited(_exchange(from, to)),
                                  ),
                                ),
                              ),
                            ),
                          );
                          if (landscape) {
                            return Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: box.maxWidth * .25,
                                    child: SingleChildScrollView(child: hud),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (_, center) => board(
                                        math.min(
                                          center.maxWidth,
                                          center.maxHeight,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: box.maxWidth * .25,
                                    child: SingleChildScrollView(child: tools),
                                  ),
                                ],
                              ),
                            );
                          }
                          final hudHeight =
                              (box.maxWidth * .28).clamp(58.0, 106.0) + 100;
                          final boardSize = math.min(
                            box.maxWidth - 20,
                            box.maxHeight - hudHeight - 132,
                          );
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                            child: Column(
                              children: [
                                hud,
                                const SizedBox(height: 6),
                                Expanded(child: board(boardSize)),
                                if (_feedback != null)
                                  SizedBox(
                                    height: 22,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _feedback!,
                                        style: const TextStyle(
                                          color: flowInk,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_busy)
                                  const SizedBox(
                                    height: 2,
                                    child: LinearProgressIndicator(),
                                  ),
                                tools,
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (modal)
                  Positioned.fill(
                    child: _paused || _backgrounded
                        ? FlowOverlay(
                            art: 'pause_panel_base',
                            child: FlowPauseContent(
                              flow: flow,
                              busy: _busy || _backgrounded,
                              onContinue: () => setState(() => _paused = false),
                              onRestart: () =>
                                  unawaited(_replay(confirmRestart: true)),
                              onExit: _leave,
                              onMusic: () => unawaited(_preference('music')),
                              onSound: () => unawaited(_preference('sound')),
                              onHaptics: () =>
                                  unawaited(_preference('haptics')),
                            ),
                          )
                        : session.status == FlowStatus.won
                        ? FlowOverlay(
                            art: 'victory_panel_base',
                            child: FlowVictoryContent(
                              level: widget.level,
                              session: session,
                              reward: _earned,
                              busy: _busy || _navigating,
                              onLevels: _leave,
                              onReplay: () => unawaited(_replay()),
                              onExitWorld: widget.onExitWorld,
                              onNext: next != null && flow.isUnlocked(next.id)
                                  ? () => _next(next)
                                  : null,
                            ),
                          )
                        : FlowOverlay(
                            child: FlowLossContent(
                              level: widget.level,
                              session: session,
                              stock: flow.available(FlowTool.extraMoves),
                              busy: _busy || _navigating,
                              onExtraMoves: () =>
                                  unawaited(_applyTool(FlowTool.extraMoves)),
                              onRestart: () => unawaited(_replay()),
                              onLevels: _leave,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
