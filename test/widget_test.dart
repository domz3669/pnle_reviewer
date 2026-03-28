import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:let_reviewer/animated_results_dialog.dart';
import 'package:let_reviewer/models/acet_assessment.dart';
import 'package:let_reviewer/settings_screen.dart';

void main() {
  testWidgets('Settings screen shows current personalization values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const TestApp(
        child: SettingsScreen(
          nickname: 'Domz',
          muteAllSounds: true,
          notificationsEnabled: true,
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Domz'), findsOneWidget);
    expect(find.text('Study Notifications'), findsOneWidget);
    expect(find.text('Mute All Sounds'), findsOneWidget);
  });

  testWidgets('Settings toggles call callbacks with updated values', (
    WidgetTester tester,
  ) async {
    bool? muteCallbackValue;
    bool? notificationsCallbackValue;
    bool? strictTimingCallbackValue;

    await tester.pumpWidget(
      TestApp(
        child: SettingsScreen(
          nickname: 'Domz',
          muteAllSounds: false,
          notificationsEnabled: false,
          strictTimingEnabled: false,
          onMuteAllSoundsChanged: (value) async {
            muteCallbackValue = value;
          },
          onNotificationsChanged: (value) async {
            notificationsCallbackValue = value;
            return value;
          },
          onStrictTimingChanged: (value) async {
            strictTimingCallbackValue = value;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('toggle_mute_all_sounds')));
    await tester.pumpAndSettle();
    expect(muteCallbackValue, isTrue);

    await tester.tap(find.byKey(const Key('toggle_notifications')));
    await tester.pumpAndSettle();
    expect(notificationsCallbackValue, isTrue);

    await tester.tap(find.byKey(const Key('toggle_strict_timing')));
    await tester.pumpAndSettle();
    expect(strictTimingCallbackValue, isTrue);
  });

  testWidgets('Results dialog shows benchmark and drill guidance', (
    WidgetTester tester,
  ) async {
    final assessment = AcetAssessment(
      totalQuestions: 15,
      correctAnswers: 10,
      wrongAnswers: 5,
      unansweredAnswers: 0,
      timedOutCount: 1,
      accuracyPercent: 66.7,
      averageTimePerQuestionSeconds: 57.0,
      efficiencyScore: 70.0,
      readinessLabel: 'Developing',
      fastAnswerCount: 4,
      moderateAnswerCount: 7,
      slowAnswerCount: 4,
      questionsPerMinute: 1.05,
      insightMessage: 'Keep practicing your weakest sections.',
      recommendedFocusCategory: 'Mathematics',
      perCategoryStats: {
        'English': const AcetCategoryAssessment(
          category: 'English',
          correctAnswers: 3,
          totalQuestions: 5,
          accuracyPercent: 60,
          averageTimePerQuestionSeconds: 54,
          statusLabel: 'Needs Accuracy',
        ),
        'Mathematics': const AcetCategoryAssessment(
          category: 'Mathematics',
          correctAnswers: 2,
          totalQuestions: 5,
          accuracyPercent: 40,
          averageTimePerQuestionSeconds: 67,
          statusLabel: 'Needs Speed',
        ),
      },
    );

    await tester.pumpWidget(
      TestApp(
        child: AnimatedResultsDialog(
          assessment: assessment,
          hasUnlimitedAccess: false,
          testMode: 'timedExam',
          elapsedSeconds: 860,
          onResultAction: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Benchmark'), findsOneWidget);
    expect(find.text('Band C'), findsOneWidget);
    expect(find.textContaining('Next drill:'), findsOneWidget);
  });
}

class TestApp extends StatelessWidget {
  const TestApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: child);
  }
}
