import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../domain/achievements.dart';
import '../controller.dart';
import '../finora_assets.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../widgets/common.dart';
import '../widgets/finora_orb.dart';

/// 1.44: the colours and signs of the rarities (never colour alone: the
/// name and the icon are always shown too).
extension AchievementRarityLook on AchievementRarity {
  Color get color => switch (this) {
    AchievementRarity.common => const Color(0xFF8E9AAF),
    AchievementRarity.uncommon => const Color(0xFF1FBF8F),
    AchievementRarity.rare => const Color(0xFF3B8BFF),
    AchievementRarity.epic => const Color(0xFF9B5CFF),
    AchievementRarity.legendary => const Color(0xFFF5B301),
  };

  IconData get icon => switch (this) {
    AchievementRarity.common => Icons.circle_outlined,
    AchievementRarity.uncommon => Icons.spa_rounded,
    AchievementRarity.rare => Icons.diamond_outlined,
    AchievementRarity.epic => Icons.auto_awesome_rounded,
    AchievementRarity.legendary => Icons.workspace_premium_rounded,
  };
}

/// «5 / 7», «18 / 30 дней», «7 450 ₽ / 10 000 ₽», «45% / 100%».
String achievementProgressText(AchievementStatus s, String currency) {
  final current = math.min(s.current, s.target);
  return switch (s.definition.unit) {
    ProgressUnit.count => '$current / ${s.target}',
    ProgressUnit.days => tr('$current / ${s.target} дн.'),
    ProgressUnit.months => tr('$current / ${s.target} мес.'),
    ProgressUnit.money =>
      '${money(current, currency)} / '
          '${money(s.target, currency)}',
    ProgressUnit.percent => '$current% / ${s.target}%',
  };
}

String achievementDate(DateTime d) => displayDate(d);

/// What Finora says at the top of the screen.
String achievementHeaderLine(double share) => share >= 1
    ? 'Все достижения ваши! Я горжусь вами'
    : share >= .8
    ? 'Почти все! Осталось совсем чуть-чуть'
    : share >= .5
    ? 'Больше половины пути — так держать!'
    : share >= .2
    ? 'Хорошее начало, вы на верном пути'
    : 'Каждый шаг считается. Начнём вместе?';

