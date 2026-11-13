import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import 'world_art.dart';
export 'world_art.dart';

const worldMint = Color(0xFF9DE5C7);

/// The world's surfaces use the existing Finance glass and theme tokens.
class WorldPage extends StatelessWidget {
  const WorldPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
  });
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final world = FinanceScope.of(context).data.world;
    return WorldTheme(
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                MediaQuery.disableAnimationsOf(context) || world.reducedMotion,
          ),
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: Navigator.canPop(context)
                  ? WorldImageButton(
                      id: 'back',
                      label: 'Назад',
                      onPressed: () => Navigator.maybePop(context),
                    )
                  : null,
              actions: actions,
            ),
            body: SafeArea(
              top: false,
              child: ListView(
                key: ValueKey('world-page-$title'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorldPanel extends StatelessWidget {
  const WorldPanel({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: WorldPearlSurface(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: child,
    ),
  );
}

class WorldHeading extends StatelessWidget {
  const WorldHeading(this.text, {super.key, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class WorldStat extends StatelessWidget {
  const WorldStat({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: worldMint),
        const SizedBox(width: 7),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    ),
  );
}

Future<void> worldAttempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

Future<void> worldOpen(BuildContext context, Widget screen) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _WorldRouteMotion(child: WorldTheme(child: screen)),
      ),
    );

/// Navigator pages do not inherit the MediaQuery below the previous route.
/// Carry the world's calm preference into reused wardrobe/achievement pages,
/// and stop their existing tickers when covered or the app is backgrounded.
class _WorldRouteMotion extends StatefulWidget {
  const _WorldRouteMotion({required this.child});
  final Widget child;
  @override
  State<_WorldRouteMotion> createState() => _WorldRouteMotionState();
}

class _WorldRouteMotionState extends State<_WorldRouteMotion>
    with WidgetsBindingObserver {
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _active = state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        FinanceScope.of(context).data.world.reducedMotion;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: TickerMode(
        enabled:
            _active && !reduced && (ModalRoute.isCurrentOf(context) ?? true),
        child: widget.child,
      ),
    );
  }
}

IconData worldCosmeticIcon(String id) => switch (id) {
  'crystal' => Icons.diamond_outlined,
  'tea' => Icons.emoji_food_beverage_outlined,
  'star' => Icons.auto_awesome_outlined,
  'plant' => Icons.spa_outlined,
  'moon' => Icons.nightlight_outlined,
  'lantern' => Icons.light_outlined,
  'night' => Icons.dark_mode_outlined,
  'garden' => Icons.local_florist_outlined,
  'aurora' => Icons.waves_outlined,
  'pearl' => Icons.circle_outlined,
  _ => Icons.bubble_chart_outlined,
};

WorldCosmetic? worldCosmetic(String id) =>
    worldCosmetics.where((item) => item.id == id).firstOrNull;

bool worldOwns(WorldState world, WorldCosmetic item) =>
    item.price == 0 || world.purchases.contains(item.id);

String worldSlotName(String slot) => switch (slot) {
  'left' => 'Левая подставка',
  'right' => 'Правая подставка',
  _ => 'Полка',
};
