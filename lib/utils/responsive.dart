import 'package:flutter/material.dart';

class Responsive {
  final BuildContext context;
  
  Responsive(this.context);
  
  // Screen dimensions
  double get width => MediaQuery.of(context).size.width;
  double get height => MediaQuery.of(context).size.height;
  
  // Device type detection
  bool get isSmallPhone => width < 360;
  bool get isPhone => width < 600;
  bool get isTablet => width >= 600 && width < 900;
  bool get isDesktop => width >= 900;
  
  // Responsive font sizes
  double fontSize(double base) {
    if (isSmallPhone) return base * 0.9;
    if (isTablet) return base * 1.15;
    if (isDesktop) return base * 1.3;
    return base;
  }
  
  // Responsive spacing
  double spacing(double base) {
    if (isSmallPhone) return base * 0.85;
    if (isTablet) return base * 1.2;
    if (isDesktop) return base * 1.4;
    return base;
  }
  
  // Responsive padding
  EdgeInsets padding(double value) {
    return EdgeInsets.all(spacing(value));
  }
  
  EdgeInsets paddingSymmetric({double horizontal = 0, double vertical = 0}) {
    return EdgeInsets.symmetric(
      horizontal: spacing(horizontal),
      vertical: spacing(vertical),
    );
  }
  
  // Responsive sizing
  double size(double base) {
    if (isSmallPhone) return base * 0.9;
    if (isTablet) return base * 1.2;
    if (isDesktop) return base * 1.4;
    return base;
  }
}

// Extension for easy access
extension ResponsiveContext on BuildContext {
  Responsive get responsive => Responsive(this);
}