/// The current series, said gently: a broken one is not a failure.
String achievementStreakText(int days) =>
    days == 0 ? tr('Начнём новую серию?') : tr('Серия: $days дн.');

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  /// 'all', 'got', 'progress' or a category name.
  String _filter = 'all';
  FinanceController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = FinanceScope.of(context);
    if (!identical(c, _controller)) {
      _controller = c;
      // What was «Новое» has been seen once the screen is open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(c.markAchievementsSeen());
      });
    }
  }

  bool _shown(AchievementStatus s) => switch (_filter) {
    'all' => true,
    'got' => s.unlocked,
    'progress' => !s.unlocked && !s.definition.secret,
    final category => s.definition.category.name == category,
  };

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final report = c.achievements;
    final theme = Theme.of(context);
    final list = report.statuses.where(_shown).toList()
      ..sort((a, b) {
        if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
        if (a.unlocked) return b.unlockedAt!.compareTo(a.unlockedAt!);
        return b.progress.compareTo(a.progress);
      });
    final filters = <(String, String)>[
      ('all', 'Все'),
      ('got', 'Получено'),
      ('progress', 'В процессе'),
      for (final cat in AchievementCategory.values)
        (cat.name, achievementCategoryNames[cat]!),
    ];
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
    return Scaffold(
      appBar: AppBar(title: const Text('Достижения')),
      body: CustomScrollView(
        key: const ValueKey('achievements-list'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: _Header(report: report, currency: c.currency),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                key: const ValueKey('achievements-filters'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final (id, title) in filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('achievements-filter-$id'),
                        label: Text(title),
                        selected: _filter == id,
                        onSelected: (_) {
                          Haptics.tap();
                          setState(() => _filter = id);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Здесь пока пусто — всё впереди',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 268,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => AchievementCard(
                    status: list[i],
                    currency: c.currency,
                    onTap: () => showAchievement(context, list[i]),
                  ),
                  childCount: list.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.currency});
  final AchievementReport report;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = report.level;
    final mood = AchievementEngine.moodFor(report.share);
    final last = report.last;
    final nearest = report.nearest.take(3).toList();
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: FinoraCharacter(
                      size: 64,
                      moods: [FinoraAssets.mood(mood)],
                      rings: false,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Получено ${report.unlockedCount} из ${report.total}',
                          key: const ValueKey('achievements-count'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(achievementHeaderLine(report.share), style: muted),
                      ],
                    ),
                  ),
                  Text(
                    '${(report.share * 100).round()}%',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AnimatedBar(value: report.share, color: scheme.primary),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.military_tech_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Уровень: ${tr(level.title)}',
                      key: const ValueKey('achievements-level'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    level.next == null
                        ? '${report.points}'
                        : '${report.points} / ${level.next}',
                    style: muted,
                  ),
                ],
              ),
              if (level.next != null) ...[
                const SizedBox(height: 6),
                _AnimatedBar(
                  value:
                      (report.points - level.from) / (level.next! - level.from),
                  color: AchievementRarity.legendary.color,
                  height: 5,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Stat(
                icon: Icons.local_fire_department_rounded,
                color: const Color(0xFFFF8A3D),
                title: achievementStreakText(report.metrics.currentStreak),
                subtitle: report.metrics.bestStreak > 0
                    ? tr('Лучшая: ${report.metrics.bestStreak} дн.')
                    : tr('Серия'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                icon: AchievementRarity.rare.icon,
                color: AchievementRarity.rare.color,
                title: '${report.rareCount}',
                subtitle: tr('Редких и выше'),
              ),
            ),
          ],
        ),
        if (last != null) ...[
          const SizedBox(height: 10),
          SurfaceCard(
            padding: const EdgeInsets.all(14),
            onTap: () => showAchievement(context, last),
            child: Row(
              children: [
                _Thumb(status: last, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Последнее', style: muted),
                      Text(
                        last.definition.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Text(achievementDate(last.unlockedAt!), style: muted),
              ],
            ),
          ),
        ],
        if (nearest.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Ближайшие',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final s in nearest)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                key: ValueKey('achievements-nearest-${s.definition.id}'),
                padding: const EdgeInsets.all(12),
                onTap: () => showAchievement(context, s),
                child: Row(
                  children: [
                    _Thumb(status: s, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.definition.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          _AnimatedBar(
                            value: s.progress,
                            color: s.definition.rarity.color,
                            height: 5,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(achievementProgressText(s, currency), style: muted),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({
    required this.value,
    required this.color,
    this.height = 8,
  });
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
    duration: const Duration(milliseconds: 700),
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height,
        color: color,
        backgroundColor: color.withValues(alpha: .16),
      ),
    ),
  );
}

/// A small square picture of an achievement.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.status, required this.size});
  final AchievementStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = status.definition;
    final hidden = d.secret && !status.unlocked;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .28),
      child: SizedBox.square(
        dimension: size,
        child: hidden
            ? _Mystery(size: size)
            : FinoraArt(
                name: FinoraAssets.achievementArt(d),
                reaction: d.reaction,
                locked: !status.unlocked,
                frame: false,
              ),
      ),
    );
  }
}

class _Mystery extends StatelessWidget {
  const _Mystery({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2B2350), Color(0xFF14122A)],
      ),
    ),
    child: Center(
      child: Text(
        '???',
        style: TextStyle(
          color: Colors.white.withValues(alpha: .8),
          fontWeight: FontWeight.w800,
          fontSize: (size * .28).clamp(14, 40),
          letterSpacing: 2,
        ),
      ),
    ),
  );
}

