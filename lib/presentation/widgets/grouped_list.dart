import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/services.dart';

import 'common.dart';
import 'finora_orb.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';

/// Tile colors for grouped lists (Finora 1.26), iOS-like but a little
/// quieter so they sit well on every theme.
abstract final class TileColors {
  static const blue = Color(0xFF3B82F6);
  static const indigo = Color(0xFF6366F1);
  static const purple = Color(0xFFA855F7);
  static const pink = Color(0xFFEC4899);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF59E0B);
  static const green = Color(0xFF22C55E);
  static const teal = Color(0xFF14B8A6);
  static const gray = Color(0xFF8E8E93);
}

/// A titled group of rows on one card, with thin dividers between them.
class GroupedSection extends StatelessWidget {
  const GroupedSection({
    super.key,
    this.title,
    required this.children,
    this.footer,
  });
  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: .6,
            indent: 58,
            color: scheme.outlineVariant.withValues(alpha: .35),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(
                tr(title!).toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: .6,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(children: rows),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                footer!,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row: colored icon tile, title, optional subtitle or value, chevron.
class GroupedRow extends StatelessWidget {
  const GroupedRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle, value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 19, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: destructive ? scheme.error : scheme.onSurface,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null)
                  ConstrainedBox(
                    // A short value keeps the title and subtitle wide.
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: scheme.onSurfaceVariant.withValues(alpha: .6),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Проведите, чтобы …» like the iPhone power-off slider: the knob has to be
/// dragged almost to the end; let go earlier and it springs back.
class SwipeToConfirm extends StatefulWidget {
  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color,
    this.icon = Icons.arrow_forward_rounded,
  });
  final String label;
  final VoidCallback onConfirmed;
  final Color? color;
  final IconData icon;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm>
    with SingleTickerProviderStateMixin {
  late final _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  double _x = 0, _from = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _back.addListener(
      () => setState(
        () => _x = _from * (1 - Curves.easeOutBack.transform(_back.value)),
      ),
    );
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? scheme.error;
    const height = 60.0, pad = 5.0;
    const knob = height - pad * 2;
    return LayoutBuilder(
      builder: (context, box) {
        final max = box.maxWidth - knob - pad * 2;
        final t = max <= 0 ? 0.0 : (_x / max).clamp(0.0, 1.0);
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Color.lerp(
              color.withValues(alpha: .14),
              color.withValues(alpha: .32),
              t,
            ),
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: knob + pad * 2,
                    right: 16,
                  ),
                  child: Center(
                    child: Opacity(
                      opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: pad + _x,
                child: GestureDetector(
                  key: const ValueKey('swipe-knob'),
                  onHorizontalDragUpdate: _done
                      ? null
                      : (d) {
                          _back.stop();
                          setState(
                            () => _x = (_x + d.delta.dx).clamp(0.0, max),
                          );
                        },
                  onHorizontalDragEnd: _done
                      ? null
                      : (_) {
                          if (_x >= max * .9) {
                            setState(() {
                              _x = max;
                              _done = true;
                            });
                            HapticFeedback.heavyImpact();
                            widget.onConfirmed();
                          } else {
                            _from = _x;
                            _back.forward(from: 0);
                          }
                        },
                  child: Container(
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: .35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _done ? Icons.check_rounded : widget.icon,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Swipe left to delete (Finora 1.28): a red strip with a bin follows the
/// finger; Finora asks before anything goes. [onDelete] may refuse with a
/// FormatException (an account with operations) — then nothing is removed.
class SwipeToDelete extends StatelessWidget {
  const SwipeToDelete({
    required super.key,
    required this.child,
    required this.title,
    required this.message,
    required this.onDelete,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onSwipeRight,
    this.rightLabel = 'Оплатить',
    this.rightIcon = Icons.check_circle_outline_rounded,
  });
  final Widget child;
  final EdgeInsets margin;
  final String title, message;
  final Future<void> Function() onDelete;

  /// 1.36: a swipe to the right (e.g. «оплатить досрочно»); the row stays.
  final Future<void> Function()? onSwipeRight;
  final String rightLabel;
  final IconData rightIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final right = onSwipeRight;
    final delete = Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Удалить',
            style: TextStyle(
              color: scheme.onError,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.delete_outline_rounded, color: scheme.onError),
        ],
      ),
    );
    return Dismissible(
      key: ObjectKey(key),
      direction: right == null
          ? DismissDirection.endToStart
          : DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.endToStart: .35,
        DismissDirection.startToEnd: .3,
      },
      background: right == null
          ? delete
          : Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 24),
              margin: margin,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(rightIcon, color: scheme.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    rightLabel,
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
      secondaryBackground: right == null ? null : delete,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          if (right != null) {
            try {
              await right();
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          }
          return false;
        }
        final ok = await confirmWithFinora(
          context,
          title: title,
          message: message,
          action: 'Удалить',
          destructive: true,
        );
        if (!ok || !context.mounted) return false;
        try {
          await onDelete();
          HapticFeedback.heavyImpact();
          return true;
        } catch (e) {
          if (context.mounted) showError(context, e);
          return false;
        }
      },
      child: child,
    );
  }
}

/// A question from Finora (1.28): her face, a title, a line and two buttons.
Future<bool> confirmWithFinora(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Да',
  String cancel = 'Отмена',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      key: const ValueKey('finora-confirm'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: FinoraMark(
                size: 72,
                mood: destructive ? FinoraMood.doubt : FinoraMood.thinking,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('finora-confirm-yes'),
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancel),
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}
