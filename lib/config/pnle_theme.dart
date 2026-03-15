import 'package:flutter/material.dart';

class PnleTheme {
  static const Color bgTop = Color(0xFF5A1530);
  static const Color bgBottom = Color(0xFF0E3B2E);

  static const Color glowA = Color(0xFFE8A7B9);
  static const Color glowB = Color(0xFFAAC7EA);

  static const Color accent = Color(0xFFF4C542);
  static const Color accentDeep = Color(0xFFE29DB0);

  static const Color glassFill = Color(0x1FFFFFFF);
  static const Color glassBorder = Color(0x42FFFFFF);

  static const Color success = Color(0xFF86D6A5);
  static const Color warning = Color(0xFFF3C66A);
  static const Color danger = Color(0xFFE88D9A);

  static const LinearGradient appBackground = LinearGradient(
    colors: [bgTop, bgBottom],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient actionGradient = LinearGradient(
    colors: [accent, accentDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
