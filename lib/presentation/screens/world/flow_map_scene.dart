import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../../domain/flow/flow.dart';
import '../../l10n_widgets.dart';
import 'flow_art.dart';
import 'flow_hud.dart' show FlowType, flowText;
import 'world_art.dart';

/// The supplied terraces and the live nodes share one world coordinate system.
abstract final class FlowMapGeometry {
  static const double referenceWidth = 724;
  static const double sectionHeight = 724;
  static const double periodHeight = 2172;
  static const double origin = 724;
  static const double baseYOffset = 36;
  static const anchors = <FlowMapAnchor>[
    FlowMapAnchor(240, 145),
    FlowMapAnchor(490, 308),
    FlowMapAnchor(235, 465),
    FlowMapAnchor(490, 632),
    FlowMapAnchor(230, 805),
    FlowMapAnchor(350, 1040, width: 130),
    FlowMapAnchor(490, 1290),
    FlowMapAnchor(235, 1410),
    FlowMapAnchor(490, 1555),
    FlowMapAnchor(230, 1695),
    FlowMapAnchor(490, 1835),
    FlowMapAnchor(225, 1988),
    FlowMapAnchor(490, 2130),
  ];

  static int backgroundIndex(int section) => ((section % 3) + 3) % 3;
  static FlowMapAnchor anchor(int levelId, int topLevelId) =>
      anchors[((topLevelId - levelId) % 13 + 13) % 13];
  static double worldY(int levelId, int topLevelId) {
    final q = topLevelId - levelId;
    return (q / 13).floor() * periodHeight + anchor(levelId, topLevelId).y;
  }

  /// Adjacent textures use the exact same rounded boundary, including at a
  /// fractional device pixel ratio; never accumulate rounded section heights.
  static double boundary(int section, double width, double dpr) =>
      ((origin + section * sectionHeight) * width / referenceWidth * dpr)
          .round() /
      dpr;
}

class FlowMapAnchor {
  const FlowMapAnchor(this.x, this.y, {this.width = 164});
  final double x, y, width;
}

class FlowTerraceMap extends StatefulWidget {
  const FlowTerraceMap({
    super.key,
    required this.levels,
    required this.progress,
    required this.onOpen,
    required this.onBack,
    this.onResume,
  });
  final List<FlowLevel> levels;
  final FlowProgress progress;
  final ValueChanged<FlowLevel> onOpen;
  final VoidCallback onBack;
  final VoidCallback? onResume;

  @override
  State<FlowTerraceMap> createState() => _FlowTerraceMapState();
}

class _FlowTerraceMapState extends State<FlowTerraceMap> {
  final _scroll = ScrollController(keepScrollOffset: false);
  String? _layout;
  int? _previousCurrent;
  int? _warmWidth;

