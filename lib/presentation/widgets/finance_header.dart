import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../controller.dart';
import '../screens/management.dart';
import '../screens/settings.dart';
import '../theme/app_theme.dart';
import 'common.dart' show money;
import 'motion.dart';

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
      semanticLabel: 'Finance',
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

/// Top bar of the dashboard: settings, the total balance in the selected
/// currency (from [FinanceController.balance]) and the family profile.
/// The app mark is kept for the launch screen; the header no longer repeats it.
class FinanceHeader extends StatelessWidget {
  const FinanceHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = FinanceScope.of(context);
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: colors.iconBackground,
      foregroundColor: colors.iconForeground,
      minimumSize: const Size(48, 48),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Настройки',
            onPressed: () => open(const SettingsScreen()),
            style: buttonStyle,
            icon: const Icon(Icons.tune_rounded, size: 21),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Общий баланс ${money(c.balance, c.currency)}',
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('header-balance'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => open(const AccountsScreen()),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    // Soft accent halo behind the total balance.
                    gradient: RadialGradient(
                      radius: 1.4,
                      colors: [
                        scheme.primary.withValues(alpha: .18),
                        scheme.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Общий баланс · ${c.currency}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: .2,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AnimatedMoney(
                            c.balance,
                            currency: c.currency,
                            textKey: const ValueKey('header-balance-amount'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.5,
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
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Моя семья',
            onPressed: () => open(const MembersScreen()),
            style: buttonStyle,
            icon: const Icon(Icons.family_restroom_outlined, size: 22),
          ),
        ],
      ),
    );
  }
}
