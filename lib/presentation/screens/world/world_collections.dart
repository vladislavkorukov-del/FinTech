import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../../domain/wardrobe.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../wardrobe_screen.dart';
import 'world_components.dart';

class WorldCollectionsScreen extends StatelessWidget {
  const WorldCollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final wardrobe = c.data.wardrobe;
    return WorldPage(
      title: 'Коллекции',
      children: [
        for (final collection in worldCollections)
          WorldPanel(
            key: ValueKey('world-collection-${collection.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: collection.count(wardrobe) / collection.itemIds.length,
                  color: worldMint,
                  backgroundColor: worldMint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                  minHeight: 5,
                ),
                const SizedBox(height: 8),
                Text(
                  '${collection.count(wardrobe)} из ${collection.itemIds.length}',
                ),
                const SizedBox(height: 12),
                for (final id in collection.itemIds)
                  if (Wardrobe.item(id) case final item?)
                    _CollectionItem(
                      item: item,
                      owned: Wardrobe.open(item, c.data.achievements, wardrobe),
                    ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => worldOpen(context, const WardrobeScreen()),
          icon: const Icon(Icons.checkroom_outlined),
          label: const Text('Открыть гардероб'),
        ),
      ],
    );
  }
}

class _CollectionItem extends StatelessWidget {
  const _CollectionItem({required this.item, required this.owned});
  final WardrobeItem item;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final hidden = item.secret && !owned;
    Widget image = Image.asset(
      item.asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      cacheWidth: 192,
      excludeFromSemantics: true,
    );
    if (!owned) {
      image = ColorFiltered(
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.onSurface.withValues(alpha: .24),
          BlendMode.srcIn,
        ),
        child: image,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 56, height: 64, child: image),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hidden ? '???' : item.name),
                const SizedBox(height: 3),
                Text(
                  owned
                      ? 'В коллекции'
                      : wardrobeCondition(item) ??
                            wardrobeSourceText(item, open: false),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            owned ? Icons.check_circle_outline : Icons.lock_outline,
            color: owned
                ? worldMint
                : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 19,
          ),
        ],
      ),
    );
  }
}
