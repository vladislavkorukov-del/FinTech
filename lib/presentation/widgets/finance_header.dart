import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide InputDecoration, Text;
import '../controller.dart';
import '../screens/management.dart';
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

/// The total balance (from [FinanceController.balance], in the selected
/// currency), shown in the middle of the main screen's «Все счета» header,
/// without a caption. Tapping it opens the accounts.
class AccountsTotal extends StatelessWidget {
  const AccountsTotal({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = FinanceScope.of(context);
    return Semantics(
      button: true,
      label: 'Общий баланс ${money(c.balance, c.currency)}',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('accounts-total'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedMoney(
              c.balance,
              currency: c.currency,
              textKey: const ValueKey('accounts-total-amount'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
