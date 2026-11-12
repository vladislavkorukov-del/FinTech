import '../i18n.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide InputDecoration, Text;
import '../controller.dart';
import '../screens/management.dart';
import '../screens/settings.dart';
import 'common.dart' show money;
import 'motion.dart';
import '../l10n_widgets.dart';

class FinanceBrand extends StatefulWidget {
  const FinanceBrand({super.key, this.animated = true});
  final bool animated;
  static const originalAsset = 'assets/brand/Finance_F_5000_rub_texture_v7.png';
  static const asset = 'assets/brand/Finance_F_transparent.png';
  @override
  State<FinanceBrand> createState() => _FinanceBrandState();
}

class _FinanceBrandState extends State<FinanceBrand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  Timer? _timer;
  bool _enabled = false;

  void _configure() {
    final enabled =
        widget.animated &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        TickerMode.valuesOf(context).enabled;
    if (_enabled == enabled) return;
    _enabled = enabled;
    _timer?.cancel();
    _timer = null;
    if (enabled) {
      _motion.forward(from: 0);
      _timer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (mounted && _enabled) _motion.forward(from: 0);
      });
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(covariant FinanceBrand oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: Image.asset(
      FinanceBrand.asset,
      semanticLabel: 'Finora',
      fit: BoxFit.contain,
      isAntiAlias: true,
      filterQuality: FilterQuality.high,
    ),
    builder: (context, child) {
      final wave = math.sin(_motion.value * math.pi * 2);
      return Transform.translate(
        key: const ValueKey('finance-logo-motion'),
        offset: Offset(0, -wave * 1.1),
        child: Transform.rotate(
          angle: wave * .018,
          child: Transform.scale(
            scale: 1 + math.sin(_motion.value * math.pi) * .025,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Top of the dashboard, after Apple Wallet: two quiet round buttons
/// (settings, family) and below them the total balance in the selected
/// currency (from [FinanceController.balance]) as the one large number on
/// the screen. The app mark is kept for the launch screen.
class FinanceHeader extends StatelessWidget {
  const FinanceHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = FinanceScope.of(context);
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      minimumSize: const Size(40, 40),
      fixedSize: const Size(40, 40),
      padding: EdgeInsets.zero,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: tr('Настройки'),
                onPressed: () => open(const SettingsScreen()),
                style: buttonStyle,
                icon: const Icon(Icons.tune_rounded, size: 19),
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: tr('Моя семья'),
                onPressed: () => open(const MembersScreen()),
                style: buttonStyle,
                icon: const Icon(Icons.family_restroom_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            button: true,
            label: 'Общий баланс ${money(c.balance, c.currency)}',
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('header-balance'),
              behavior: HitTestBehavior.opaque,
              onTap: () => open(const AccountsScreen()),
              child: PressScale(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${tr('Общий баланс')} · ${c.currency}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedMoney(
                          c.balance,
                          currency: c.currency,
                          textKey: const ValueKey('header-balance-amount'),
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 44,
                            height: 1.1,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
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
