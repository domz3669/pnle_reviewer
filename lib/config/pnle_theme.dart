import 'package:flutter/material.dart';

class PnleTheme {
  static const Color bgTop = Color(0xFF4A6E8A);
  static const Color bgBottom = Color(0xFF2A4560);

  static const Color glowA = Color(0xFFA8D0F0);
  static const Color glowB = Color(0xFF6BA3D6);

  static const Color accent = Color(0xFF6BA3D6);
  static const Color accentDeep = Color(0xFF4A85B8);

  static const Color glassFill = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x446BA3D6);

  static const Color success = Color(0xFF6F95E8);
  static const Color successDeep = Color(0xFF466DBF);
  static const Color info = Color(0xFF9EBCFF);
  static const Color infoDeep = Color(0xFF6C8EDD);
  static const Color neutral = Color(0xFFA8B6D3);
  static const Color warning = Color(0xFFD9B24C);
  static const Color warningDeep = Color(0xFFAA7F12);
  static const Color danger = Color(0xFFB3213D);
  static const Color dangerSoft = Color(0xFFE5A0AC);

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
