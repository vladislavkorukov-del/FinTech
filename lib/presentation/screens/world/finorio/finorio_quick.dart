import 'package:flutter/material.dart' hide Text;

import '../../../../domain/finorio/finorio.dart';
import '../../../l10n_widgets.dart';
import 'finorio_art.dart';
import 'finorio_names.dart';
import 'finorio_screen.dart';

/// Quick actions floating right above the building tapped in select mode:
/// turn it, open its full panel, or take it apart. Follows the camera.
class FinQuickBar extends StatelessWidget {
  const FinQuickBar({super.key, required this.state, required this.size});
  final FinorioScreenState state;
  final Size size;

  static const width = 216.0, height = 50.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: state.frame,
      builder: (context, _, _) {
        final w = state.world, cam = state.camera;
        final id = state.quick;
        final m = id == null ? null : w?.machines[id];
        if (w == null ||
            cam == null ||
            m == null ||
            state.tool != FinTool.select ||
            state.inspected != null) {
          return const SizedBox.shrink();
        }
        final s = cam.scale;
        final cx = (m.x + .5 - cam.x) * s + size.width / 2;
        final top = (m.y - cam.y) * s + size.height / 2;
        var y = top - height - 8;
        if (y < 90) y = top + s + 8; // no room above: show it below
        final x = (cx - width / 2).clamp(8.0, size.width - width - 8);
        if (y > size.height - height - 8 || top + s < 0) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned(
              left: x,
              top: y,
              width: width,
              height: height,
              child: Material(
                key: ValueKey('finorio-quick-${m.id}'),
                color: FinPalette.plum.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(16),
                elevation: 4,
                child: Row(
                  children: [
                    _action(
                      'finorio-quick-rotate',
                      Icons.rotate_right_rounded,
                      'Повернуть',
                      () {
                        w.rotate(m.id);
                        state.say('${FinNames.short(m.kind)}: повёрнуто');
                        state.changed();
                      },
                    ),
                    _action(
                      'finorio-quick-info',
                      Icons.info_outline_rounded,
                      'Сведения',
                      () => state.openInspector(m.id),
                    ),
                    _action(
                      'finorio-quick-remove',
                      Icons.handyman_outlined,
                      'Разобрать',
                      () {
                        w.remove(m.id);
                        state.quick = null;
                        state.say('Разобрано: набор и содержимое в инвентаре');
                        state.changed();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _action(String key, IconData icon, String label, VoidCallback tap) =>
      Expanded(
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(16),
          onTap: tap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 10.5),
              ),
            ],
          ),
        ),
      );
}
