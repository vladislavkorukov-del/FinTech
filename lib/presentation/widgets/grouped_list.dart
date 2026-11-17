import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';

import 'common.dart';
import 'finora_orb.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';

/// Tile colors for grouped lists (Finora 1.26), iOS-like but a little
/// quieter so they sit well on every theme.
/// Apple's system colours (Release): every menu row has a tile of its own
/// colour with a white icon, as in the iPhone's Settings.
abstract final class TileColors {
  static const blue = Color(0xFF0A84FF);
  static const indigo = Color(0xFF5E5CE6);
  static const purple = Color(0xFFBF5AF2);
  static const pink = Color(0xFFFF375F);
  static const red = Color(0xFFFF453A);
  static const orange = Color(0xFFFF9F0A);
  static const yellow = Color(0xFFFFCC00);
  static const green = Color(0xFF30D158);
  static const mint = Color(0xFF00C7BE);
  static const teal = Color(0xFF40C8E0);
  static const cyan = Color(0xFF64D2FF);
  static const brown = Color(0xFFAC8E68);
  static const gray = Color(0xFF8E8E93);

  /// A pastel user colour made bright enough for a tile with a white icon.
  static Color vivid(Color c) {
    final h = HSLColor.fromColor(c);
    if (h.saturation < .08) return gray;
    return h
        .withSaturation(h.saturation.clamp(.62, .95))
        .withLightness(h.lightness.clamp(.46, .56))
        .toColor();
  }

  /// A tile: the colour, a touch lighter at the top (glassy).
  static Decoration tile(Color c, {double radius = 9}) => ShapeDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(c, Colors.white, .18)!, c],
    ),
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// The thin SF-style symbol for a Material icon used in the menus; icons
/// without a match stay as they are.
IconData iosIcon(IconData icon) => _ios[icon] ?? icon;

final _ios = <IconData, IconData>{
  Icons.account_balance_wallet_rounded: CupertinoIcons.creditcard,
  Icons.calendar_month_rounded: CupertinoIcons.calendar,
  Icons.category_rounded: CupertinoIcons.square_grid_2x2,
  Icons.emoji_events_rounded: CupertinoIcons.rosette,
  Icons.event_repeat_rounded: CupertinoIcons.arrow_2_circlepath,
  Icons.people_alt_rounded: CupertinoIcons.person_2,
  Icons.pie_chart_rounded: CupertinoIcons.chart_pie,
  Icons.settings_rounded: CupertinoIcons.gear_alt,
  Icons.shopping_basket_rounded: CupertinoIcons.cart,
  Icons.star_rounded: CupertinoIcons.star,
  Icons.article_rounded: CupertinoIcons.doc_text,
  Icons.cleaning_services_rounded: CupertinoIcons.sparkles,
  Icons.cloud_upload_rounded: CupertinoIcons.cloud_upload,
  Icons.download_rounded: CupertinoIcons.arrow_down_to_line,
  Icons.face_retouching_natural_rounded: CupertinoIcons.smiley,
  Icons.grid_on_rounded: CupertinoIcons.table,
  Icons.info_rounded: CupertinoIcons.info_circle,
  Icons.lightbulb_rounded: CupertinoIcons.lightbulb,
  Icons.lock_rounded: CupertinoIcons.lock,
  Icons.move_down_rounded: CupertinoIcons.arrow_down_doc,
  Icons.notifications_active_rounded: CupertinoIcons.bell,
  Icons.notifications_rounded: CupertinoIcons.bell,
  Icons.palette_outlined: CupertinoIcons.paintbrush,
  Icons.palette_rounded: CupertinoIcons.paintbrush,
  Icons.power_settings_new_rounded: CupertinoIcons.power,
  Icons.record_voice_over_outlined: CupertinoIcons.mic,
  Icons.record_voice_over_rounded: CupertinoIcons.mic,
  Icons.restart_alt_rounded: CupertinoIcons.arrow_counterclockwise,
  Icons.restore_rounded: CupertinoIcons.arrow_uturn_left,
  Icons.school_rounded: CupertinoIcons.book,
  Icons.storage_rounded: CupertinoIcons.archivebox,
  Icons.table_chart_rounded: CupertinoIcons.table,
  Icons.touch_app_rounded: CupertinoIcons.hand_draw,
  Icons.translate_rounded: CupertinoIcons.globe,
  Icons.tune_rounded: CupertinoIcons.slider_horizontal_3,
  Icons.upload_file_rounded: CupertinoIcons.square_arrow_up,
  Icons.vibration_rounded: CupertinoIcons.waveform,
  Icons.volume_off_rounded: CupertinoIcons.speaker_slash,
  Icons.widgets_rounded: CupertinoIcons.square_grid_2x2,
  Icons.auto_awesome_rounded: CupertinoIcons.sparkles,
};

