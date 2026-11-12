import 'package:flutter/material.dart';

/// Original reference colors. The shared builder derives only contrast-safe
/// text tones and light surfaces; these six source tokens remain unchanged.
@immutable
class ReferencePalette {
  const ReferencePalette({
    required this.base,
    required this.card,
    required this.panel,
    required this.accent,
    required this.ink,
    required this.signal,
  });
  final Color base, card, panel, accent, ink, signal;
}

const referencePalettes = <String, ReferencePalette>{
  'harbor': ReferencePalette(
    base: Color(0xFF0B132B),
    card: Color(0xFF1C2541),
    panel: Color(0xFF3A506B),
    accent: Color(0xFF5BC0DE),
    ink: Color(0xFFF4D6B0),
    signal: Color(0xFFD97706),
  ),
  'forest': ReferencePalette(
    base: Color(0xFF0B0F0D),
    card: Color(0xFF1F2A1F),
    panel: Color(0xFF3E5A3E),
    accent: Color(0xFF8CA98C),
    ink: Color(0xFFD9C7A3),
    signal: Color(0xFFB08D57),
  ),
  'velvet': ReferencePalette(
    base: Color(0xFF0E0B1D),
    card: Color(0xFF2A1E4D),
    panel: Color(0xFF5A3B8C),
    accent: Color(0xFF8B7CC7),
    ink: Color(0xFFC9C2E3),
    signal: Color(0xFF3A3A52),
  ),
  // The two-color Royal/Nitro reference supplies the card and accent. The
  // background, panel, text and signal are derived supporting colors.
  'royal': ReferencePalette(
    base: Color(0xFF09091F),
    card: Color(0xFF191970),
    panel: Color(0xFF2D2D88),
    accent: Color(0xFFFB5607),
    ink: Color(0xFFF7F5F1),
    signal: Color(0xFFFFA775),
  ),
  // Finance 1.9: palettes from the owner's references. Colors visible in the
  // reference are kept; a darker base or a readable ink is derived only where
  // the reference has none.
  'sunset': ReferencePalette(
    base: Color(0xFF1C0B33),
    card: Color(0xFF2B124C),
    panel: Color(0xFF78215C),
    accent: Color(0xFFFDB553),
    ink: Color(0xFFFFF3D6),
    signal: Color(0xFFE77655),
  ),
  'neon': ReferencePalette(
    base: Color(0xFF160B26),
    card: Color(0xFF2A1650),
    panel: Color(0xFF662E9B),
    accent: Color(0xFF43BCCD),
    ink: Color(0xFFFFF6E3),
    signal: Color(0xFFF86624),
  ),
  'dusk': ReferencePalette(
    base: Color(0xFF1D1A39),
    card: Color(0xFF2D1F4A),
    panel: Color(0xFF451952),
    accent: Color(0xFFF39F5A),
    ink: Color(0xFFF5E2DF),
    signal: Color(0xFFAE445A),
  ),
  'emerald': ReferencePalette(
    base: Color(0xFF051F20),
    card: Color(0xFF0B2B26),
    panel: Color(0xFF235347),
    accent: Color(0xFF8EB69B),
    ink: Color(0xFFDAF1DE),
    // Monochrome reference: a warm derived tone keeps expenses distinct.
    signal: Color(0xFFD9A27E),
  ),
  'tropic': ReferencePalette(
    base: Color(0xFF052733),
    card: Color(0xFF073A4B),
    panel: Color(0xFF108AB1),
    accent: Color(0xFF06D7A0),
    ink: Color(0xFFFFF6E0),
    signal: Color(0xFFF04770),
  ),
  'twilight': ReferencePalette(
    base: Color(0xFF0E1A2B),
    card: Color(0xFF1A2C44),
    panel: Color(0xFF26425A),
    accent: Color(0xFF86A8CF),
    ink: Color(0xFFE1CBD7),
    signal: Color(0xFFC38EB4),
  ),
  'apricot': ReferencePalette(
    base: Color(0xFF2A1F38),
    card: Color(0xFF433258),
    panel: Color(0xFF5B4876),
    accent: Color(0xFFF5A623),
    ink: Color(0xFFFFE5D9),
    signal: Color(0xFFF0803A),
  ),
};
