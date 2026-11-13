import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../../services/magistrali_store.dart';
import '../../../controller.dart';
import 'mag_art.dart';
import 'mag_game.dart';
import 'mag_hud.dart';
import 'mag_iso.dart';
import 'mag_fleet.dart';
import 'mag_sheets.dart';
import 'mag_sprites.dart';
import 'mag_tools.dart';
import 'mag_town.dart';
import 'mag_warehouse.dart';

/// What a finger on the map does.
enum MagTool { view, road, remove, warehouse }

/// «Магистрали»: a transport company on an isometric map. Roads are drawn
/// with a finger, trucks run their routes by themselves, deliveries pay,
/// and the money goes into new trucks, upgrades and roads.
class MagistraliScreen extends StatefulWidget {
  const MagistraliScreen({super.key, this.seed});

  /// A fixed map for a new company (tests); the saved company otherwise.
  final int? seed;

  @override
  State<MagistraliScreen> createState() => MagistraliScreenState();
}

class MagistraliScreenState extends State<MagistraliScreen>
    with WidgetsBindingObserver
    implements MagHost {
  final _store = MagistraliStore();
  MagWorld? _world;
  MagCamera? _camera;
  MagGame? game;
  @override
  final overlay = MagOverlay();

  /// Bumped as the simulation runs (panels listen to it).
  final ticks = ValueNotifier(0);

  double _time = 0, _acc = 0, _sinceSave = 0, _sincePanel = 0;
  bool _foreground = true, _dirty = false;
  final _incomeSeen = <int, int>{};
  int _rewardsSeen = -1;

  MagTool tool = MagTool.view;

  /// The task card shows only its title.
  bool taskFolded = false;
  void toggleTask() => setState(() => taskFolded = !taskFolded);
  MagRoad roadType = MagRoad.dirt;

  /// A road or a removal waiting for «Построить» / «Снести».
  MagRoadPlan? pendingRoad;
  List<int> pendingRemove = const [];

  /// Corner cell of a warehouse waiting for «Построить».
  int? pendingWarehouse;
  int? _tapStart;
  String? message;
  Timer? _messageTimer;

  @override
  MagWorld get world => _world!;
  MagWorld? get maybeWorld => _world;
  @override
  MagCamera get camera => _camera!;
  @override
  double get time => _time;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    MagWorld? w;
    if (widget.seed == null) w = await _store.load();
    w ??= MagWorld.start(widget.seed ?? MagRules.defaultSeed);
    try {
      MagSprites.current = await MagSprites.load();
    } on Object {
      MagSprites.current = null;
    }
    if (!mounted) return;
    setState(() {
      _world = w;
      _camera = MagCamera(w!.cameraX, w.cameraY, w.zoom);
      game = MagGame(this);
      for (final v in w.vehicles.values) {
        _incomeSeen[v.id] = v.income;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageTimer?.cancel();
    unawaited(save());
    MagSprites.current?.dispose();
    MagSprites.current = null;
    ticks.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The company stands still while the game is not on screen.
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(save());
  }

  Future<void> _saving = Future.value();

  /// Saves the company; saves run one after another, never at once.
  Future<void> save() => _saving = _saving.then((_) => _save());

  Future<void> _save() async {
    final w = _world, cam = _camera;
    if (w == null || cam == null) return;
    w
      ..cameraX = cam.x
      ..cameraY = cam.y
      ..zoom = cam.zoom;
    _dirty = false;
    try {
      await _store.save(w);
    } on Object {
      _dirty = true; // tried again at the next autosave
    }
  }

  @override
  void advance(double dt) {
    final w = _world;
    if (w == null) return;
    _time += dt;
    if (!_foreground) return;
    _acc += math.min(dt, .25) * 1000 * w.speed;
    final n = (_acc / MagRules.tickMs).floor();
    if (n > 0) {
      _acc -= n * MagRules.tickMs;
      w.step(n);
      _dirty = true;
      _afterTicks(w);
    }
    _sinceSave += dt;
    if (_sinceSave > 15 && _dirty) {
      _sinceSave = 0;
      unawaited(save());
    }
    _sincePanel += dt;
    if (_sincePanel > .25) {
      _sincePanel = 0;
      ticks.value++;
    }
  }

  void _afterTicks(MagWorld w) {
    for (final v in w.vehicles.values) {
      final seen = _incomeSeen[v.id] ?? v.income;
      if (v.income > seen && v.onMap) {
        final (x, y) = w.positionOf(v);
        overlay.floats.add((x, y, '+${v.income - seen}', _time));
      }
      _incomeSeen[v.id] = v.income;
    }
    final events = w.takeEvents().where((e) => !e.startsWith('+')).toList();
    if (events.isNotEmpty) say(events.last);
    final earned = w.earnedRewards;
    if (earned.length != _rewardsSeen) {
      _rewardsSeen = earned.length;
      final c = FinanceScope.maybeOf(context);
      if (c != null) unawaited(c.claimGameRewards(earned).catchError((_) {}));
    }
  }

  void say(String text) {
    _messageTimer?.cancel();
    setState(() => message = text);
    _messageTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => message = null);
    });
  }

  /// After a player's action: tasks, panels, a save soon.
  void changed() {
    final w = world;
    w.checkTasks();
    _afterTicks(w);
    _dirty = true;
    ticks.value++;
    setState(() {});
  }

  /// Shows a result: an error, or [ok] when it worked.
  bool report(String? error, [String? ok]) {
    if (error != null) {
      say(error);
      return false;
    }
    if (ok != null) say(ok);
    changed();
    return true;
  }

  /// A new company on a new map (rewards already paid stay paid).
  Future<void> restart() async {
    await _store.clear();
    final w = MagWorld.start(math.Random().nextInt(0x7ffffff0) + 1);
    if (!mounted) return;
    setState(() {
      _world = w;
      _camera = MagCamera(w.cameraX, w.cameraY, w.zoom);
      _incomeSeen.clear();
      _rewardsSeen = -1;
      overlay
        ..industry = null
        ..vehicle = null
        ..floats.clear();
      tool = MagTool.view;
      _clearPending();
    });
    await save();
  }

  void centerOn(double x, double y) {
    camera
      ..x = x
      ..y = y;
  }

  void setTool(MagTool t, [MagRoad? type]) => setState(() {
    tool = t;
    if (type != null) roadType = type;
    _clearPending();
  });

  void _clearPending() {
    pendingRoad = null;
    pendingRemove = const [];
    pendingWarehouse = null;
    _tapStart = null;
    overlay
      ..plan = const []
      ..removing = const [];
  }

  void cancelPending() => setState(_clearPending);

  void confirmPending() {
    final wh = pendingWarehouse;
    if (wh != null) {
      if (report(world.buildWarehouse(world.cx(wh), world.cy(wh)))) {
        setState(() {
          _clearPending();
          tool = MagTool.view;
        });
        final built = world.warehouses.last;
        unawaited(showWarehouseSheet(this, built.id));
      }
      return;
    }
    final road = pendingRoad;
    if (road != null) {
      if (report(world.buildRoad(road), 'Дорога построена')) {
        setState(_clearPending);
      }
      return;
    }
    if (pendingRemove.isNotEmpty) {
      if (report(world.removeRoad(pendingRemove), 'Дорога снесена')) {
        setState(_clearPending);
      }
    }
  }

  // ---- Gestures ----

  Offset? _downAt, _focalStart;
  Offset _cellStart = Offset.zero;
  double _zoomStart = 1;
  bool _drawing = false;
  int? _drawFrom;

  int? _cellAt(Offset p, Size size) {
    final c = camera.toCell(p, size);
    final x = c.dx.floor(), y = c.dy.floor();
    return world.map.inside(x, y) ? world.cellOf(x, y) : null;
  }

  void _scaleStart(ScaleStartDetails d, Size size) {
    if ((tool == MagTool.road || tool == MagTool.remove) &&
        d.pointerCount == 1) {
      _drawFrom = _cellAt(_downAt ?? d.localFocalPoint, size);
      if (_drawFrom != null) {
        _drawing = true;
        _drawTo(_drawFrom!);
        return;
      }
    }
    _beginPan(d.localFocalPoint, size);
  }

  void _beginPan(Offset focal, Size size) {
    _drawing = false;
    _focalStart = focal;
    _zoomStart = camera.zoom;
    _cellStart = camera.toCell(focal, size);
  }

  void _scaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_drawing) {
      if (d.pointerCount > 1) {
        setState(_clearPending);
        _beginPan(d.localFocalPoint, size);
        _zoomStart = camera.zoom / d.scale;
      } else {
        final c = _cellAt(d.localFocalPoint, size);
        if (c != null) _drawTo(c);
        return;
      }
    }
    if (_focalStart == null) return;
    final cam = camera;
    cam.zoom = (_zoomStart * d.scale).clamp(
      MagCamera.minZoom,
      MagCamera.maxZoom,
    );
    // Keep the cell under the fingers where it was.
    final now = cam.toCell(d.localFocalPoint, size);
    final n = world.size.toDouble();
    cam
      ..x = (cam.x + _cellStart.dx - now.dx).clamp(0, n)
      ..y = (cam.y + _cellStart.dy - now.dy).clamp(0, n);
  }

  void _scaleEnd() {
    _focalStart = null;
    if (!_drawing) return;
    _drawing = false;
    setState(() {}); // shows the confirm bar
  }

  void _drawTo(int to) {
    final w = world, from = _drawFrom!;
    if (tool == MagTool.road) {
      final plan = w.planRoad(
        w.cx(from),
        w.cy(from),
        w.cx(to),
        w.cy(to),
        roadType,
      );
      pendingRoad = plan;
      overlay
        ..plan = plan.cells.isEmpty ? [from] : plan.cells
        ..planOk = plan.error == null && plan.cost <= w.money;
    } else {
      // Removal follows a straight L from the first cell.
      final cells = <int>[];
      final fx = w.cx(from), fy = w.cy(from), tx = w.cx(to), ty = w.cy(to);
      for (var x = fx; x != tx + (tx >= fx ? 1 : -1); x += tx >= fx ? 1 : -1) {
        cells.add(w.cellOf(x, fy));
      }
      for (var y = fy; y != ty + (ty >= fy ? 1 : -1); y += ty >= fy ? 1 : -1) {
        if (y != fy) cells.add(w.cellOf(tx, y));
      }
      pendingRemove = [
        for (final c in cells)
          if (w.roads[c] != 0) c,
      ];
      overlay.removing = pendingRemove;
    }
    setState(() {});
  }

  void _tap(Offset p, Size size) {
    final cell = _cellAt(p, size);
    if (cell == null) return;
    final w = world;
    switch (tool) {
      case MagTool.road:
        // Two taps also make a road: start, then end.
        if (_tapStart == null || pendingRoad != null) {
          setState(() {
            _clearPending();
            _tapStart = cell;
            overlay
              ..plan = [cell]
              ..planOk = true;
          });
          say('Теперь коснитесь, где дорога закончится');
        } else {
          _drawFrom = _tapStart;
          _drawTo(cell);
          _tapStart = null;
        }
      case MagTool.warehouse:
        // The tapped cell is the warehouse's top corner (2×2).
        final x = w.cx(cell), y = w.cy(cell);
        final why = w.warehouseBlocker(x, y);
        setState(() {
          pendingWarehouse = cell;
          overlay
            ..plan = [
              for (var dy = 0; dy < 2; dy++)
                for (var dx = 0; dx < 2; dx++)
                  if (w.map.inside(x + dx, y + dy)) w.cellOf(x + dx, y + dy),
            ]
            ..planOk = why == null && w.money >= w.warehousePrice;
        });
        if (why != null) say(why);
      case MagTool.remove:
        if (w.roads[cell] == 0) return say('Здесь нет дороги');
        setState(() {
          pendingRemove = [...pendingRemove, cell];
          overlay.removing = pendingRemove;
        });
      case MagTool.view:
        // A truck under the finger first, then a place.
        for (final v in w.vehicles.values) {
          if (!v.onMap) continue;
          final (x, y) = w.positionOf(v);
          if ((camera.cellToScreen(x, y, size) - p).distance < 22) {
            setState(() {
              overlay.vehicle = v.id;
              overlay.industry = null;
            });
            unawaited(showVehicleSheet(this, v.id));
            return;
          }
        }
        final i = w.map.industryAt(w.cx(cell), w.cy(cell));
        setState(() {
          overlay.industry = i?.id;
          overlay.vehicle = null;
        });
        if (i != null) {
          unawaited(
            i.town != null
                ? showTownSheet(this, i.id)
                : i.spec.stores
                ? showWarehouseSheet(this, i.id)
                : showIndustrySheet(this, i.id),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _world, g = game;
    final media = MediaQuery.of(context);
    if (w == null || g == null) {
      return const Scaffold(
        backgroundColor: MagPalette.sky,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(save());
      },
      child: Scaffold(
        backgroundColor: MagPalette.sky,
        body: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = box.biggest;
                  return Listener(
                    onPointerDown: (e) => _downAt = e.localPosition,
                    child: GestureDetector(
                      key: const ValueKey('mag-map'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (d) => _scaleStart(d, size),
                      onScaleUpdate: (d) => _scaleUpdate(d, size),
                      onScaleEnd: (_) => _scaleEnd(),
                      onTapUp: (d) => _tap(d.localPosition, size),
                      child: GameWidget<MagGame>(game: g),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: media.padding.left + 8,
              right: media.padding.right + 8,
              top: media.padding.top + 6,
              child: MagTopBar(state: this),
            ),
            if (message != null)
              Positioned(
                left: 24,
                right: 24,
                bottom:
                    media.padding.bottom + (tool == MagTool.view ? 150 : 340),
                child: MagToast(text: message!),
              ),
            Positioned(
              left: media.padding.left,
              right: media.padding.right,
              bottom: 0,
              child: MagBottomPanel(state: this),
            ),
          ],
        ),
      ),
    );
  }
}
