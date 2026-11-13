import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart';

import '../../../../domain/finorio/finorio.dart';
import '../../../../services/finorio_store.dart';
import '../../../controller.dart';
import '../../../l10n_widgets.dart';
import 'finorio_art.dart';
import 'finorio_names.dart';
import 'finorio_painter.dart';
import 'finorio_inspector.dart';
import 'finorio_panels.dart';
import 'finorio_sheets.dart';

enum FinTool { select, build, remove }

/// Finorio: the factory game inside Finora's world. The simulation runs in
/// fixed 100 ms steps however fast the screen draws; it stops while the
/// app is in the background or the menu is open, and is saved then.
class FinorioScreen extends StatefulWidget {
  const FinorioScreen({super.key, this.store, this.seed});

  /// Where the game is saved (tests pass a temporary folder).
  final FinorioStore? store;

  /// The seed for a new map; random when null.
  final int? seed;

  @override
  State<FinorioScreen> createState() => FinorioScreenState();
}

class FinorioScreenState extends State<FinorioScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final FinorioStore _store = widget.store ?? FinorioStore();
  FinWorld? world;
  FinCamera? _camera;
  FinTerrainCache? _cache;
  final overlay = FinOverlay();

  late final Ticker _ticker = createTicker(_onFrame);
  Duration _last = Duration.zero;
  double _acc = 0;
  bool _menu = false, _background = false, _claiming = false;
  Timer? _autosave;

  /// Every frame (repaints the map) and every tick (refreshes panels).
  final frame = ValueNotifier(0), ticks = ValueNotifier(0);

  FinTool tool = FinTool.select;
  FinBuilding? building;
  int dir = 1;
  int? inspected;
  String? _message;
  Timer? _messageTimer;

  bool get running => world != null && !_menu && !_background;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    final loaded = await _store.load();
    if (!mounted) return;
    final w =
        loaded ??
        FinWorld.start(widget.seed ?? math.Random().nextInt(0x7ffffff0) + 1);
    setState(() {
      world = w;
      _camera = FinCamera(w.cameraX, w.cameraY, w.zoom);
      _cache = FinTerrainCache(w.terrain);
    });
    _ticker.start();
    _autosave = Timer.periodic(const Duration(seconds: 30), (_) => save());
    _claimRewards();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away == _background) return;
    _background = away;
    if (away) unawaited(save()); // the world waits while the app is away
  }

  void _onFrame(Duration elapsed) {
    final w = world;
    if (w == null) return;
    final dt = (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    if (!running) return;
    // At most a quarter second at once: a long frame never floods ticks.
    _acc = math.min(_acc + dt, 250);
    var steps = 0;
    while (_acc >= FinRules.tickMs) {
      w.step();
      _acc -= FinRules.tickMs;
      steps++;
    }
    if (steps > 0) {
      ticks.value++;
      if (w.tick % 10 < steps) _claimRewards();
    }
    frame.value++;
  }

  /// Hands earned rewards to the shared world wallet, once each.
  void _claimRewards() {
    final w = world;
    if (w == null || _claiming) return;
    final fresh = w.earnedRewards
        .where((id) => !w.claimed.contains(id))
        .toList();
    if (fresh.isEmpty) return;
    final scope = FinanceScope.maybeOf(context);
    if (scope == null) return;
    _claiming = true;
    scope
        .claimFinorioRewards(fresh)
        .then((_) {
          w.claimed.addAll(fresh);
          if (mounted) setState(() {});
        })
        .catchError((Object _) {})
        .whenComplete(() => _claiming = false);
  }

  Future<void> save() async {
    final w = world, cam = _camera;
    if (w == null || cam == null) return;
    w
      ..cameraX = cam.x
      ..cameraY = cam.y
      ..zoom = cam.zoom;
    try {
      await _store.save(w);
    } on Object {
      if (mounted) say('Не удалось сохранить игру');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave?.cancel();
    _messageTimer?.cancel();
    _ticker.dispose();
    _cache?.dispose();
    frame.dispose();
    ticks.dispose();
    unawaited(save());
    super.dispose();
  }

  /// Moves the camera to a cell at zoom 1.
  void centerOn(int x, int y) {
    final cam = _camera;
    if (cam == null) return;
    cam
      ..x = x + .5
      ..y = y + .5
      ..zoom = 1;
    frame.value++;
  }

  /// Where the camera looks, in cells.
  double get cameraX => _camera?.x ?? 0;
  double get cameraY => _camera?.y ?? 0;

  /// The camera's current zoom (for tests and the HUD).
  double get zoom => _camera?.zoom ?? 1;

  /// Panels change the screen's state through this.
  void update(VoidCallback change) => setState(change);

  void say(String text) {
    _messageTimer?.cancel();
    setState(() => _message = text);
    _messageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _message = null);
    });
  }

  void changed() {
    world?.checkTasks();
    ticks.value++;
    frame.value++;
    setState(() {});
  }

  // ------------------------------------------------------------- gestures

  Offset? _focalStart;
  double _zoomStart = 1;
  Offset _worldStart = Offset.zero;

  void _scaleStart(ScaleStartDetails d, Size size) {
    final cam = _camera!;
    _focalStart = d.localFocalPoint;
    _zoomStart = cam.zoom;
    _worldStart = cam.toWorld(d.localFocalPoint, size);
  }

  void _scaleUpdate(ScaleUpdateDetails d, Size size) {
    final cam = _camera!, w = world!;
    if (_focalStart == null) return;
    cam.zoom = (_zoomStart * d.scale).clamp(
      FinCamera.minZoom,
      FinCamera.maxZoom,
    );
    // The point under the fingers stays under them.
    cam.x =
        (_worldStart.dx - (d.localFocalPoint.dx - size.width / 2) / cam.scale)
            .clamp(0, w.terrain.width.toDouble());
    cam.y =
        (_worldStart.dy - (d.localFocalPoint.dy - size.height / 2) / cam.scale)
            .clamp(0, w.terrain.height.toDouble());
    frame.value++;
  }

  (int, int) _cellAt(Offset p, Size size) {
    final wp = _camera!.toWorld(p, size);
    return (wp.dx.floor(), wp.dy.floor());
  }

  /// A tap acts (never a drag: moving the map can never build).
  void tapCell(int x, int y) {
    final w = world!;
    if (!w.terrain.inside(x, y)) return;
    final m = w.machineAt(x, y);
    switch (tool) {
      case FinTool.select:
        setState(() {
          overlay.selectedX = x;
          overlay.selectedY = y;
          inspected = m?.id;
        });
      case FinTool.remove:
        if (m == null) return;
        w.remove(m.id);
        if (inspected == m.id) inspected = null;
        say(
          '${FinNames.building(m.kind)}: разобрано, всё вернулось в инвентарь',
        );
        changed();
      case FinTool.build:
        final kind = building;
        if (kind == null) return;
        if (kind == FinBuilding.belt || kind == FinBuilding.fastBelt) {
          if (overlay.beltStartX == null) {
            setState(() {
              overlay.beltStartX = x;
              overlay.beltStartY = y;
            });
            say('Коснитесь клетки, где линия закончится');
            return;
          }
          final placed = w.placeBeltLine(
            overlay.beltStartX!,
            overlay.beltStartY!,
            x,
            y,
            kind: kind,
          );
          overlay
            ..beltStartX = null
            ..beltStartY = null
            ..beltPreview = const [];
          say(
            placed > 0
                ? 'Конвейер: $placed клеток'
                : 'Линия упирается в препятствие',
          );
          changed();
          return;
        }
        final why = w.whyNot(kind, x, y);
        if (why != null) {
          say(why);
          return;
        }
        w.place(kind, x, y, dir: dir);
        overlay
          ..selectedX = x
          ..selectedY = y;
        changed();
    }
  }

  void _beltDragStart(int x, int y) {
    if (tool != FinTool.build ||
        (building != FinBuilding.belt && building != FinBuilding.fastBelt)) {
      return;
    }
    overlay
      ..beltStartX = x
      ..beltStartY = y
      ..beltPreview = world!.beltPath(x, y, x, y);
    frame.value++;
  }

  void _beltDragMove(int x, int y) {
    if (overlay.beltStartX == null) return;
    overlay.beltPreview = world!.beltPath(
      overlay.beltStartX!,
      overlay.beltStartY!,
      x,
      y,
    );
    frame.value++;
  }

  void _beltDragEnd() {
    final path = overlay.beltPreview;
    if (overlay.beltStartX == null || path.isEmpty) return;
    final (x, y, _) = path.last;
    tapCell(x, y);
  }

  // ------------------------------------------------------------------ ui

  Future<void> openMenu() async {
    setState(() => _menu = true);
    final result = await showFinorioMenu(context, this);
    if (!mounted) return;
    setState(() => _menu = false);
    if (result == 'exit') {
      await save();
      if (mounted) Navigator.of(context).maybePop();
    } else if (result == 'restart') {
      await _store.clear();
      _cache?.dispose();
      final w = FinWorld.start(math.Random().nextInt(0x7ffffff0) + 1);
      w.claimed.addAll(world?.claimed ?? const {});
      setState(() {
        world = w;
        _camera = FinCamera(w.cameraX, w.cameraY, w.zoom);
        _cache = FinTerrainCache(w.terrain);
        inspected = null;
      });
      await save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = world, cam = _camera, cache = _cache;
    final media = MediaQuery.of(context);
    if (w == null || cam == null || cache == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFE9E3F1),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final inspect = inspected == null ? null : w.machines[inspected];
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(save());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFCFC7DB),
        body: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = box.biggest;
                  return GestureDetector(
                    key: const ValueKey('finorio-map'),
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (d) => _scaleStart(d, size),
                    onScaleUpdate: (d) => _scaleUpdate(d, size),
                    onScaleEnd: (_) => _focalStart = null,
                    onTapUp: (d) {
                      final (x, y) = _cellAt(d.localPosition, size);
                      tapCell(x, y);
                    },
                    onLongPressStart: (d) {
                      final (x, y) = _cellAt(d.localPosition, size);
                      _beltDragStart(x, y);
                    },
                    onLongPressMoveUpdate: (d) {
                      final (x, y) = _cellAt(d.localPosition, size);
                      _beltDragMove(x, y);
                    },
                    onLongPressEnd: (_) => _beltDragEnd(),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: FinWorldPainter(
                          world: w,
                          camera: cam,
                          cache: cache,
                          overlay: overlay,
                          time: () =>
                              (w.tick + _acc / FinRules.tickMs) /
                              FinRules.ticksPerSecond,
                          alpha: () => running ? _acc / FinRules.tickMs : 0,
                          repaint: frame,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: media.padding.left + 8,
              right: media.padding.right + 8,
              top: media.padding.top + 6,
              child: FinTopBar(state: this),
            ),
            if (_message != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: media.padding.bottom + (inspect == null ? 150 : 330),
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: FinPalette.plum.withValues(alpha: .88),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: media.padding.left,
              right: media.padding.right,
              bottom: 0,
              child: inspect != null
                  ? FinInspector(
                      key: ValueKey('finorio-inspector-${inspect.id}'),
                      state: this,
                      machine: inspect,
                    )
                  : FinBuildBar(state: this),
            ),
          ],
        ),
      ),
    );
  }
}