/// One achievement in the grid.
class AchievementCard extends StatelessWidget {
  const AchievementCard({
    super.key,
    required this.status,
    required this.currency,
    this.onTap,
  });
  final AchievementStatus status;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = status.definition;
    final hidden = d.secret && !status.unlocked;
    final rarity = d.rarity;
    final title = hidden ? '???' : d.title;
    final description = hidden ? 'Секретное достижение' : d.description;
    final glow =
        status.unlocked && rarity.index >= AchievementRarity.epic.index;
    return Semantics(
      button: true,
      label:
          '${tr(title)}. ${tr(description)}. ${tr(rarity.title)}. '
          '${status.unlocked ? tr('Получено') : achievementProgressText(status, currency)}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('achievement-${d.id}'),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: scheme.surface.withValues(alpha: .92),
            border: Border.all(
              color: status.unlocked
                  ? rarity.color.withValues(alpha: .85)
                  : scheme.outlineVariant.withValues(alpha: .5),
              width: status.unlocked ? 1.6 : 1,
            ),
            boxShadow: [
              if (glow)
                BoxShadow(
                  color: rarity.color.withValues(alpha: .35),
                  blurRadius: 18,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 104,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      hidden
                          ? const _Mystery(size: 104)
                          : FinoraArt(
                              name: FinoraAssets.achievementArt(d),
                              reaction: d.reaction,
                              locked: !status.unlocked,
                              frame: false,
                            ),
                      if (!status.unlocked)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black.withValues(
                              alpha: .45,
                            ),
                            child: const Icon(
                              Icons.lock_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (!status.unlocked && !hidden) ...[
                          _AnimatedBar(
                            value: status.progress,
                            color: rarity.color,
                            height: 5,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            achievementProgressText(status, currency),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ] else if (status.unlocked)
                          Text(
                            achievementDate(status.unlockedAt!),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 6),
                        RarityPill(rarity: rarity),
                      ],
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

class RarityPill extends StatelessWidget {
  const RarityPill({super.key, required this.rarity});
  final AchievementRarity rarity;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: rarity.color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(rarity.icon, size: 12, color: rarity.color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            rarity.title,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: rarity.color,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The details of one achievement in a sheet.
Future<void> showAchievement(BuildContext context, AchievementStatus s) {
  final c = FinanceScope.of(context);
  final d = s.definition;
  final hidden = d.secret && !s.unlocked;
  Haptics.tap();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final muted = TextStyle(color: scheme.onSurfaceVariant);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            key: ValueKey('achievement-sheet-${d.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: AspectRatio(
                  aspectRatio: FinoraAssets.cardRatio,
                  child: hidden
                      ? const _Mystery(size: 180)
                      : FinoraArt(
                          name: FinoraAssets.achievementArt(d),
                          reaction: d.reaction,
                          locked: !s.unlocked,
                          semanticLabel: tr(d.title),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hidden ? '???' : d.title,
                      style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  RarityPill(rarity: d.rarity),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hidden
                    ? 'Секретное достижение. Условие откроется, когда вы его получите.'
                    : d.description,
                style: muted,
              ),
              const SizedBox(height: 6),
              Text(
                tr(achievementCategoryNames[d.category]!),
                style: muted.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (s.unlocked) ...[
                Row(
                  children: [
                    Icon(Icons.verified_rounded, color: d.rarity.color),
                    const SizedBox(width: 8),
                    Text('Получено ${achievementDate(s.unlockedAt!)}'),
                  ],
                ),
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: d.rarity.color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '«${tr(AchievementEngine.quote(d))}»',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                ),
              ] else if (!hidden) ...[
                _AnimatedBar(value: s.progress, color: d.rarity.color),
                const SizedBox(height: 6),
                Text(achievementProgressText(s, c.currency), style: muted),
              ],
              const SizedBox(height: 8),
              Text(
                '+${d.rarity.points} ${tr('очков')}',
                style: muted.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The block on the main screen.
class AchievementsCard extends StatelessWidget {
  const AchievementsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final report = c.achievements;
    final scheme = Theme.of(context).colorScheme;
    final next = report.nearest.firstOrNull;
    final fresh = report.newSince(c.data.achievements.seenAt);
    final last = report.last;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SurfaceCard(
        key: const ValueKey('dashboard-achievements'),
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AchievementsScreen()),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 72,
                height: 72,
                child: last == null
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: .12),
                        ),
                        child: Center(
                          child: FinoraCharacter(
                            size: 52,
                            moods: [
                              FinoraAssets.mood(
                                AchievementEngine.moodFor(report.share),
                              ),
                            ],
                            rings: false,
                          ),
                        ),
                      )
                    : FinoraArt(
                        name: FinoraAssets.achievementArt(last.definition),
                        reaction: last.definition.reaction,
                        frame: false,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'Достижения',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (fresh > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          key: const ValueKey('achievements-new-badge'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AchievementRarity.legendary.color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Новое',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Получено ${report.unlockedCount} из ${report.total}',
                    style: muted,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 14,
                        color: Color(0xFFFF8A3D),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          achievementStreakText(report.metrics.currentStreak),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                  if (next != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${tr('Дальше:')} ${tr(next.definition.title)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          achievementProgressText(next, c.currency),
                          style: muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _AnimatedBar(
                      value: next.progress,
                      color: next.definition.rarity.color,
                      height: 5,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1.45: «Достижение получено» — the achievement's card pops up over the
/// whole screen. Several at once come one after another in the same window
/// («1 / 3»), never as a stack of windows.
abstract final class AchievementPopup {
  /// Off in widget tests unless a test turns it on.
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  static OverlayEntry? _entry;
  static final _queue = <AchievementDefinition>[];

  static bool get showing => _entry != null;

  static void show(BuildContext context, List<AchievementDefinition> got) {
    if (!enabled || got.isEmpty) return;
    _queue.addAll(got);
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final navigator = Navigator.of(context);
    final scope = context.findAncestorWidgetOfExactType<FinanceScope>();
    _entry = OverlayEntry(
      builder: (_) => _UnlockStage(
        queue: _queue,
        onOpen: () {
          close();
          final page = MaterialPageRoute<void>(
            builder: (_) => scope == null
                ? const AchievementsScreen()
                : FinanceScope(
                    controller: scope.notifier!,
                    child: const AchievementsScreen(),
                  ),
          );
          unawaited(navigator.push(page));
        },
        onClose: close,
      ),
    );
    overlay.insert(_entry!);
  }

  static void close() {
    _entry?.remove();
    _entry = null;
    _queue.clear();
  }
}

class _UnlockStage extends StatefulWidget {
  const _UnlockStage({
    required this.queue,
    required this.onOpen,
    required this.onClose,
  });
  final List<AchievementDefinition> queue;
  final VoidCallback onOpen, onClose;

  @override
  State<_UnlockStage> createState() => _UnlockStageState();
}

class _UnlockStageState extends State<_UnlockStage>
    with TickerProviderStateMixin {
  /// The dimmed, blurred screen behind.
  late final _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  /// The card popping up (again for each next one).
  late final _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// A gleam running over the card and the confetti.
  late final _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  int _index = 0;
  String _quote = '';
  bool _leaving = false;

  AchievementDefinition get _current => widget.queue[_index];

  @override
  void initState() {
    super.initState();
    _enter();
  }

  void _enter() {
    final d = _current;
    _quote = tr(AchievementEngine.quote(d));
    switch (d.rarity) {
      case AchievementRarity.legendary || AchievementRarity.epic:
        unawaited(Haptics.success());
      case AchievementRarity.rare:
        Haptics.heavy();
      default:
        Haptics.medium();
    }
    _pop.forward(from: 0);
    _shine.forward(from: 0);
  }

  Future<void> _next() async {
    if (_leaving) return;
    if (_index + 1 < widget.queue.length) {
      Haptics.tap();
      await _pop.reverse();
      if (!mounted) return;
      setState(() => _index++);
      _enter();
      return;
    }
    _leaving = true;
    await Future.wait([_pop.reverse(), _back.reverse()]);
    widget.onClose();
  }

  @override
  void dispose() {
    _back.dispose();
    _pop.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _current;
    final color = d.rarity.color;
    final total = widget.queue.length;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 40, 520.0);
    final high = d.rarity.index >= AchievementRarity.epic.index;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        key: const ValueKey('achievement-popup'),
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: AnimatedBuilder(
                animation: _back,
                builder: (context, _) => BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: 8 * _back.value,
                    sigmaY: 8 * _back.value,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: .62 * _back.value),
                  ),
                ),
              ),
            ),
          ),
          if (high)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _shine,
                  builder: (context, _) => CustomPaint(
                    painter: _Confetti(
                      t: _shine.value,
                      gold: d.rarity == AchievementRarity.legendary,
                    ),
                  ),
                ),
              ),
            ),
          Center(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: AnimatedBuilder(
                  animation: _pop,
                  builder: (context, child) {
                    final v = _pop.value;
                    final scale = .35 + .65 * Curves.elasticOut.transform(v);
                    return Opacity(
                      opacity: Curves.easeOut.transform(
                        (v * 2.5).clamp(0.0, 1.0),
                      ),
                      child: Transform.rotate(
                        angle: (1 - Curves.easeOutBack.transform(v)) * -.12,
                        child: Transform.scale(scale: scale, child: child),
                      ),
                    );
                  },
                  child: SizedBox(
                    width: width,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ДОСТИЖЕНИЕ ПОЛУЧЕНО',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            shadows: [Shadow(color: color, blurRadius: 12)],
                          ),
                        ),
                        if (total > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_index + 1} / $total',
                              key: const ValueKey('achievement-popup-count'),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: _next,
                          child: _ShiningCard(
                            definition: d,
                            shine: _shine,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          d.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          d.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        RarityPill(rarity: d.rarity),
                        const SizedBox(height: 12),
                        Text(
                          '«$_quote»',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontStyle: FontStyle.italic,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                key: const ValueKey('achievement-popup-open'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white54),
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: widget.onOpen,
                                child: const Text('Посмотреть'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey('achievement-popup-next'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: color,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: _next,
                                child: Text(
                                  _index + 1 < total ? 'Далее' : 'Отлично!',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
}

/// The achievement's own card with its glow and a gleam running over it.
class _ShiningCard extends StatelessWidget {
  const _ShiningCard({
    required this.definition,
    required this.shine,
    required this.color,
  });
  final AchievementDefinition definition;
  final Animation<double> shine;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .7),
          blurRadius: definition.rarity == AchievementRarity.legendary
              ? 46
              : 28,
          spreadRadius: 2,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: AspectRatio(
        aspectRatio: FinoraAssets.cardRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FinoraArt(
              name: FinoraAssets.achievementArt(definition),
              reaction: definition.reaction,
              semanticLabel: tr(definition.title),
            ),
            IgnorePointer(
              child: AnimatedBuilder(
                animation: shine,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(shine.value);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-2.2 + 4 * t, -1),
                        end: Alignment(-1.2 + 4 * t, 1),
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: .35),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bits of colour flying over the screen (epic and legendary only).
class _Confetti extends CustomPainter {
  const _Confetti({required this.t, required this.gold});
  final double t;
  final bool gold;

  static const _colors = [
    Color(0xFFF5B301),
    Color(0xFF9B5CFF),
    Color(0xFF1FBF8F),
    Color(0xFF3B8BFF),
    Color(0xFFFF6FA8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final random = math.Random(7);
    final count = gold ? 90 : 50;
    final fade = 1 - t;
    final center = Offset(size.width / 2, size.height * .42);
    for (var i = 0; i < count; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final speed = size.shortestSide * (.25 + random.nextDouble() * .55);
      final p =
          center +
          Offset(math.cos(angle), math.sin(angle)) * speed * t +
          Offset(0, size.height * .35 * t * t);
      final color = gold && i.isEven
          ? _colors.first
          : _colors[i % _colors.length];
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle + t * 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-5, -2.5, 10, 5),
          const Radius.circular(1.5),
        ),
        Paint()..color = color.withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confetti old) => old.t != t;
}
