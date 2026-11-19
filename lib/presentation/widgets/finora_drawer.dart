import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../haptics.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../screens/achievements_screen.dart';
import '../screens/app_search.dart';
import '../screens/batch_entries_screen.dart';
import '../screens/entry_editor.dart';
import '../screens/management.dart';
import '../screens/settings.dart';
import '../screens/developer_screen.dart';
import '../screens/debts_screen.dart';
import '../controller.dart';
import '../../features/finora_ai/ui/ai_settings_screen.dart';
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
    (5, CupertinoIcons.sparkles, 'Finora AI'),
    (4, CupertinoIcons.ellipsis_circle, 'Ещё'),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Material(
          color: on
              ? scheme.onSurface.withValues(alpha: .1)
              : Colors.transparent,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            key: key,
            customBorder: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: on ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
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

    Widget divider() => Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
      child: Divider(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: .5),
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    void page(Widget screen) => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    void settings(String section) => page(SettingsScreen(section: section));
    final developer =
        FinanceScope.maybeOf(context)?.data.preferences.developer.enabled ??
        false;

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
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Finora',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 34,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('drawer-search'),
                    tooltip: tr('Поиск'),
                    onPressed: () {
                      Haptics.light();
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AppSearchScreen(onPlace: onSelect),
                        ),
                      );
                    },
                    icon: Icon(
                      CupertinoIcons.search,
                      size: 23,
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
                  divider(),
                  heading(tr('Функции')),
                  // «Функции»: tools that already live in the app.
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
                          'batch',
                          CupertinoIcons.square_list,
                          'Несколько операций',
                          () => openFinancePage(
                            context,
                            const BatchEntriesScreen(),
                          ),
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
                          'debts',
                          CupertinoIcons.creditcard,
                          'Долги',
                          () => openFinancePage(context, const DebtsScreen()),
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
                  // Settings right here: the pages people open most, and
                  // the whole list.
                  divider(),
                  heading(tr('Настройки')),
                  for (final (key, icon, label, open)
                      in <(String, IconData, String, VoidCallback)>[
                        (
                          'appearance',
                          CupertinoIcons.paintbrush,
                          'Внешний вид',
                          () => settings('appearance'),
                        ),
                        (
                          'general',
                          CupertinoIcons.money_rubl_circle,
                          'Валюта и форматы',
                          () => settings('general'),
                        ),
                        (
                          'notifications',
                          CupertinoIcons.bell,
                          'Уведомления',
                          () => settings('notifications'),
                        ),
                        (
                          'security',
                          CupertinoIcons.lock,
                          'Защита',
                          () => settings('security'),
                        ),
                        (
                          'backups',
                          CupertinoIcons.cloud_upload,
                          'Резервные копии',
                          () => settings('backups'),
                        ),
                        (
                          'ai-settings',
                          CupertinoIcons.slider_horizontal_3,
                          'Настройки Finora AI',
                          () => page(const AiSettingsScreen()),
                        ),
                        if (developer)
                          (
                            'developer',
                            CupertinoIcons.hammer,
                            'Для разработчика',
                            () => page(const DeveloperScreen()),
                          ),
                        (
                          'settings',
                          CupertinoIcons.gear,
                          'Все настройки',
                          () => page(const SettingsScreen()),
                        ),
                      ])
                    row(
                      key: ValueKey('drawer-settings-$key'),
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
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
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
                    child: const ProfileAvatar(size: 38),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const ValueKey('drawer-new-entry'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: scheme.onSurface,
                          foregroundColor: scheme.surface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          showEntryEditor(context);
                        },
                        icon: const Icon(CupertinoIcons.plus, size: 17),
                        label: Text(
                          tr('Новая операция'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
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