  int get _topId => widget.levels.fold(1, (n, l) => math.max(n, l.id));
  int get _currentId {
    final attempt = widget.progress.session;
    if (attempt != null &&
        !attempt.finished &&
        widget.levels.any((l) => l.id == attempt.levelId)) {
      return attempt.levelId;
    }
    return widget.levels
        .where((l) => widget.progress.isUnlocked(l.id))
        .fold(1, (n, l) => math.max(n, l.id));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _warm(BuildContext context, int width) {
    if (_warmWidth == width) return;
    _warmWidth = width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only three reusable textures, not a bitmap of the entire map.
      for (final suffix in const ['A', 'B', 'C']) {
        unawaited(
          precacheImage(
            ResizeImage(
              AssetImage(FlowArt.path('map_bg_$suffix')),
              width: width,
            ),
            context,
            onError: (error, stack) {
              // The visible Image widgets report asset failures normally.
            },
          ),
        );
      }
    });
  }

  void _locate({
    required double width,
    required double height,
    required double headerHeight,
    required EdgeInsets padding,
  }) {
    final current = _currentId;
    final layout = '$width/$height/${padding.top}/${padding.bottom}';
    if (_layout == layout && _previousCurrent == current) return;
    _layout = layout;
    _previousCurrent = current;
    final scale = width / FlowMapGeometry.referenceWidth;
    final node = _nodeRect(
      current,
      _topId,
      scale,
      widget.progress,
      currentId: current,
    );
    final usableTop = padding.top + headerHeight + 20;
    final usableBottom = height - padding.bottom - 12;
    final center = (usableTop + usableBottom) * .5;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(
        (node.center.dy - center).clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => WorldTheme(
    child: Builder(
      builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: worldPearl,
          body: LayoutBuilder(
            builder: (context, box) {
              final media = MediaQuery.of(context);
              final width = box.maxWidth, height = box.maxHeight;
              final scale = width / FlowMapGeometry.referenceWidth;
              final headerWidth = math.min(
                width - media.padding.horizontal - 24,
                500.0,
              );
              // 1.60: a slim header, like the level's top bar.
              const headerHeight = 52.0;
              final top = _topId;
              final lastY = widget.levels.fold<double>(
                0,
                (y, l) => math.max(
                  y,
                  FlowMapGeometry.worldY(l.id, top) +
                      FlowMapGeometry.baseYOffset,
                ),
              );
              final contentWorld =
                  ((FlowMapGeometry.origin + lastY + height / scale * .4) /
                          FlowMapGeometry.sectionHeight)
                      .ceil() *
                  FlowMapGeometry.sectionHeight;
              final contentHeight = math.max(height, contentWorld * scale);
              final cacheWidth = (width * media.devicePixelRatio).ceil().clamp(
                256,
                724,
              );
              _warm(context, cacheWidth);
              _locate(
                width: width,
                height: height,
                headerHeight: headerHeight,
                padding: media.padding,
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(overscroll: false),
                      child: SingleChildScrollView(
                        key: const ValueKey('flow-map-scroll'),
                        controller: _scroll,
                        child: SizedBox(
                          height: contentHeight,
                          width: width,
                          child: AnimatedBuilder(
                            animation: _scroll,
                            builder: (context, _) {
                              final offset = _scroll.hasClients
                                  ? _scroll.offset
                                  : 0.0;
                              final from =
                                  ((offset / scale - FlowMapGeometry.origin) /
                                          FlowMapGeometry.sectionHeight)
                                      .floor() -
                                  1;
                              final through =
                                  (((offset + height) / scale -
                                              FlowMapGeometry.origin) /
                                          FlowMapGeometry.sectionHeight)
                                      .ceil() +
                                  1;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (
                                    var section = from;
                                    section <= through;
                                    section++
                                  )
                                    if (FlowMapGeometry.boundary(
                                              section + 1,
                                              width,
                                              media.devicePixelRatio,
                                            ) >
                                            0 &&
                                        FlowMapGeometry.boundary(
                                              section,
                                              width,
                                              media.devicePixelRatio,
                                            ) <
                                            contentHeight)
                                      _background(
                                        section,
                                        width,
                                        media.devicePixelRatio,
                                        cacheWidth,
                                      ),
                                  for (final level in widget.levels)
                                    if (_nodeRect(
                                              level.id,
                                              top,
                                              scale,
                                              widget.progress,
                                              currentId: _currentId,
                                            ).bottom >=
                                            offset - width &&
                                        _nodeRect(
                                              level.id,
                                              top,
                                              scale,
                                              widget.progress,
                                              currentId: _currentId,
                                            ).top <=
                                            offset + height + width)
                                      Positioned.fromRect(
                                        rect: _nodeRect(
                                          level.id,
                                          top,
                                          scale,
                                          widget.progress,
                                          currentId: _currentId,
                                        ),
                                        child: _TerraceNode(
                                          level: level,
                                          progress: widget.progress,
                                          current: level.id == _currentId,
                                          onOpen: widget.onOpen,
                                        ),
                                      ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: media.padding.top + 8,
                    left: (width - headerWidth) / 2,
                    width: headerWidth,
                    height: headerHeight,
                    child: _MapHeader(onBack: widget.onBack),
                  ),
                  if (widget.onResume != null &&
                      widget.progress.session != null &&
                      !widget.progress.session!.finished)
                    Positioned(
                      left: media.padding.left + 24,
                      right: media.padding.right + 24,
                      bottom: media.padding.bottom + 12,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: WorldPearlSurface(
                            key: const ValueKey('flow-resume'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            onTap: widget.onResume,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.play_arrow_rounded,
                                  color: worldJade,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Продолжить уровень ${widget.progress.session!.levelId}',
                                    style: flowText(14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _background(int section, double width, double dpr, int cacheWidth) {
    final top = FlowMapGeometry.boundary(section, width, dpr);
    final bottom = FlowMapGeometry.boundary(section + 1, width, dpr);
    final suffix = const [
      'A',
      'B',
      'C',
    ][FlowMapGeometry.backgroundIndex(section)];
    return Positioned(
      key: ValueKey('flow-map-section-$section'),
      left: 0,
      top: top,
      width: width,
      height: bottom - top,
      child: Image.asset(
        FlowArt.path('map_bg_$suffix'),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        cacheWidth: cacheWidth,
        excludeFromSemantics: true,
        gaplessPlayback: true,
      ),
    );
  }
}

// Alpha128 bounds from the supplied manifest: all nodes receive the same
// visible width, and their visible lower edge remains on the terrace anchor.
const _nodeBounds = <String, Rect>{
  'completed': Rect.fromLTRB(50, 37, 451, 465),
  'current': Rect.fromLTRB(50, 62, 451, 465),
  'locked': Rect.fromLTRB(64, 62, 437, 451),
  'available': Rect.fromLTRB(59, 61, 442, 453),
};

String _nodeState(int id, FlowProgress progress, bool current) =>
    progress.results.containsKey(id)
    ? 'completed'
    : !progress.isUnlocked(id)
    ? 'locked'
    : current
    ? 'current'
    : 'available';

Rect _nodeRect(
  int id,
  int top,
  double scale,
  FlowProgress progress, {
  int? currentId,
}) {
  final anchor = FlowMapGeometry.anchor(id, top);
  final bounds =
      _nodeBounds[_nodeState(
        id,
        progress,
        id == (currentId ?? progress.highestUnlocked),
      )]!;
  final height = anchor.width * bounds.height / bounds.width;
  return Rect.fromLTWH(
    (anchor.x - anchor.width / 2) * scale,
    (FlowMapGeometry.origin +
            FlowMapGeometry.worldY(id, top) +
            FlowMapGeometry.baseYOffset -
            height) *
        scale,
    anchor.width * scale,
    height * scale,
  );
}

class _TerraceNode extends StatelessWidget {
  const _TerraceNode({
    required this.level,
    required this.progress,
    required this.current,
    required this.onOpen,
  });
  final FlowLevel level;
  final FlowProgress progress;
  final bool current;
  final ValueChanged<FlowLevel> onOpen;

  @override
  Widget build(BuildContext context) {
    final result = progress.results[level.id];
    final unlocked = progress.isUnlocked(level.id);
    final state = _nodeState(level.id, progress, current);
    final bounds = _nodeBounds[state]!;
    final description = result != null
        ? 'Пройден. ${result.stars} из 3 звёзд'
        : unlocked
        ? 'Доступен'
        : 'Закрыт. Пройдите уровень ${level.id - 1}';
    return Semantics(
      button: true,
      enabled: unlocked,
      label: 'Уровень ${level.id}. ${level.name}. $description',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Уровень ${level.id}. ${level.name}. $description',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('flow-level-${level.id}'),
            borderRadius: BorderRadius.circular(60),
            onTap: unlocked ? () => onOpen(level) : null,
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth, height = box.maxHeight;
                final pixelScale = width / bounds.width;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -bounds.left * pixelScale,
                      top: -bounds.top * pixelScale,
                      width: 512 * pixelScale,
                      height: 512 * pixelScale,
                      child: FlowSprite(
                        'map_node_$state',
                        trim: false,
                        width: 512 * pixelScale,
                        height: 512 * pixelScale,
                      ),
                    ),
                    Positioned(
                      left: width * .14,
                      width: width * .72,
                      top:
                          height *
                          (state == 'completed'
                              ? .18
                              : state == 'locked'
                              ? .14
                              : .24),
                      height: height * .44,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${level.id}',
                            textScaler: TextScaler.noScaling,
                            style: flowText(
                              width * (level.id >= 100 ? .32 : .4),
                            ).copyWith(height: 1),
                          ),
                        ),
                      ),
                    ),
                    if (result != null)
                      for (var i = 0; i < 3; i++)
                        Positioned(
                          left: width * (.28 + i * .22) - width * .12,
                          top: height * (i == 1 ? .82 : .79) - width * .12,
                          width: width * .24,
                          height: width * .24,
                          child: FlowSprite(
                            i < result.stars
                                ? 'map_star_earned'
                                : 'map_star_empty',
                            width: width * .24,
                            height: width * .24,
                          ),
                        ),
                    if (!unlocked)
                      Positioned(
                        left: width * .36,
                        top: height * .76 - width * .15,
                        width: width * .28,
                        height: width * .3,
                        child: FlowSprite(
                          'map_lock_closed',
                          width: width * .28,
                          height: width * .3,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  const _MapHeader({required this.onBack});
  final VoidCallback onBack;

  /// 1.62: the pack's header — the pearl bar, the «Уровни» lettering and
  /// the round back button (its target widened to 48×48).
  @override
  Widget build(BuildContext context) => FlowArtPanel(
    key: const ValueKey('flow-map-header'),
    art: 'map_header_base',
    padding: EdgeInsets.zero,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          left: 56,
          right: 56,
          child: Semantics(
            header: true,
            child: Center(child: Text('Уровни', style: FlowType.heading)),
          ),
        ),
        Positioned(
          left: 4,
          top: 0,
          bottom: 0,
          child: Semantics(
            button: true,
            label: 'Назад к играм',
            child: Tooltip(
              message: 'Назад к играм',
              child: InkWell(
                key: const ValueKey('flow-map-back'),
                onTap: onBack,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: FlowSprite('map_button_back', width: 36, height: 36),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
