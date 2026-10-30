import 'package:flutter/material.dart';

/// Design tokens taken from the reference image: deep-teal -> mint header gradient, white rounded cards,
/// teal primary actions, pill chips, capsule bottom navigation. Everything visual reads from here.
abstract final class Tk {
  // Brand
  static const tealDeep = Color(0xFF2E6573);
  static const tealMid = Color(0xFF5A949B);
  static const mint = Color(0xFFC9DFDB);
  static const mintSoft = Color(0xFFE6F0EF);
  static const primary = Color(0xFF1F7679); // white text on it >= 5:1
  static const primaryDark = Color(0xFF2F5F6B);
  static const onPrimary = Colors.white;

  // Surfaces and text (all text/background pairs meet WCAG AA contrast)
  static const page = Color(0xFFF4F8F8);
  static const surface = Colors.white;
  static const text = Color(0xFF16313A);
  static const textMuted = Color(0xFF52696F);
  static const border = Color(0xFFE1ECEC);

  // Status palette. Colour is NEVER the only signal: each status also has an icon and a word.
  static const danger = Color(0xFFB3261E);
  static const dangerBg = Color(0xFFFDECEA);
  static const warn = Color(0xFF8A5300);
  static const warnBg = Color(0xFFFFF1D6);
  static const ok = Color(0xFF1B6E3C);
  static const okBg = Color(0xFFE3F4E8);
  static const info = Color(0xFF1F5F8B);
  static const infoBg = Color(0xFFE2EFF8);
  static const neutral = Color(0xFF4A5A5F);
  static const neutralBg = Color(0xFFE9EEEF);

  // Shape and spacing
  static const rCard = 22.0;
  static const rButton = 16.0;
  static const rChip = 999.0;
  static const s4 = 4.0,
      s8 = 8.0,
      s12 = 12.0,
      s16 = 16.0,
      s20 = 20.0,
      s24 = 24.0,
      s32 = 32.0;
  static const minTouch = 52.0; // field workers, often one-handed and outdoors: larger than the 48dp minimum

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    // stays dark all the way down: white header text must keep >= 4.5:1 contrast
    colors: [Color(0xFF1B5662), Color(0xFF226571)],
  );

  /// Deep-teal fill for hero cards and the main call-to-action (white text on it is well above 4.5:1).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B5662), Color(0xFF226571)],
  );

  static const cardShadow = [
    BoxShadow(color: Color(0x0F16313A), blurRadius: 4, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1416313A), blurRadius: 18, offset: Offset(0, 8)),
  ];
}
