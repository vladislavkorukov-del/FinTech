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
  'aurora': ReferencePalette(
    base: Color(0xFF1A1A1F),
    card: Color(0xFF2D2B55),
    panel: Color(0xFF6A5ACD),
    accent: Color(0xFFA678B9),
    ink: Color(0xFFF0D9B5),
    signal: Color(0xFFF4A62A),
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
};
