import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../screens/management.dart';
import '../screens/settings.dart';
import '../theme/app_theme.dart';

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

class FinanceHeader extends StatelessWidget {
  const FinanceHeader({super.key, this.brand});
  final Widget? brand;
  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    return SizedBox(
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: SizedBox(
              key: const ValueKey('finance-brand-center'),
              width: 54,
              height: 54,
              child: brand ?? const FinanceBrand(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton.filledTonal(
              tooltip: 'Настройки',
              onPressed: () => open(const SettingsScreen()),
              style: IconButton.styleFrom(
                backgroundColor: colors.iconBackground,
                foregroundColor: colors.iconForeground,
              ),
              icon: const Icon(Icons.tune_rounded, size: 21),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton.filledTonal(
              tooltip: 'Моя семья',
              onPressed: () => open(const MembersScreen()),
              style: IconButton.styleFrom(
                backgroundColor: colors.iconBackground,
                foregroundColor: colors.iconForeground,
              ),
              icon: const Icon(Icons.family_restroom_outlined, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