/// The reset symbol (Release): a ring arrow wound around a small bin —
/// «start over». [spin] turns the arrow (0–1 per turn).
class ResetGlyph extends StatelessWidget {
  const ResetGlyph({
    super.key,
    this.size = 22,
    this.color,
    this.spin = 0,
    this.stroke = 1.6,
  });
  final double size, spin, stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ResetPainter(
      color: color ?? Theme.of(context).colorScheme.error,
      spin: spin,
      stroke: stroke,
    ),
  );
}

class _ResetPainter extends CustomPainter {
  const _ResetPainter({
    required this.color,
    required this.spin,
    required this.stroke,
  });
  final Color color;
  final double spin, stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * s / 22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    // The ring arrow, open at the top-right, with its head.
    final r = s * .44;
    final start = -math.pi / 2 + .55 + spin * math.pi * 2;
    const sweep = math.pi * 2 - 1.0;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      line,
    );
    final end = start + sweep;
    final tip = c + Offset(math.cos(end), math.sin(end)) * r;
    final along = Offset(-math.sin(end), math.cos(end));
    final out = Offset(math.cos(end), math.sin(end));
    final h = s * .17;
    canvas.drawPath(
      Path()
        ..moveTo(
          tip.dx - along.dx * h + out.dx * h * .7,
          tip.dy - along.dy * h + out.dy * h * .7,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx - along.dx * h - out.dx * h * .7,
          tip.dy - along.dy * h - out.dy * h * .7,
        ),
      line,
    );
    // The bin inside.
    final w = s * .3, bh = s * .3;
    final top = c.dy - bh * .38;
    canvas
      ..drawLine(Offset(c.dx - w * .62, top), Offset(c.dx + w * .62, top), line)
      ..drawLine(
        Offset(c.dx - w * .2, top - s * .06),
        Offset(c.dx + w * .2, top - s * .06),
        line,
      )
      ..drawPath(
        Path()
          ..moveTo(c.dx - w * .45, top)
          ..lineTo(c.dx - w * .36, top + bh)
          ..lineTo(c.dx + w * .36, top + bh)
          ..lineTo(c.dx + w * .45, top),
        line,
      );
  }

  @override
  bool shouldRepaint(_ResetPainter old) =>
      old.color != color || old.spin != spin || old.stroke != stroke;
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
              borderRadius: BorderRadius.circular(16),
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

/// A row: a coloured icon tile (Release: back to colour, as on the iPhone),
/// title, optional subtitle or value, chevron.
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
    this.leading,
  });
  final IconData icon;

  /// A drawn symbol in place of [icon] (e.g. [ResetGlyph]).
  final Widget? leading;
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
                // iOS-strict: a thin line symbol, no tile behind it.
                SizedBox(
                  width: 28,
                  child:
                      leading ??
                      Icon(
                        iosIcon(icon),
                        size: 22,
                        color: destructive ? scheme.error : scheme.primary,
                      ),
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
        () => _x = _from * (1 - Curves.easeOutCubic.transform(_back.value)),
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

/// Gives a [Dismissible] a live swipe progress (0–1) for its background.
class SwipeProgress extends StatefulWidget {
  const SwipeProgress({super.key, required this.builder});
  final Widget Function(BuildContext context, ValueNotifier<double> progress)
  builder;
  @override
  State<SwipeProgress> createState() => _SwipeProgressState();
}

class _SwipeProgressState extends State<SwipeProgress> {
  final _progress = ValueNotifier<double>(0);
  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _progress);
}

