import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../domain/models.dart';
import '../controller.dart';
import '../haptics.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../screens/entry_editor.dart';
import '../screens/settings.dart';
import 'common.dart';
import 'profile_avatar.dart';

/// The app's navigation (Release), after a chat app's side panel: the name
/// and search at the top, the main places with thin symbols, recent
/// operations, and at the bottom the profile and «Новая операция».
class FinoraDrawer extends StatelessWidget {
  const FinoraDrawer({
    super.key,
    required this.current,
    required this.onSelect,
  });

  /// The open place: 0 home, 1 operations, 3 analytics, 4 more, 5 Finora AI.
  final int current;
  final ValueChanged<int> onSelect;

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
    final c = FinanceScope.of(context);
    final width = (MediaQuery.sizeOf(context).width * .86).clamp(280.0, 360.0);
    final recent = [...c.data.entries.where((e) => e.status == 'posted')]
      ..sort((a, b) => b.date.compareTo(a.date));
    void go(int place) {
      Haptics.light();
      Navigator.pop(context);
      onSelect(place);
    }

    Widget item(int place, IconData icon, String label) {
      final on = place == current;
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
            key: ValueKey('drawer-$place'),
            customBorder: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onTap: () => go(place),
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
                      tr(label),
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
                    item(place, icon, label),
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
                      tr('Недавние'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final e in recent.take(6))
                    _Recent(
                      entry: e,
                      onTap: () {
                        Navigator.pop(context);
                        showEntryEditor(context, entry: e);
                      },
                    ),
                  if (recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 6, 28, 6),
                      child: Text(
                        'Операций пока нет',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  if (recent.length > 6)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () => go(1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tr('Показать все'),
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 4),
                            const Icon(CupertinoIcons.chevron_right, size: 16),
                          ],
                        ),
                      ),
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

class _Recent extends StatelessWidget {
  const _Recent({required this.entry, required this.onTap});
  final FinanceEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cat = c.category(entry.categoryId);
    final name = entry.payee.trim().isNotEmpty
        ? entry.payee.trim()
        : entry.kind == EntryKind.transfer
        ? tr('Перевод')
        : cat?.name ?? '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
        child: Row(
          children: [
            Icon(
              entry.kind == EntryKind.transfer
                  ? CupertinoIcons.arrow_right_arrow_left
                  : categoryIcon(cat?.icon ?? 26),
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: scheme.onSurface),
              ),
            ),
            Text(
              '${entry.kind == EntryKind.income
                  ? '+'
                  : entry.kind == EntryKind.expense
                  ? '−'
                  : ''}'
              '${money(entry.amountMinor, entry.currency)}',
              style: TextStyle(
                fontSize: 13.5,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
