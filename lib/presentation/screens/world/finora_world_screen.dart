import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/wardrobe.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';

import '../achievements_screen.dart';
import '../management.dart';
import '../wardrobe_screen.dart';
import 'world_collections.dart';
import 'world_components.dart';
import 'world_customization.dart';
import 'world_games_screen.dart';
import 'world_garden_album.dart';
import 'world_home_scene.dart';
import 'world_home_chrome.dart';
import 'world_reviews_settings.dart';

/// A private home inside existing settings. Main navigation is untouched.
class FinoraWorldScreen extends StatefulWidget {
  const FinoraWorldScreen({super.key});

  @override
  State<FinoraWorldScreen> createState() => _FinoraWorldScreenState();
}

class _FinoraWorldScreenState extends State<FinoraWorldScreen>
    with WidgetsBindingObserver {
  bool _active = true, _front = true, _synced = false, _celebrating = false;
  bool _pendingCelebration = false;
  Set<String>? _completed;
  Timer? _celebration;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = FinanceScope.of(context);
    final completed = c.data.world.completedGoals;
    final previous = _completed;
    _completed = {...completed};
    if (previous != null && completed.difference(previous).isNotEmpty) {
      _pendingCelebration = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _celebrateIfVisible();
      });
    }
    if (!_synced) {
      _synced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(worldAttempt(context, c.syncWorld));
      });
    }
  }

  void _celebrateIfVisible() {
    if (!_pendingCelebration || !_active || !_front) return;
    _pendingCelebration = false;
    if (FinanceScope.of(context).data.world.reducedMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _celebration?.cancel();
    setState(() => _celebrating = true);
    _celebration = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _active = state == AppLifecycleState.resumed;
      if (!_active) _celebrating = false;
    });
    if (!_active) _celebration?.cancel();
    if (_active) _celebrateIfVisible();
  }

  @override
  void dispose() {
    _celebration?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open(Widget page) async {
    _celebration?.cancel();
    setState(() {
      _front = false;
      _celebrating = false;
    });
    try {
      await worldOpen(context, page);
    } finally {
      if (mounted) {
        setState(() => _front = true);
        _celebrateIfVisible();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final state = c.data.world;
    final points = c.worldPoints;
    final level = c.achievements.level;
    final reduced =
        state.reducedMotion || MediaQuery.disableAnimationsOf(context);
    return WorldTheme(
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: TickerMode(
            enabled: _active && _front && !reduced,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  (['night', 'underwater', 'aurora'].contains(
                            WorldArt.background(state.background).cosmeticId,
                          )
                          ? SystemUiOverlayStyle.light
                          : SystemUiOverlayStyle.dark)
                      .copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.transparent,
                        systemNavigationBarIconBrightness:
                            ['night', 'underwater', 'aurora'].contains(
                              WorldArt.background(state.background).cosmeticId,
                            )
                            ? Brightness.light
                            : Brightness.dark,
                      ),
              child: Scaffold(
                backgroundColor: worldPearl,
                body: LayoutBuilder(
                  builder: (context, box) {
                    final media = MediaQuery.of(context);
                    final scale = media.textScaler.scale(1);
                    final landscape = box.maxWidth > box.maxHeight;
                    final stacked = WorldHomeHeader.stacks(
                      box.maxWidth - media.padding.horizontal - 16,
                      scale,
                    );
                    final headerHeight = stacked
                        ? 108 + (scale - 1) * 24
                        : 60 + math.max(0, scale - 1) * 24;
                    final dockHeight =
                        (landscape ? 104.0 : 124.0) +
                        math.max(0, scale - 1) * 25;
                    final topInset =
                        media.padding.top +
                        headerHeight +
                        (landscape ? 30 : 44);
                    final bottomInset = media.padding.bottom + dockHeight;
                    return Stack(
                      key: const ValueKey('world-page-Мир Финоры'),
                      children: [
                        Positioned.fill(
                          child: WorldHomeScene(
                            world: state,
                            wardrobe: c.data.wardrobe,
                            celebrating: _celebrating,
                            topInset: topInset,
                            bottomInset: bottomInset,
                            onBackground: () =>
                                _open(const WorldBackgroundScreen()),
                            onDecorate: () => _open(const WorldDecorScreen()),
                            reaction: state.remarks
                                ? _WorldReaction(onOpen: _open)
                                : null,
                          ),
                        ),
                        Positioned(
                          top: media.padding.top + 4,
                          left: media.padding.left + 8,
                          right: media.padding.right + 8,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              WorldHomeHeader(
                                title: level.title,
                                points: points,
                                progress: level.next == null
                                    ? null
                                    : ((points - level.from) /
                                              (level.next! - level.from))
                                          .clamp(0, 1),
                                sparks: state.sparks,
                                onBack: () => Navigator.maybePop(context),
                                onRank: () => _open(const AchievementsScreen()),
                                onCurrency: () =>
                                    _open(const WorldSettingsScreen()),
                                onSettings: () =>
                                    _open(const WorldSettingsScreen()),
                              ),
                              SizedBox(
                                height: landscape ? 32 : 44,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const WorldArtImage(
                                      'leaf_ornament',
                                      size: 26,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Мир Финоры',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFFFFBF1),
                                          fontSize: math.min(
                                            landscape ? 19 : 23,
                                            (landscape ? 25 : 30) / scale,
                                          ),
                                          height: 1.05,
                                          fontWeight: FontWeight.w700,
                                          shadows: const [
                                            Shadow(
                                              color: worldPlum,
                                              blurRadius: 5,
                                              offset: Offset(0, 1),
                                            ),
                                            Shadow(
                                              color: worldPlum,
                                              blurRadius: 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Transform.flip(
                                      flipX: true,
                                      child: const WorldArtImage(
                                        'leaf_ornament',
                                        size: 26,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: media.padding.left + 12,
                          bottom: bottomInset + 8,
                          child: WorldPearlSurface(
                            padding: EdgeInsets.zero,
                            child: IconButton(
                              key: const ValueKey('world-home-more'),
                              tooltip: 'Образы, коллекции и обзор',
                              onPressed: () => _showMore(context),
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                color: worldPlum,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: media.padding.left + 4,
                          right: media.padding.right + 4,
                          bottom: media.padding.bottom + 4,
                          height: dockHeight,
                          child: WorldHomeDock(
                            key: const ValueKey('world-home-dock'),
                            children: [
                              _homeNav(
                                'world-destination-0',
                                'wardrobe',
                                'Гардероб',
                                const WardrobeScreen(
                                  initialCategory: WardrobeCategory.cape,
                                ),
                                landscape,
                              ),
                              _homeNav(
                                'world-nav-pets',
                                'pet',
                                'Питомцы',
                                const WardrobeScreen(
                                  initialCategory: WardrobeCategory.companion,
                                ),
                                landscape,
                              ),
                              _homeNav(
                                'world-destination-2',
                                'garden',
                                'Сад',
                                const WorldGardenScreen(),
                                landscape,
                              ),
                              _homeNav(
                                'world-destination-4',
                                'album',
                                'Альбом',
                                const WorldAlbumScreen(),
                                landscape,
                              ),
                              _homeNav(
                                'world-destination-5',
                                'games',
                                'Игры',
                                const WorldGamesScreen(),
                                landscape,
                              ),
                            ],
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
      ),
    );
  }

  Future<void> _showMore(BuildContext themedContext) async {
    final page = await showModalBottomSheet<Widget>(
      context: themedContext,
      showDragHandle: true,
      builder: (_) => WorldTheme(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in <(String, String, IconData, Widget)>[
                  (
                    'world-destination-1',
                    'Образы',
                    Icons.checkroom_outlined,
                    const WorldOutfitsScreen(),
                  ),
                  (
                    'world-destination-3',
                    'Коллекции',
                    Icons.collections_bookmark_outlined,
                    const WorldCollectionsScreen(),
                  ),
                  (
                    'world-open-review',
                    'Обзор',
                    Icons.insights_rounded,
                    const WorldReviewScreen(),
                  ),
                ])
                  ListTile(
                    key: ValueKey(item.$1),
                    leading: Icon(item.$3, color: worldJade),
                    title: Text(item.$2),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(themedContext, item.$4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (page != null && mounted) await _open(page);
  }

  Widget _homeNav(
    String id,
    String image,
    String label,
    Widget page,
    bool compact,
  ) => Expanded(
    child: Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: ValueKey(id),
          onTap: () => _open(page),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WorldArtImage(image, size: compact ? 48 : 64),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: worldChampagne.withValues(alpha: .7),
                    ),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: worldPlum,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _WorldReaction extends StatelessWidget {
  const _WorldReaction({required this.onOpen});
  final Future<void> Function(Widget) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final lastGoal =
        c.data.world.memories.values
            .where((memory) => memory.goalId != null)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final goalId = lastGoal.firstOrNull?.goalId;
    final hasPayment = c.data.recurring.any(
      (rule) => rule.paymentType == 'mandatory' && rule.enabled,
    );
    final message = goalId != null
        ? 'Цель достигнута. Этот момент уже в альбоме.'
        : hasPayment
        ? 'Теперь обязательные платежи на виду.'
        : 'С возвращением!';
    return WorldPearlSurface(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          if (goalId != null || hasPayment)
            IconButton(
              tooltip: goalId != null ? 'Открыть альбом' : 'Открыть платежи',
              onPressed: () => onOpen(
                goalId != null
                    ? const WorldAlbumScreen()
                    : const RecurringScreen(),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 19),
            ),
        ],
      ),
    );
  }
}
