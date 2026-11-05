import 'package:flutter/material.dart';
import '../screens/management.dart';
import '../screens/settings.dart';
import '../theme/app_theme.dart';

class FinanceBrand extends StatelessWidget {
  const FinanceBrand({super.key});
  static const asset = 'assets/brand/Finance_F_5000_rub_texture_v7.png';
  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    semanticLabel: 'Finance',
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
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
