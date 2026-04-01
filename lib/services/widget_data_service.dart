import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Sends study data to the iOS Home Screen Widget via App Groups.
class WidgetDataService {
  WidgetDataService._();
  static final WidgetDataService instance = WidgetDataService._();

  static const String _appGroupId =
      'group.com.niotron.domingotambasacan.pnleaireviewer2026';
  static const String _iOSWidgetName = 'StudyWidget';
  static const String _androidWidgetName = 'StudyWidgetProvider';

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      _initialized = true;
    } catch (e) {
      debugPrint('WidgetDataService init error: $e');
    }
  }

  /// Update the widget with latest study data.
  Future<void> updateWidget({
    required int streak,
    required int readinessScore,
    required int sessionsToday,
  }) async {
    try {
      await initialize();
      await HomeWidget.saveWidgetData('study_streak', streak);
      await HomeWidget.saveWidgetData('readiness_score', readinessScore);
      await HomeWidget.saveWidgetData('sessions_today', sessionsToday);
      await HomeWidget.updateWidget(
        iOSName: _iOSWidgetName,
        androidName: _androidWidgetName,
      );
    } catch (e) {
      debugPrint('Widget update error: $e');
    }
  }
}
