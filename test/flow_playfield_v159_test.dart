import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:finora/presentation/screens/world/flow_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1.59: the playfield pack (background, backplate, cell, pearl frame) laid
/// out from its PLAYFIELD_LAYOUT.json on the 1254 × 1254 canvas.
void main() {
  test('the four layers are bundled unchanged', () {
    const sums = {
      'gameplay_background.png':
          'e2a8cf714b647e6f29cc7710a5247809d3d68deb20610d54dfb60d355eaa05e2',
      'board_backplate.png':
          '6dec006e1b642041ca82c929520a65ac541d1c4cee3b3f15fdf6f3448bc83988',
      'board_cell.png':
          'c50a9284bb791c6bfe8816dca15cdbb99b0b4b74fa7b8e4a7cd1ea843bf677f3',
      'board_frame_pearl.png':
          'ea6097c1d9f0a575ed1bb027c83561834e8c3b9e83791f605dc5ee3be1b93121',
    };
    for (final e in sums.entries) {
      final bytes = File('${FlowPlayfield.folder}/${e.key}').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), e.value, reason: e.key);
    }
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/finora/match3/playfield/'),
    );
  });

  test('cells fill the grid rect with an 8.5% gap and map back', () {
    final pitch = FlowPlayfield.pitch;
    expect(pitch, closeTo(870 / 8, 1e-9));
    final first = FlowPlayfield.cellRect(0), last = FlowPlayfield.cellRect(63);
    final gap = pitch * .085;
    expect(first.left, closeTo(190 + gap / 2, 1e-9));
    expect(first.top, closeTo(195 + gap / 2, 1e-9));
    expect(last.right, closeTo(1060 - gap / 2, 1e-9));
    expect(last.bottom, closeTo(1065 - gap / 2, 1e-9));
    for (var i = 0; i < 64; i++) {
      expect(FlowPlayfield.cellAt(FlowPlayfield.cellRect(i).center), i);
    }
    // A drag that starts on the frame still picks the nearest edge cell.
    expect(FlowPlayfield.cellAt(const Offset(120, 120)), 0);
    expect(FlowPlayfield.cellAt(const Offset(1140, 1140)), 63);
  });

  test('the backplate is placed by its visible part and the box shows the '
      'frame', () {
    final placed = FlowPlayfield.place(
      FlowPlayfield.backplateVisible,
      FlowPlayfield.backplateDest,
    );
    final sx = placed.width / FlowPlayfield.canvas;
    expect(placed.left + 56 * sx, closeTo(151, 1e-9));
    expect(placed.left + 1198 * sx, closeTo(1098, 1e-9));
    // The frame's visible part spans the board box; points round-trip.
    final box = FlowPlayfield.toBox(FlowPlayfield.frameVisible, 300);
    expect(box.left, closeTo(0, 1e-9));
    expect(box.right, closeTo(300, 1e-9));
    const p = Offset(123, 210);
    final back = FlowPlayfield.toCanvas(
      FlowPlayfield.toBox(
        Rect.fromCenter(center: p, width: 0, height: 0),
        300,
      ).center,
      300,
    );
    expect(back.dx, closeTo(p.dx, 1e-9));
    expect(back.dy, closeTo(p.dy, 1e-9));
  });
}
