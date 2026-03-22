import 'package:flutter/material.dart';

class PnleTheme {
  // UST-inspired palette: royal blue, navy, and gold.
  static const Color bgTop = Color(0xFF0A2B63);
  static const Color bgBottom = Color(0xFF061A3A);

  static const Color glowA = Color(0xFFFFD66B);
  static const Color glowB = Color(0xFF7DB8F5);

  static const Color accent = Color(0xFFF3C13A);
  static const Color accentDeep = Color(0xFFD59D14);

  static const Color glassFill = Color(0x1FFFFFFF);
  static const Color glassBorder = Color(0x42FFFFFF);

  static const Color success = Color(0xFF7DD3FC);
  static const Color warning = Color(0xFFFFD166);
  static const Color danger = Color(0xFFFF7B72);

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
