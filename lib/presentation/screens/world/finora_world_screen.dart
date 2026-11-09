import 'dart:async';

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
            child: Scaffold(
              backgroundColor: worldPearl,
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final rank = WorldPearlSurface(
                      padding: const EdgeInsets.fromLTRB(5, 7, 10, 7),
                      onTap: () => _open(const AchievementsScreen()),
                      child: Row(
                        children: [
                          const WorldArtImage('rank_badge', size: 40),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  level.title,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$points опыта',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                if (level.next != null) ...[
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    key: const ValueKey('world-level-progress'),
                                    value:
                                        ((points - level.from) /
                                                (level.next! - level.from))
                                            .clamp(0, 1),
                                    color: const Color(0xFF84CBA9),
                                    backgroundColor: const Color(0xFFE3D8E4),
                                    minHeight: 4,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                    final currency = WorldPearlSurface(
                      padding: const EdgeInsets.fromLTRB(5, 1, 0, 1),
                      child: Row(
                        children: [
                          const WorldArtImage('currency_gem', size: 30),
                          Expanded(
                            child: Text(
                              '${state.sparks}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          WorldImageButton(
                            key: const ValueKey('world-currency-ways'),
                            id: 'add',
                            label: 'Как получать искры',
                            size: 36,
                            onPressed: () => _open(const WorldSettingsScreen()),
                          ),
                        ],
                      ),
                    );
                    final back = WorldImageButton(
                      id: 'back',
                      label: 'Назад',
                      onPressed: () => Navigator.maybePop(context),
                    );
                    final settings = WorldImageButton(
                      key: const ValueKey('world-settings'),
                      id: 'settings',
                      label: 'Настройки мира',
                      onPressed: () => _open(const WorldSettingsScreen()),
                    );
                    return SingleChildScrollView(
                      key: const ValueKey('world-page-Мир Финоры'),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                          child: Column(
                            children: [
                              if (box.maxWidth >= 420 && scale < 1.3)
                                Row(
                                  children: [
                                    back,
                                    const SizedBox(width: 3),
                                    Expanded(child: rank),
                                    const SizedBox(width: 6),
                                    SizedBox(width: 125, child: currency),
                                    settings,
                                  ],
                                )
                              else ...[
                                Row(
                                  children: [
                                    back,
                                    const SizedBox(width: 3),
                                    Expanded(child: rank),
                                    settings,
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: SizedBox(width: 172, child: currency),
                                ),
                              ],
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const WorldArtImage(
                                      'leaf_ornament',
                                      size: 30,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Мир Финоры',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              color: worldPlum,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 36),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: (box.maxHeight * .55).clamp(
                                  230.0,
                                  600.0,
                                ),
                                child: WorldHomeScene(
                                  world: state,
                                  wardrobe: c.data.wardrobe,
                                  celebrating: _celebrating,
                                  onBackground: () =>
                                      _open(const WorldBackgroundScreen()),
                                  onDecorate: () =>
                                      _open(const WorldDecorScreen()),
                                ),
                              ),
                              if (state.remarks)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _WorldReaction(onOpen: _open),
                                ),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: [
                                  TextButton(
                                    key: const ValueKey('world-destination-1'),
                                    onPressed: () =>
                                        _open(const WorldOutfitsScreen()),
                                    child: const Text('Образы'),
                                  ),
                                  TextButton(
                                    key: const ValueKey('world-destination-3'),
                                    onPressed: () =>
                                        _open(const WorldCollectionsScreen()),
                                    child: const Text('Коллекции'),
                                  ),
                                  TextButton(
                                    key: const ValueKey('world-open-review'),
                                    onPressed: () =>
                                        _open(const WorldReviewScreen()),
                                    child: const Text('Обзор'),
                                  ),
                                ],
                              ),
                              WorldPearlSurface(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 5,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _homeNav(
                                      'world-destination-0',
                                      'wardrobe',
                                      'Гардероб',
                                      const WardrobeScreen(
                                        initialCategory: WardrobeCategory.cape,
                                      ),
                                    ),
                                    _homeNav(
                                      'world-nav-pets',
                                      'pet',
                                      'Питомцы',
                                      const WardrobeScreen(
                                        initialCategory:
                                            WardrobeCategory.companion,
                                      ),
                                    ),
                                    _homeNav(
                                      'world-destination-2',
                                      'garden',
                                      'Сад',
                                      const WorldGardenScreen(),
                                    ),
                                    _homeNav(
                                      'world-destination-4',
                                      'album',
                                      'Альбом',
                                      const WorldAlbumScreen(),
                                    ),
                                    _homeNav(
                                      'world-destination-5',
                                      'games',
                                      'Игры',
                                      const WorldGamesScreen(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Widget _homeNav(String id, String image, String label, Widget page) =>
      Expanded(
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            key: ValueKey(id),
            onTap: () => _open(page),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WorldArtImage(image, size: 54),
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
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: worldMint.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: worldMint.withValues(alpha: .15)),
      ),
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
