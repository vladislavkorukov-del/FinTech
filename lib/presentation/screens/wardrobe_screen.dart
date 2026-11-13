import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../domain/achievements.dart';
import '../../domain/wardrobe.dart';
import '../controller.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../widgets/common.dart';
import '../widgets/finora_dressed.dart';
import '../widgets/finora_orb.dart';
import 'achievements_screen.dart';

/// Where an item comes from, as the person reads it.
String wardrobeSourceText(WardrobeItem item, {required bool open}) {
  if (item.secret && !open) return '???';
  return switch (item.source) {
    AchievementReward(:final achievementId) => () {
      final d = achievementDefinitions
          .where((a) => a.id == achievementId)
          .firstOrNull;
      return d == null ? '' : '${tr('За достижение')} «${tr(d.title)}»';
    }(),
    EventReward() => tr('Особое событие'),
  };
}

/// What to do to open a closed item (none for a secret one).
String? wardrobeCondition(WardrobeItem item) {
  if (item.secret) return null;
  if (item.source case EventReward(:final condition)) {
    return condition == null ? tr('Особое событие') : tr(condition);
  }
  final id = item.achievementId;
  final d = achievementDefinitions.where((a) => a.id == id).firstOrNull;
  return d == null ? null : tr(d.description);
}

/// 1.46: «Гардероб Finora» — what she can wear, on her right away.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key, this.initialCategory});
  final WardrobeCategory? initialCategory;

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  late WardrobeCategory? _category = widget.initialCategory;
  Future<void> _toggle(FinanceController c, WardrobeItem item) async {
    final worn = c.data.wardrobe.equipped[item.slot] == item.id;
    Haptics.tap();
    try {
      if (worn) {
        await c.takeOff(item.slot);
      } else {
        await c.wear(item.id);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final state = c.data.wardrobe;
    final achievements = c.data.achievements;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = {
      for (final i in wardrobeItems)
        if (Wardrobe.open(i, achievements, state)) i.id,
    };
    final list = wardrobeItems
        .where((i) => _category == null || i.category == _category)
        .toList();
    final worn = Wardrobe.worn(state);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final glow = FinoraOrbPainter.mint;
    return Scaffold(
      appBar: AppBar(title: const Text('Гардероб Finora')),
      body: CustomScrollView(
        key: const ValueKey('wardrobe-list'),
        slivers: [
          // 1.56: a showcase stage — Finora under a soft spotlight in her own
          // color, a floor shadow, what she wears and the collection progress.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: ClipRSuperellipse(
                key: const ValueKey('wardrobe-preview'),
                borderRadius: BorderRadius.circular(28),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.lerp(const Color(0xFF0B1418), glow, .16)!,
                        const Color(0xFF0A0D10),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -.25),
                              radius: .75,
                              colors: [
                                glow.withValues(alpha: .34),
                                glow.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (context, box) {
                                final size =
                                    (box.maxWidth / FinoraDressed.widthFactor)
                                        .clamp(70.0, 150.0);
                                return Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    // The floor under her.
                                    Container(
                                      width: size * 1.5,
                                      height: size * .22,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          size,
                                        ),
                                        gradient: RadialGradient(
                                          colors: [
                                            Colors.black.withValues(alpha: .4),
                                            Colors.black.withValues(alpha: 0),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: size * .05,
                                      ),
                                      child: Semantics(
                                        label: worn.isEmpty
                                            ? tr('Финора')
                                            : '${tr('Финора')}: ${worn.map((i) => tr(i.name)).join(', ')}',
                                        child: AnimatedSize(
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          child: FinoraDressed(
                                            size: size,
                                            outfit: worn,
                                            moods: const [FinoraMood.happy],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            if (worn.isNotEmpty)
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                alignment: WrapAlignment.center,
                                children: [
                                  for (final item in worn)
                                    _GlassPill(
                                      text: tr(item.name),
                                      color: item.rarity.color,
                                    ),
                                ],
                              )
                            else
                              Text(
                                'Выберите открытого компаньона или плащ',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: .7),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Text(
                                  'Коллекция',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: .7),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Открыто ${open.length} из ${wardrobeItems.length}',
                                    key: const ValueKey('wardrobe-count'),
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: wardrobeItems.isEmpty
                                    ? 0
                                    : open.length / wardrobeItems.length,
                                minHeight: 4,
                                color: glow,
                                backgroundColor: Colors.white.withValues(
                                  alpha: .12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // A segmented switcher instead of loose chips.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: ShapeDecoration(
                  color: scheme.onSurface.withValues(alpha: .07),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  children: [
                    for (final filter in <(WardrobeCategory?, String)>[
                      (null, 'Все'),
                      (WardrobeCategory.companion, 'Компаньоны'),
                      (WardrobeCategory.cape, 'Плащи'),
                    ])
                      Expanded(
                        child: GestureDetector(
                          key: ValueKey(
                            'wardrobe-filter-${filter.$1?.name ?? "all"}',
                          ),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Haptics.tap();
                            setState(() => _category = filter.$1);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: ShapeDecoration(
                              color: _category == filter.$1
                                  ? scheme.surface
                                  : Colors.transparent,
                              shape: const StadiumBorder(),
                              shadows: _category == filter.$1
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: .12,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              filter.$2,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 14,
                                color: _category == filter.$1
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 176 + 130 * textScale,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => WardrobeCard(
                  item: list[i],
                  open: open.contains(list[i].id),
                  worn: state.equipped[list[i].slot] == list[i].id,
                  onToggle: () => _toggle(c, list[i]),
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

/// A small frosted label on the showcase stage.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: ShapeDecoration(
      color: Colors.white.withValues(alpha: .1),
      shape: StadiumBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: .16), width: .8),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One item in the grid (1.56): a glass card with the item on a soft stage
/// tinted by its rarity, a quiet rarity mark and one compact action.
class WardrobeCard extends StatelessWidget {
  const WardrobeCard({
    super.key,
    required this.item,
    required this.open,
    required this.worn,
    required this.onToggle,
  });

  final WardrobeItem item;
  final bool open, worn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rarity = item.rarity;
    final hidden = item.secret && !open;
    final name = hidden ? '???' : item.name;
    final status = worn
        ? 'Надето'
        : open
        ? 'Открыто'
        : 'Закрыто';
    final condition = open ? null : wardrobeCondition(item);
    final muted = TextStyle(
      fontSize: 12,
      height: 1.3,
      color: scheme.onSurfaceVariant,
    );
    Widget picture = Image.asset(
      item.asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      cacheWidth: (MediaQuery.devicePixelRatioOf(context) * 192).ceil().clamp(
        128,
        768,
      ),
      excludeFromSemantics: true,
    );
    if (!open) {
      // A closed item: only its shape, in the text colour, dimmed.
      picture = ColorFiltered(
        colorFilter: ColorFilter.mode(
          scheme.onSurface.withValues(alpha: .22),
          BlendMode.srcIn,
        ),
        child: picture,
      );
    }
    return Semantics(
      container: true,
      label:
          '${tr(name)}. ${tr(rarity.title)}. ${tr(status)}. '
          '${wardrobeSourceText(item, open: open)}',
      child: KeyedSubtree(
        key: ValueKey('wardrobe-${item.id}'),
        child: GlassSurface(
          radius: 22,
          tint: worn ? rarity.color : null,
          tintStrength: 2,
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The item on its own small stage.
              SizedBox(
                height: 108,
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -.1),
                        radius: .85,
                        colors: [
                          rarity.color.withValues(alpha: open ? .26 : .08),
                          rarity.color.withValues(alpha: open ? .06 : .02),
                        ],
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: picture,
                        ),
                        if (hidden)
                          Center(
                            child: Text(
                              '???',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface.withValues(alpha: .6),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: worn
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: ShapeDecoration(
                                    color: rarity.color,
                                    shape: const StadiumBorder(),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_rounded,
                                        size: 12,
                                        color: Colors.black,
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        'Надето',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : !open
                              ? Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: ShapeDecoration(
                                    color: scheme.surface.withValues(alpha: .8),
                                    shape: const CircleBorder(),
                                  ),
                                  child: Icon(
                                    Icons.lock_rounded,
                                    size: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(height: 1.2),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: rarity.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            worn ? rarity.title : '${rarity.title} · $status',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                  child: Text(
                    open
                        ? wardrobeSourceText(item, open: true)
                        : condition ?? '???',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
              ),
              if (open)
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: worn
                      ? OutlinedButton(
                          key: ValueKey('wardrobe-toggle-${item.id}'),
                          onPressed: onToggle,
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Снять'),
                        )
                      : FilledButton(
                          key: ValueKey('wardrobe-toggle-${item.id}'),
                          onPressed: onToggle,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: const StadiumBorder(),
                            backgroundColor: scheme.primary,
                            foregroundColor:
                                ThemeData.estimateBrightnessForColor(
                                      scheme.primary,
                                    ) ==
                                    Brightness.dark
                                ? Colors.white
                                : const Color(0xFF14110D),
                          ),
                          child: const Text('Надеть'),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A short line about items a set of achievements brought (for the unlock
/// window), or null.
String? wardrobeRewardLine(AchievementDefinition d) {
  final items = Wardrobe.rewardsOf(d.id);
  if (items.isEmpty) return null;
  return '${tr('Новое в гардеробе:')} ${items.map((i) => tr(i.name)).join(', ')}';
}

/// Opens the wardrobe (used by «Ещё» and the achievements screen).
Future<void> openWardrobe(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const WardrobeScreen()));
