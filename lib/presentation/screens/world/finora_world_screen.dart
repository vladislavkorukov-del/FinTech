import 'dart:async';

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
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
    final theme = Theme.of(context);
    final points = c.worldPoints;
    final level = c.achievements.level;
    final collections = worldCollections
        .where((e) => e.completed(c.data.wardrobe))
        .length;
    return TickerMode(
      enabled:
          _active &&
          _front &&
          !state.reducedMotion &&
          !MediaQuery.disableAnimationsOf(context),
      child: WorldPage(
        title: 'Мир Финоры',
        actions: [
          IconButton(
            key: const ValueKey('world-settings'),
            tooltip: 'Настройки мира',
            onPressed: () => _open(const WorldSettingsScreen()),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              WorldStat(icon: Icons.auto_awesome, text: '${state.sparks} искр'),
              WorldStat(icon: Icons.bolt_outlined, text: '$points опыта'),
              WorldStat(
                icon: Icons.workspace_premium_outlined,
                text: level.title,
              ),
            ],
          ),
          if (level.next != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              key: const ValueKey('world-level-progress'),
              value: ((points - level.from) / (level.next! - level.from)).clamp(
                0,
                1,
              ),
              color: worldMint,
              backgroundColor: worldMint.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
              minHeight: 4,
            ),
            const SizedBox(height: 5),
            Text(
              'До следующего уровня: ${level.next! - points} опыта',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          WorldHomeScene(
            world: state,
            wardrobe: c.data.wardrobe,
            celebrating: _celebrating,
            onDecorate: () => _open(const WorldDecorScreen()),
          ),
          if (state.remarks) ...[
            const SizedBox(height: 12),
            _WorldReaction(onOpen: _open),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              final destinations = <(IconData, String, String, Widget)>[
                (
                  Icons.checkroom_outlined,
                  'Гардероб',
                  'Компаньоны и плащи',
                  const WardrobeScreen(),
                ),
                (
                  Icons.bookmarks_outlined,
                  'Образы',
                  '${state.outfits.length} сохранено',
                  const WorldOutfitsScreen(),
                ),
                (
                  Icons.spa_outlined,
                  'Сад целей',
                  '${c.data.goals.length} растений',
                  const WorldGardenScreen(),
                ),
                (
                  Icons.collections_bookmark_outlined,
                  'Коллекции',
                  '$collections из ${worldCollections.length}',
                  const WorldCollectionsScreen(),
                ),
                (
                  Icons.photo_album_outlined,
                  'Альбом',
                  '${state.memories.length} воспоминаний',
                  const WorldAlbumScreen(),
                ),
                (
                  Icons.extension_outlined,
                  'Путешествия',
                  'Три небольшие активности',
                  const WorldGamesScreen(),
                ),
              ];
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    SizedBox(
                      width: width,
                      child: _WorldDestination(
                        key: ValueKey('world-destination-$i'),
                        icon: destinations[i].$1,
                        title: destinations[i].$2,
                        subtitle: destinations[i].$3,
                        onTap: () => _open(destinations[i].$4),
                      ),
                    ),
                ],
              );
            },
          ),
          const WorldHeading('Финансовые привычки'),
          WorldPanel(
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('world-open-review'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.fact_check_outlined,
                    color: worldMint,
                  ),
                  title: const Text('Недельный и месячный обзор'),
                  subtitle: const Text(
                    'Проверить данные и сохранить результат',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _open(const WorldReviewScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.emoji_events_outlined,
                    color: worldMint,
                  ),
                  title: const Text('Достижения'),
                  subtitle: Text(
                    '${c.achievements.unlockedCount} из ${c.achievements.total}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _open(const AchievementsScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldDestination extends StatelessWidget {
  const _WorldDestination({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(14),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: worldMint, size: 24),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
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
