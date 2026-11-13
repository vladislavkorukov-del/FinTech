part of 'flow_hud.dart';

class FlowBottomTools extends StatelessWidget {
  const FlowBottomTools({
    super.key,
    required this.flow,
    required this.onUse,
    required this.onMore,
    this.selected,
    this.enabled = true,
    this.columns = 4,
  });
  final FlowProgress flow;
  final ValueChanged<FlowTool> onUse, onMore;
  final FlowTool? selected;
  final bool enabled;
  final int columns;

  static const _pad = 10.0;
  static const _outset = FlowToolTile.plusOutset;

  /// One booster slot's side for a given panel width. Every tile is its slot
  /// plus [FlowToolTile.plusOutset] to the right and below, which doubles as
  /// the gap between slots and holds the «+» target.
  static double slotSide(double width, {int columns = 4}) => math.min(
    78.0,
    (width - _pad * 2 - _outset - columns * _outset) / columns,
  );

  /// The panel's height for a given width, for the screen's layout.
  static double heightFor(double width, {int columns = 4}) {
    final rows = (FlowTool.values.length / columns).ceil();
    final side = slotSide(width, columns: columns);
    return (side + FlowToolTile.outsetBelow(side)) * rows + _pad * 2 + _outset;
  }

  /// 1.62: the pack's bottom HUD — the pearl base with four lavender slots
  /// (hammer, bomb, shuffle, +5 moves), the stock badge bottom-left and the
  /// mint «+» bottom-right of every slot.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = slotSide(box.maxWidth, columns: columns);
      return FlowArtPanel(
        key: const ValueKey('flow-bottom-panel'),
        art: 'bottom_panel_base',
        // The tiles' trailing outset is balanced by extra space before them,
        // so the visible slots sit centred on the base.
        padding: const EdgeInsets.fromLTRB(
          _pad + _outset,
          _pad + _outset,
          _pad,
          _pad,
        ),
        child: Center(
          heightFactor: 1,
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final tool in FlowTool.values)
                SizedBox(
                  width: side + _outset,
                  height: side + FlowToolTile.outsetBelow(side),
                  child: FlowToolTile(
                    tool: tool,
                    stock: flow.available(tool),
                    selected: selected == tool,
                    buttonKey: ValueKey('flow-tool-${tool.name}'),
                    onPressed: enabled ? () => onUse(tool) : null,
                    moreKey: ValueKey('flow-tool-more-${tool.name}'),
                    onMore: enabled ? () => onMore(tool) : null,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// One booster on the pack's lavender slot (shared by the level and its
/// start screen): the icon in the upper part, the stock on the empty badge
/// bottom-left and, on the level, the «+» bottom-right.
class FlowToolTile extends StatelessWidget {
  const FlowToolTile({
    super.key,
    required this.tool,
    required this.stock,
    required this.selected,
    required this.buttonKey,
    required this.onPressed,
    this.moreKey,
    this.onMore,
    this.label,
  });
  final FlowTool tool;
  final int stock;
  final bool selected;
  final Key buttonKey;
  final Key? moreKey;
  final VoidCallback? onPressed, onMore;
  final String? label;

  /// With a «+», the tile is its slot plus this much to the right and below:
  /// the 48×48 «+» target then reaches past the slot instead of covering
  /// its centre, so the two targets stay apart.
  static const plusOutset = 14.0;

  /// Below the slot the outset grows on small slots, so the «+» target
  /// never reaches the slot's centre (its top stays below the middle).
  static double outsetBelow(double side) => math.max(plusOutset, 52 - side / 2);

  /// Icons balanced by visual mass: the open arrows may be wider.
  static double _iconScale(FlowTool tool) => switch (tool) {
    FlowTool.shuffle => .66,
    FlowTool.extraMoves => .58,
    _ => .56,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final plus = onMore != null || moreKey != null;
      final side = plus
          ? math.min(
              box.maxWidth - plusOutset,
              box.maxHeight -
                  outsetBelow(math.max(0, box.maxWidth - plusOutset)),
            )
          : math.min(box.maxWidth, box.maxHeight);
      final badgeW = side * .46, badgeH = badgeW / 1.85;
      final plusSize = side * .28;
      // The visible «+» centre sits 17% in from the slot's corner; the
      // target fills the tile's bottom-right 48×48.
      double align(double tile) =>
          2 * (side * .83 - (tile - 48) - plusSize / 2) / (48 - plusSize) - 1;
      final plusAlign = Alignment(align(box.maxWidth), align(box.maxHeight));
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: side,
            height: side,
            child: FlowArtButton(
              key: buttonKey,
              art: 'booster_slot',
              label: label ?? '${flowToolName(tool)}, запас $stock',
              onPressed: onPressed,
              child: Align(
                alignment: const Alignment(0, -.42),
                child: FlowSprite(
                  flowToolArt(tool),
                  width: side * _iconScale(tool),
                  height: side * _iconScale(tool),
                ),
              ),
            ),
          ),
          // Selection is drawn by Flutter over the slot (not baked in art).
          Positioned(
            left: 0,
            top: 0,
            width: side,
            height: side,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: const Color(0x223FC79F),
                    shape: RoundedSuperellipseBorder(
                      side: const BorderSide(
                        color: Color(0xFF3FC79F),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(side * .24),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: side * .08,
            top: side * .92 - badgeH,
            width: badgeW,
            height: badgeH,
            child: IgnorePointer(
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: FlowSprite('booster_counter_badge'),
                  ),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: badgeW * .14),
                      child: FlowNumber(stock, size: badgeH * .7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (selected)
            Positioned(
              left: side * .95 - math.max(14, side * .22),
              top: side * .05,
              child: IgnorePointer(
                child: Icon(
                  Icons.check_circle_rounded,
                  color: const Color(0xFF27896C),
                  size: math.max(14, side * .22),
                ),
              ),
            ),
          if (plus)
            // A 48×48 target at the tile's corner; the visible «+» sits at
            // the slot's bottom-right, like the pack's assembled review.
            Positioned(
              right: 0,
              bottom: 0,
              child: FlowArtButton(
                key: moreKey,
                art: 'booster_plus_button',
                visualSize: plusSize,
                visualAlignment: plusAlign,
                label: 'Запас: ${flowToolName(tool)}',
                onPressed: onMore,
                width: 48,
                height: 48,
              ),
            ),
        ],
      );
    },
  );
}

class FlowScoreTrack extends StatelessWidget {
  const FlowScoreTrack({
    super.key,
    required this.score,
    required this.thresholds,
  });
  final int score;
  final List<int> thresholds;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final maximum = math.max(1, thresholds.last);
      final value = (score / maximum).clamp(0.0, 1.0);
      return Semantics(
        label: 'Прогресс звёзд: $score из $maximum',
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Positioned(
              left: 0,
              right: 0,
              top: 9,
              height: 14,
              child: FlowSprite('hud_progress_track', fit: BoxFit.fill),
            ),
            Positioned(
              left: 2,
              right: 2,
              top: 11,
              height: 10,
              child: ClipRect(
                key: const ValueKey('flow-score-fill'),
                clipper: _ProgressClipper(value),
                child: const FlowSprite('hud_progress_fill', fit: BoxFit.fill),
              ),
            ),
            for (final threshold in thresholds)
              Positioned(
                left: ((threshold / maximum) * (box.maxWidth - 22)).clamp(
                  0,
                  box.maxWidth - 22,
                ),
                top: 4,
                width: 24,
                height: 24,
                child: FlowSprite(
                  score >= threshold ? 'hud_star_active' : 'hud_star_inactive',
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _ProgressClipper extends CustomClipper<Rect> {
  const _ProgressClipper(this.value);
  final double value;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * value, size.height);
  @override
  bool shouldReclip(_ProgressClipper oldClipper) => value != oldClipper.value;
}
