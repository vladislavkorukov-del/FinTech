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
  final id = item.achievementId;
  final d = achievementDefinitions.where((a) => a.id == id).firstOrNull;
  return d == null ? null : tr(d.description);
}

/// 1.46: «Гардероб Finora» — what she can wear, on her right away.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
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
    const list = wardrobeItems;
    final worn = Wardrobe.worn(state);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Гардероб Finora')),
      body: CustomScrollView(
        key: const ValueKey('wardrobe-list'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SurfaceCard(
                key: const ValueKey('wardrobe-preview'),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, box) {
                        // The biggest Finora that fits the card.
                        final size = (box.maxWidth / FinoraDressed.widthFactor)
                            .clamp(60.0, 130.0);
                        return Center(
                          child: Semantics(
                            label: worn.isEmpty
                                ? tr('Финора')
                                : '${tr('Финора')}: ${worn.map((i) => tr(i.name)).join(', ')}',
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              child: FinoraDressed(
                                size: size,
                                outfit: worn,
                                moods: const [FinoraMood.happy],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Text(
                      'Открыто ${open.length} из ${wardrobeItems.length}',
                      key: const ValueKey('wardrobe-count'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      worn.isEmpty
                          ? 'Нажмите «Надеть» на открытом компаньоне'
                          : 'Компаньон парит рядом с Финорой',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 166 + 150 * textScale,
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

/// One item in the grid.
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
    final scheme = Theme.of(context).colorScheme;
    final rarity = item.rarity;
    final hidden = item.secret && !open;
    final name = hidden ? '???' : item.name;
    final status = worn
        ? 'Надето'
        : open
        ? 'Открыто'
        : 'Закрыто';
    final condition = open ? null : wardrobeCondition(item);
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    Widget picture = Image.asset(
      item.asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
    if (!open) {
      // A closed item: only its shape, in the text colour, dimmed.
      picture = ColorFiltered(
        colorFilter: ColorFilter.mode(
          scheme.onSurface.withValues(alpha: .28),
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
      child: DecoratedBox(
        key: ValueKey('wardrobe-${item.id}'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: scheme.surface.withValues(alpha: .92),
          border: Border.all(
            color: worn
                ? rarity.color
                : open
                ? rarity.color.withValues(alpha: .45)
                : scheme.outlineVariant.withValues(alpha: .5),
            width: worn ? 2 : 1,
          ),
          boxShadow: [
            if (worn || (open && rarity.index >= AchievementRarity.epic.index))
              BoxShadow(
                color: rarity.color.withValues(alpha: worn ? .3 : .16),
                blurRadius: 14,
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 92,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(padding: const EdgeInsets.all(4), child: picture),
                    if (hidden)
                      Center(
                        child: Text(
                          '???',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface.withValues(alpha: .7),
                          ),
                        ),
                      ),
                    if (worn)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: rarity.color,
                          child: const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.black,
                          ),
                        ),
                      )
                    else if (!open)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Icon(
                          Icons.lock_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RarityPill(rarity: rarity),
                  Text(
                    status,
                    style: muted.copyWith(
                      fontWeight: FontWeight.w700,
                      color: worn ? rarity.color : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  open
                      ? wardrobeSourceText(item, open: true)
                      : condition ?? '???',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
              if (open)
                SizedBox(
                  width: double.infinity,
                  child: worn
                      ? OutlinedButton(
                          key: ValueKey('wardrobe-toggle-${item.id}'),
                          onPressed: onToggle,
                          child: const Text('Снять'),
                        )
                      : FilledButton.tonal(
                          key: ValueKey('wardrobe-toggle-${item.id}'),
                          onPressed: onToggle,
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
