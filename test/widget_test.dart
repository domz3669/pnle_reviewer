import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    await tester.pumpWidget(
      TestApp(
        child: SettingsScreen(
          nickname: 'Domz',
          muteAllSounds: false,
          notificationsEnabled: false,
          onMuteAllSoundsChanged: (value) async {
            muteCallbackValue = value;
          },
          onNotificationsChanged: (value) async {
            notificationsCallbackValue = value;
            return value;
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
