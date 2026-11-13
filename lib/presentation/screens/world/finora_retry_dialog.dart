import 'package:flutter/material.dart';

import 'flow_hud.dart' show FlowType, flowInk, flowText;
import 'world_art.dart' show worldFontFamily;

// From the owner's «Finora Potok · Шрифт и окно новой попытки» pack (1.55),
// on the pause panel and victory buttons already bundled from earlier packs.
const finoraPotokFont = worldFontFamily;

/// Shows the confirmation. True means the caller may replace the old attempt.
/// Cancelling, dismissing, and system Back all return false.
Future<bool> showFinoraRetryDialog(
  BuildContext context, {
  required int unfinishedLevel,
  required String panelAsset,
  required String cancelButtonAsset,
  required String confirmButtonAsset,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x9925132E),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Stack(
            children: [
              Positioned.fill(
                child: _FinoraArtwork(
                  asset: panelAsset,
                  sourceSize: const Size(1024, 949),
                  visibleRect: const Rect.fromLTWH(64, 88, 895, 778),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 27, 24, 23),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Начать новую попытку?',
                        textAlign: TextAlign.center,
                        style: FlowType.title,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Незавершённая попытка уровня $unfinishedLevel будет заменена.',
                      textAlign: TextAlign.center,
                      style: FlowType.body.copyWith(height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Звёзды и награды сохранятся.',
                      textAlign: TextAlign.center,
                      style: flowText(FlowType.body.fontSize!),
                    ),
                    const SizedBox(height: 23),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cancel = _RetryButton(
                          label: 'Отмена',
                          asset: cancelButtonAsset,
                          sourceSize: const Size(1024, 458),
                          visibleRect: const Rect.fromLTWH(85, 144, 849, 162),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                        );
                        final start = _RetryButton(
                          label: 'Начать',
                          asset: confirmButtonAsset,
                          sourceSize: const Size(1024, 341),
                          visibleRect: const Rect.fromLTWH(68, 87, 888, 186),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                        );
                        final buttonTextSize = MediaQuery.textScalerOf(
                          context,
                        ).scale(17);
                        if (constraints.maxWidth < buttonTextSize * 12) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cancel,
                              const SizedBox(height: 10),
                              start,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: cancel),
                            const SizedBox(width: 10),
                            Expanded(child: start),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return confirmed ?? false;
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.label,
    required this.asset,
    required this.sourceSize,
    required this.visibleRect,
    required this.onPressed,
  });

  final String label;
  final String asset;
  final Size sourceSize;
  final Rect visibleRect;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _FinoraArtwork(
            asset: asset,
            sourceSize: sourceSize,
            visibleRect: visibleRect,
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
              foregroundColor: flowInk,
              textStyle: FlowType.button,
            ),
            onPressed: onPressed,
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}

class _FinoraArtwork extends StatelessWidget {
  const _FinoraArtwork({
    required this.asset,
    required this.sourceSize,
    required this.visibleRect,
  });

  final String asset;
  final Size sourceSize;
  final Rect visibleRect;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final x = constraints.maxWidth / visibleRect.width;
          final y = constraints.maxHeight / visibleRect.height;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -visibleRect.left * x,
                top: -visibleRect.top * y,
                width: sourceSize.width * x,
                height: sourceSize.height * y,
                child: Image.asset(
                  asset,
                  fit: BoxFit.fill,
                  excludeFromSemantics: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
