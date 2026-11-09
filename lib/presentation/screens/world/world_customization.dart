import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../../domain/wardrobe.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import '../wardrobe_screen.dart';
import 'world_components.dart';

/// The package's six previews use the existing ownership and persistence rules.
class WorldBackgroundScreen extends StatefulWidget {
  const WorldBackgroundScreen({super.key});
  @override
  State<WorldBackgroundScreen> createState() => _WorldBackgroundScreenState();
}

class _WorldBackgroundScreenState extends State<WorldBackgroundScreen> {
  String? _saving;
  Future<void> _select(String id) async {
    if (_saving != null) return;
    setState(() => _saving = id);
    final c = FinanceScope.of(context);
    await worldAttempt(context, () => c.configureWorld(id, c.data.world.decor));
    if (mounted) setState(() => _saving = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final world = c.data.world;
    return WorldPage(
      title: 'Фон дома',
      children: [
        const Text('Выбор применяется сразу и сохраняется на устройстве.'),
        const SizedBox(height: 14),
        for (final art in worldBackgroundArt)
          Builder(
            builder: (context) {
              final item = worldCosmetic(art.cosmeticId);
              final owned = item != null && worldOwns(world, item);
              final selected = world.background == art.cosmeticId;
              return WorldPanel(
                key: ValueKey('world-background-${art.cosmeticId}'),
                onTap: _saving != null
                    ? null
                    : owned
                    ? () => _select(art.cosmeticId)
                    : () => worldOpen(context, const WorldCatalogScreen()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AspectRatio(
                        aspectRatio: 1.6,
                        child: Image.asset(
                          art.asset,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (MediaQuery.sizeOf(context).width *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .ceil()
                                  .clamp(256, 768),
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            art.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : owned
                              ? Icons.radio_button_unchecked
                              : Icons.lock_outline,
                          color: selected ? worldJade : worldPlum,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _saving == art.cosmeticId
                          ? 'Сохраняем…'
                          : selected
                          ? 'Выбран'
                          : owned
                          ? 'Выбрать'
                          : 'Условия открытия — в существующем каталоге',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class WorldDecorScreen extends StatelessWidget {
  const WorldDecorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final world = c.data.world;
    final backgrounds = worldCosmetics.where((i) => i.kind == 'background');
    final decor = worldCosmetics.where(
      (i) => i.kind == 'decor' && worldOwns(world, i),
    );
    return WorldPage(
      title: 'Оформление дома',
      children: [
        const WorldHeading('Фон'),
        OutlinedButton.icon(
          onPressed: () => worldOpen(context, const WorldBackgroundScreen()),
          icon: const WorldArtImage('background', size: 30),
          label: const Text('Посмотреть все фоны'),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in backgrounds)
              ChoiceChip(
                key: ValueKey('world-background-${item.id}'),
                avatar: Icon(
                  worldCosmeticIcon(item.id),
                  color: Color(item.color),
                  size: 18,
                ),
                label: Text(item.name),
                selected: world.background == item.id,
                onSelected: worldOwns(world, item)
                    ? (_) => worldAttempt(
                        context,
                        () => c.configureWorld(item.id, world.decor),
                      )
                    : null,
              ),
          ],
        ),
        const WorldHeading('Места для декора'),
        for (final slot in const ['left', 'right', 'shelf'])
          WorldPanel(
            child: DropdownButtonFormField<String>(
              key: ValueKey('world-slot-$slot-${world.decor[slot]}'),
              initialValue: world.decor[slot] ?? '',
              isExpanded: true,
              decoration: InputDecoration(labelText: worldSlotName(slot)),
              items: [
                const DropdownMenuItem(value: '', child: Text('Свободно')),
                for (final item in decor)
                  DropdownMenuItem(
                    value: item.id,
                    child: Row(
                      children: [
                        Icon(worldCosmeticIcon(item.id), size: 19),
                        const SizedBox(width: 8),
                        Flexible(child: Text(item.name)),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                final updated = Map<String, String>.of(world.decor);
                if (value.isEmpty) {
                  updated.remove(slot);
                } else {
                  updated[slot] = value;
                }
                worldAttempt(
                  context,
                  () => c.configureWorld(world.background, updated),
                );
              },
            ),
          ),
        if (decor.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Декор можно получить за искры в каталоге.'),
          ),
        FilledButton.tonalIcon(
          key: const ValueKey('world-open-catalog'),
          onPressed: () => worldOpen(context, const WorldCatalogScreen()),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Каталог декора'),
        ),
      ],
    );
  }
}

class WorldCatalogScreen extends StatefulWidget {
  const WorldCatalogScreen({super.key});
  @override
  State<WorldCatalogScreen> createState() => _WorldCatalogScreenState();
}

class _WorldCatalogScreenState extends State<WorldCatalogScreen> {
  String? _buying;

  Future<void> _buy(String id) async {
    if (_buying != null) return;
    setState(() => _buying = id);
    await worldAttempt(
      context,
      () => FinanceScope.of(context).purchaseWorldCosmetic(id),
    );
    if (mounted) setState(() => _buying = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final world = c.data.world;
    return WorldPage(
      title: 'Каталог декора',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            WorldStat(icon: Icons.auto_awesome, text: '${world.sparks} искр'),
            WorldStat(
              icon: Icons.bolt_outlined,
              text: '${c.worldPoints} опыта',
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text('Искры нужны только для оформления мира. Это не деньги.'),
        ),
        for (final item in worldCosmetics)
          Builder(
            builder: (context) {
              final owned = worldOwns(world, item);
              final unlocked = c.worldPoints >= item.minPoints;
              final canBuy = unlocked && world.sparks >= item.price;
              return WorldPanel(
                key: ValueKey('world-cosmetic-${item.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Color(item.color).withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Color(item.color).withValues(alpha: .3),
                            ),
                          ),
                          child: item.kind == 'background'
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.asset(
                                    WorldArt.background(item.id).asset,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    cacheWidth: 138,
                                    excludeFromSemantics: true,
                                  ),
                                )
                              : Icon(
                                  worldCosmeticIcon(item.id),
                                  color: Color(item.color),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                item.kind == 'background' ? 'Фон' : 'Декор',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (owned)
                          const Icon(
                            Icons.check_circle_outline,
                            color: worldMint,
                          ),
                      ],
                    ),
                    if (!owned) ...[
                      const SizedBox(height: 12),
                      if (!unlocked)
                        Text('Откроется при ${item.minPoints} опыта')
                      else if (!canBuy)
                        Text('Не хватает ${item.price - world.sparks} искр'),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          key: ValueKey('world-buy-${item.id}'),
                          onPressed: canBuy && _buying == null
                              ? () => _buy(item.id)
                              : null,
                          child: Text(
                            _buying == item.id
                                ? 'Сохраняем…'
                                : '${item.price} искр',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class WorldOutfitsScreen extends StatefulWidget {
  const WorldOutfitsScreen({super.key});
  @override
  State<WorldOutfitsScreen> createState() => _WorldOutfitsScreenState();
}

class _WorldOutfitsScreenState extends State<WorldOutfitsScreen> {
  bool _saving = false;

  Future<void> _save() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _OutfitNameDialog(),
    );
    if (name == null || !mounted) return;
    setState(() => _saving = true);
    await worldAttempt(
      context,
      () => FinanceScope.of(context).saveWorldOutfit(name),
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final world = c.data.world;
    final worn = Wardrobe.worn(c.data.wardrobe);
    return WorldPage(
      title: 'Готовые образы',
      children: [
        WorldPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Сейчас надето',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                worn.isEmpty
                    ? 'Без аксессуаров'
                    : worn.map((i) => i.name).join(' · '),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => worldOpen(context, const WardrobeScreen()),
                icon: const Icon(Icons.checkroom_outlined),
                label: const Text('Выбрать в гардеробе'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('world-save-outfit'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Сохранить образ'),
              ),
            ],
          ),
        ),
        if (world.outfits.isEmpty)
          const EmptyState(
            'Пока нет сохранённых образов',
            'Выберите компаньона и плащ, затем сохраните сочетание.',
          ),
        for (final outfit in world.outfits)
          WorldPanel(
            key: ValueKey('world-outfit-${outfit.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  outfit.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final id in outfit.equipped.values)
                      if (Wardrobe.item(id) case final item?)
                        Tooltip(
                          message: item.name,
                          child: Image.asset(
                            item.asset,
                            width: 64,
                            height: 64,
                            fit: BoxFit.contain,
                            cacheWidth: 192,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                    if (outfit.equipped.isEmpty) const Text('Без аксессуаров'),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      key: ValueKey('world-apply-outfit-${outfit.id}'),
                      onPressed: () => worldAttempt(
                        context,
                        () => c.applyWorldOutfit(outfit.id),
                      ),
                      child: const Text('Надеть'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final remove = await confirm(
                          context,
                          'Удалить образ?',
                          'Предметы останутся в гардеробе.',
                        );
                        if (remove && context.mounted) {
                          await worldAttempt(
                            context,
                            () => c.deleteWorldOutfit(outfit.id),
                          );
                        }
                      },
                      child: const Text('Удалить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OutfitNameDialog extends StatefulWidget {
  const _OutfitNameDialog();
  @override
  State<_OutfitNameDialog> createState() => _OutfitNameDialogState();
}

class _OutfitNameDialogState extends State<_OutfitNameDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    if (_input.text.trim().isNotEmpty) {
      Navigator.pop(context, _input.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Сохранить текущий образ'),
    content: TextField(
      key: const ValueKey('world-outfit-name'),
      controller: _input,
      autofocus: true,
      maxLength: 40,
      decoration: const InputDecoration(labelText: 'Название'),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      TextButton(
        key: const ValueKey('world-outfit-confirm'),
        onPressed: _save,
        child: const Text('Сохранить'),
      ),
    ],
  );
}