/// What shows under a swiped row (Release): a soft gradient that deepens
/// toward the edge, a drawn symbol that comes alive with the swipe and a
/// label fading in. [delete] draws the bin (its lid lifts), otherwise
/// [icon] is shown.
class SwipeBackdrop extends StatelessWidget {
  const SwipeBackdrop({
    super.key,
    required this.progress,
    required this.color,
    required this.label,
    this.delete = false,
    this.icon,
    this.end = true,
    this.margin = EdgeInsets.zero,
    this.radius = 16,
  });
  final ValueListenable<double> progress;
  final Color color;
  final String label;
  final bool delete, end;
  final IconData? icon;
  final EdgeInsets margin;
  final double radius;

  /// The delete colour: a deep coral rather than a flat warning red.
  static const coral = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, p, _) {
        final t = (p / .35).clamp(0.0, 1.0);
        final symbol = SizedBox.square(
          dimension: 34,
          child: Center(
            child: Container(
              width: 22 + 12 * t,
              height: 22 + 12 * t,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .18 * t),
              ),
              child: delete
                  ? CustomPaint(
                      size: const Size.square(20),
                      painter: _BinPainter(lid: t, color: Colors.white),
                    )
                  : Icon(icon, size: 19, color: Colors.white),
            ),
          ),
        );
        final text = Opacity(
          opacity: t,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: end ? Alignment.centerLeft : Alignment.centerRight,
              end: end ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                color.withValues(alpha: 0),
                color.withValues(alpha: .55 + .2 * t),
                Color.lerp(color, Colors.black, .12)!,
              ],
              stops: const [0, .55, 1],
            ),
          ),
          child: Align(
            alignment: end ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(
                left: end ? 0 : 18 + 6 * t,
                right: end ? 18 + 6 * t : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: end
                    ? [text, const SizedBox(width: 8), symbol]
                    : [symbol, const SizedBox(width: 8), text],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// A thin bin whose lid lifts as [lid] goes 0 → 1.
class _BinPainter extends CustomPainter {
  const _BinPainter({required this.lid, required this.color});
  final double lid;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    // Body with two ribs.
    final top = s * .34;
    canvas.drawPath(
      Path()
        ..moveTo(s * .24, top)
        ..lineTo(s * .3, s * .88)
        ..lineTo(s * .7, s * .88)
        ..lineTo(s * .76, top),
      line,
    );
    canvas
      ..drawLine(Offset(s * .43, s * .48), Offset(s * .44, s * .74), line)
      ..drawLine(Offset(s * .57, s * .48), Offset(s * .56, s * .74), line);
    // The lid, hinged at its right end.
    final hinge = Offset(s * .84, s * .24);
    canvas
      ..save()
      ..translate(hinge.dx, hinge.dy)
      ..rotate(-.55 * lid)
      ..translate(-hinge.dx, -hinge.dy)
      ..drawLine(Offset(s * .16, s * .24), hinge, line)
      ..drawLine(Offset(s * .4, s * .24), Offset(s * .42, s * .13), line)
      ..drawLine(Offset(s * .42, s * .13), Offset(s * .58, s * .13), line)
      ..drawLine(Offset(s * .58, s * .13), Offset(s * .6, s * .24), line)
      ..restore();
  }

  @override
  bool shouldRepaint(_BinPainter old) => old.lid != lid || old.color != color;
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
  Widget build(BuildContext context) =>
      SwipeProgress(builder: (context, progress) => _build(context, progress));

  Widget _build(BuildContext context, ValueNotifier<double> progress) {
    final scheme = Theme.of(context).colorScheme;
    final right = onSwipeRight;
    final delete = SwipeBackdrop(
      progress: progress,
      color: SwipeBackdrop.coral,
      label: 'Удалить',
      delete: true,
      margin: margin,
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
      onUpdate: (d) => progress.value = d.progress,
      background: right == null
          ? delete
          : SwipeBackdrop(
              progress: progress,
              color: scheme.primary,
              label: rightLabel,
              icon: rightIcon,
              end: false,
              margin: margin,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
