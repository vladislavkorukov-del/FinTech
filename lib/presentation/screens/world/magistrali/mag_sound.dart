import 'dart:async';

import '../../../../domain/magistrali/magistrali.dart';
import '../../../../services/mag_audio.dart';

/// What the game sounds like (S21): it watches the company and plays a
/// coin for income, a fanfare for a new level, a thud for a new road or
/// building, a horn for a new vehicle.
class MagSound {
  final audio = MagAudio();
  int? _level, _roads, _places, _vehicles;

  void configure(MagWorld w, {required bool active}) => unawaited(
    audio.configure(active: active, music: w.musicOn, sound: w.soundOn),
  );

  void play(String name, {double volume = 1, int gapMs = 90}) =>
      unawaited(audio.effect(name, volume: volume, gapMs: gapMs));

  /// After simulation steps or a player's action.
  void watch(MagWorld w, {bool income = false}) {
    if (income) play('coin', volume: .7, gapMs: 140);
    if (_level != null && w.level > _level!) play('levelup');
    if (_roads != null && w.roadVersion > _roads!) play('build', volume: .8);
    final places = w.map.industries.length;
    if (_places != null && places > _places!) play('build');
    final vehicles = w.vehicles.length;
    if (_vehicles != null && vehicles > _vehicles!) play('horn', volume: .7);
    _level = w.level;
    _roads = w.roadVersion;
    _places = places;
    _vehicles = vehicles;
  }

  void close() => unawaited(audio.close());
}
