import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../../services/magistrali_store.dart';
import '../../../controller.dart';
import 'mag_center.dart';
import 'mag_art.dart';
import 'mag_game.dart';
import 'mag_hud.dart';
import 'mag_iso.dart';
import 'mag_road.dart';
import 'mag_fleet.dart';
import 'mag_sheets.dart';
import 'mag_sprites.dart';
import 'mag_tools.dart';
import 'mag_town.dart';
import 'mag_warehouse.dart';

part 'mag_screen_input.dart';

/// What a finger on the map does.
enum MagTool { view, road, remove, warehouse, industry }

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
  final _townLevels = <int, int>{};
  int _problemsDay = -1;
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

  /// What the «Предприятие» tool builds, and where (waiting to confirm).
  MagIndustryKind? buildKind;
  int? pendingIndustry;
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
    // Problem marks on the map, worked out once a game day.
    if (w.day != _problemsDay) {
      _problemsDay = w.day;
      overlay.problems = w.problemPlaces;
    }
    // A settlement that grew shows its new level over it.
    for (final i in w.settlements) {
      final level = i.town!.level, seen = _townLevels[i.id];
      if (seen != null && level > seen) {
        overlay.floats.add((
          i.centerX,
          i.centerY,
          '▲ ${i.town!.spec.name}',
          _time,
        ));
      }
      _townLevels[i.id] = level;
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
      _townLevels.clear();
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

  void chooseBuild(MagIndustryKind k) => setState(() {
    tool = MagTool.industry;
    buildKind = k;
    _clearPending();
  });

  void setTool(MagTool t, [MagRoad? type]) => setState(() {
    tool = t;
    if (type != null) roadType = type;
    _clearPending();
  });

  void _clearPending() {
    pendingRoad = null;
    pendingRemove = const [];
    pendingWarehouse = null;
    pendingIndustry = null;
    _tapStart = null;
    overlay
      ..plan = const []
      ..removing = const [];
  }

  void cancelPending() => setState(_clearPending);

  void confirmPending() {
    final at = pendingIndustry, kind = buildKind;
    if (at != null && kind != null) {
      if (report(world.buildIndustry(kind, world.cx(at), world.cy(at)))) {
        setState(() {
          _clearPending();
          tool = MagTool.view;
        });
        final built = world.map.industries.last;
        unawaited(
          built.kind == MagIndustryKind.logisticsCenter
              ? showCenterSheet(this, built.id)
              : showIndustrySheet(this, built.id),
        );
      }
      return;
    }
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
  bool _drawing = false, _drawStarted = false;
  MagRoadPlan? _extending;
  int? _drawFrom;

  /// setState for the input part of this screen.
  void _refresh(VoidCallback fn) => setState(fn);

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
