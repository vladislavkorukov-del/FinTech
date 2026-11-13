import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/finorio/finorio.dart';
import 'finorio_art.dart';

class _Particle {
  _Particle(this.at, this.v, this.color, this.size, this.life);
  Offset at, v;
  final Color color;
  final double size;
  double life, age = 0;
}

/// Motion that only decorates: buildings pop in when placed, leave a puff
/// when taken down, throw sparks when a cycle finishes, breathe while
/// working; generators and furnaces give off a few motes. Runs on the
/// screen's clock, never touches the simulation; off with reduced motion.
class FinFx {
  double now = 0;
  bool enabled = true;
  bool _primed = false;
  final _born = <int, double>{};
  final _seen = <int, (int, int, FinBuilding)>{};
  final _progress = <int, int>{};
  final _particles = <_Particle>[];
  final _rnd = math.Random(5);
  double _ambient = 0;

  void step(FinWorld w, double seconds, double dt, {required bool enabled}) {
    now = seconds;
    this.enabled = enabled;
    if (!enabled) {
      _particles.clear();
      _born.clear();
    }
    final ids = <int>{};
    for (final m in w.machines.values) {
      ids.add(m.id);
      if (!_seen.containsKey(m.id) && _primed && enabled) _born[m.id] = now;
      _seen[m.id] = (m.x, m.y, m.kind);
      final last = _progress[m.id] ?? 0;
      if (enabled &&
          m.progress < last &&
          !m.isBelt &&
          m.kind != FinBuilding.generator) {
        _burst(m.x + .5, m.y + .5, _product(m, w), 9);
      }
      _progress[m.id] = m.progress;
    }
    for (final id in _seen.keys.toList()) {
      if (ids.contains(id)) continue;
      final (x, y, kind) = _seen.remove(id)!;
      _progress.remove(id);
      _born.remove(id);
      if (enabled) _puff(x + .5, y + .5, FinPalette.accent(kind));
    }
    _primed = true;
    if (!enabled) return;
    // A few motes from working generators and furnaces.
    _ambient += dt;
    if (_ambient > .22) {
      _ambient = 0;
      for (final m in w.machines.values) {
        if (m.status != FinStatus.working) continue;
        if (m.kind == FinBuilding.generator || m.kind == FinBuilding.furnace) {
          final hot = m.kind == FinBuilding.furnace;
          _particles.add(
            _Particle(
              Offset(m.x + .5 + (_rnd.nextDouble() - .5) * .3, m.y + .45),
              Offset(
                (_rnd.nextDouble() - .5) * .15,
                -.35 - _rnd.nextDouble() * .2,
              ),
              hot ? const Color(0xFFFFB45C) : const Color(0xFF7CF2CF),
              .045 + _rnd.nextDouble() * .03,
              1.1,
            ),
          );
        }
      }
    }
    for (final p in _particles) {
      p.age += dt;
      p.at += p.v * dt;
      p.v = Offset(p.v.dx * .96, p.v.dy + .25 * dt);
    }
    _particles.removeWhere((p) => p.age >= p.life);
    if (_particles.length > 400) {
      _particles.removeRange(0, _particles.length - 400);
    }
  }

  FinItem? _product(FinMachine m, FinWorld w) {
    if (m.kind == FinBuilding.drill) {
      return FinConfig.deposits[w.terrain.at(m.x, m.y)];
    }
    return FinConfig.recipe(m.recipe)?.output;
  }

  void _burst(double x, double y, FinItem? item, int n) {
    final color = item == null ? FinPalette.teal : FinPalette.item(item);
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final speed = .5 + _rnd.nextDouble() * .7;
      _particles.add(
        _Particle(
          Offset(x, y),
          Offset(math.cos(a), math.sin(a)) * speed,
          Color.lerp(color, Colors.white, .35)!,
          .04 + _rnd.nextDouble() * .03,
          .55,
        ),
      );
    }
  }

  void _puff(double x, double y, Color color) {
    for (var i = 0; i < 16; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      _particles.add(
        _Particle(
          Offset(x, y),
          Offset(math.cos(a), math.sin(a)) * (.3 + _rnd.nextDouble() * .5),
          Color.lerp(color, Colors.white, .5)!.withValues(alpha: .8),
          .07 + _rnd.nextDouble() * .06,
          .7,
        ),
      );
    }
  }

  /// Whether a building is still popping in (its joins wait for it).
  bool popping(FinMachine? m) =>
      enabled &&
      m != null &&
      _born.containsKey(m.id) &&
      now - _born[m.id]! < .32;

  /// Scale of a building: a springy pop after placing, a gentle breath
  /// while working.
  double scaleOf(FinMachine m) {
    if (!enabled) return 1;
    var s = 1.0;
    final born = _born[m.id];
    if (born != null) {
      final t = ((now - born) / .32).clamp(0.0, 1.0);
      if (t >= 1) {
        _born.remove(m.id);
      } else {
        s = Curves.easeOutBack.transform(t).clamp(0.0, 1.3) * .9 + .1;
      }
    }
    if (!m.isBelt && m.status == FinStatus.working) {
      s *= 1 + .018 * math.sin(now * 7 + m.id);
    }
    return s;
  }

  void paint(Canvas c) {
    for (final p in _particles) {
      final k = 1 - p.age / p.life;
      c.drawCircle(
        p.at,
        p.size * (.6 + .4 * k),
        Paint()..color = p.color.withValues(alpha: p.color.a * k),
      );
    }
  }
}
