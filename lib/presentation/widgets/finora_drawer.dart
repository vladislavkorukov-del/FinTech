import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../haptics.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../screens/achievements_screen.dart';
import '../screens/entry_editor.dart';
import '../screens/management.dart';
import '../screens/settings.dart';
import 'profile_avatar.dart';

/// The app's navigation (Release), after a chat app's side panel: the name
/// and search at the top, the main places with thin symbols, handy tools
/// that already live in the app, and at the bottom the profile and
/// «Новая операция».
class FinoraDrawer extends StatelessWidget {
  const FinoraDrawer({
    super.key,
    required this.current,
    required this.onSelect,
    this.onVoice,
  });

  /// The open place: 0 home, 1 operations, 3 analytics, 4 more, 5 Finora AI.
  final int current;
  final ValueChanged<int> onSelect;

  /// Starts voice input (Finora's voice assistant, unchanged).
  final VoidCallback? onVoice;

  static const places = <(int, IconData, String)>[
    (0, CupertinoIcons.house, 'Главная'),
    (1, CupertinoIcons.doc_text, 'Операции'),
    (3, CupertinoIcons.chart_bar, 'Аналитика'),
    (5, CupertinoIcons.sparkles, 'Финора AI'),
    (4, CupertinoIcons.square_grid_2x2, 'Ещё'),
  ];

  /// The panel colour: near-black at night, white by day.
  static Color background(ThemeData t) => t.brightness == Brightness.dark
      ? const Color(0xFF121314)
      : const Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = (MediaQuery.sizeOf(context).width * .86).clamp(280.0, 360.0);
    void go(int place) {
      Haptics.light();
      Navigator.pop(context);
      onSelect(place);
    }

    // One row style for the places and the tools alike.
    Widget row({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool on = false,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: on
              ? scheme.onSurface.withValues(alpha: .1)
              : Colors.transparent,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            key: key,
            customBorder: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: on ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Drawer(
      key: const ValueKey('app-drawer'),
      width: width,
      backgroundColor: background(theme),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 16, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Finora',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 38,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('drawer-search'),
                    tooltip: tr('Поиск'),
                    onPressed: () => go(1),
                    icon: Icon(
                      CupertinoIcons.search,
                      size: 26,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final (place, icon, label) in places)
                    row(
                      key: ValueKey('drawer-$place'),
                      icon: icon,
                      label: tr(label),
                      on: place == current,
                      onTap: () => go(place),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 14, 28, 10),
                    child: Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: .5),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 10, 28, 6),
                    child: Text(
                      tr('Полезное'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // Release: handy tools that already live in the app.
                  for (final (key, icon, label, open)
                      in <(String, IconData, String, VoidCallback)>[
                        if (onVoice != null)
                          (
                            'voice',
                            CupertinoIcons.mic,
                            'Голосовой ввод',
                            onVoice!,
                          ),
                        (
                          'scan',
                          CupertinoIcons.doc_text_viewfinder,
                          'Скриншот из банка',
                          () => showEntryEditor(context, startScan: true),
                        ),
                        (
                          'shopping',
                          CupertinoIcons.cart,
                          'Список покупок',
                          () =>
                              openFinancePage(context, const ShoppingScreen()),
                        ),
                        (
                          'recurring',
                          CupertinoIcons.arrow_2_circlepath,
                          'Платежи и подписки',
                          () =>
                              openFinancePage(context, const RecurringScreen()),
                        ),
                        (
                          'calendar',
                          CupertinoIcons.calendar,
                          'Календарь',
                          () =>
                              openFinancePage(context, const CalendarScreen()),
                        ),
                        (
                          'budgets',
                          CupertinoIcons.chart_pie,
                          'Бюджеты',
                          () => openFinancePage(context, const BudgetsScreen()),
                        ),
                        (
                          'goals',
                          CupertinoIcons.star,
                          'Мечты',
                          () => openFinancePage(context, const GoalsScreen()),
                        ),
                        (
                          'achievements',
                          CupertinoIcons.rosette,
                          'Достижения',
                          () => openFinancePage(
                            context,
                            const AchievementsScreen(),
                          ),
                        ),
                      ])
                    row(
                      key: ValueKey('drawer-$key'),
                      icon: icon,
                      label: tr(label),
                      onTap: () {
                        Haptics.light();
                        Navigator.pop(context);
                        open();
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Row(
                children: [
                  InkWell(
                    key: const ValueKey('drawer-profile'),
                    customBorder: const CircleBorder(),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    child: const ProfileAvatar(size: 52),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const ValueKey('drawer-new-entry'),
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.onSurface,
                          foregroundColor: scheme.surface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          showEntryEditor(context);
                        },
                        icon: const Icon(CupertinoIcons.plus, size: 20),
                        label: Text(
                          tr('Новая операция'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
