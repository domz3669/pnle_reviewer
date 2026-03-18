import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:let_reviewer/utils/session_flow_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const refillDuration = Duration(hours: 2);

  SessionFlowState seedState({
    int remainingSessions = 4,
    int adChances = 2,
    int completedSessions = 0,
    String? lastClaimDate,
    bool isOnline = true,
    DateTime? nextRefillAt,
  }) {
    return SessionFlowState(
      remainingSessions: remainingSessions,
      adChances: adChances,
      maxAdChances: 2,
      nextAdRefillAt: nextRefillAt,
      adRefillDuration: refillDuration,
      completedSessions: completedSessions,
      lastStreakRewardClaimDate: lastClaimDate,
      isOnline: isOnline,
    );
  }

  group('Session Flow Harness', () {
    testWidgets('consumes sessions down to zero and blocks at zero',
        (tester) async {
      var state = seedState(remainingSessions: 2);

      state = SessionFlowHarness.consumeSession(state);
      state = SessionFlowHarness.consumeSession(state);
      final blocked = SessionFlowHarness.consumeSession(state);

      expect(state.remainingSessions, 0);
      expect(blocked.remainingSessions, 0);
    });

    testWidgets('depletes ad chances and refills by countdown', (tester) async {
      final now = DateTime(2026, 3, 18, 8, 0, 0);
      var state = seedState(adChances: 2);

      state = SessionFlowHarness.rewardedAdSuccess(state, now);
      state = SessionFlowHarness.rewardedAdSuccess(
          state, now.add(const Duration(minutes: 1)));

      expect(state.adChances, 0);
      expect(state.nextAdRefillAt, isNotNull);

      state = SessionFlowHarness.processAdRefill(
        state,
        now.add(refillDuration + const Duration(minutes: 1)),
      );
      expect(state.adChances, 1);

      state = SessionFlowHarness.processAdRefill(
        state,
        now.add(refillDuration * 2 + const Duration(minutes: 1)),
      );
      expect(state.adChances, 2);
      expect(state.nextAdRefillAt, isNull);
    });

    testWidgets('skip consumes one session like a started session',
        (tester) async {
      final before = seedState(remainingSessions: 3);
      final after = SessionFlowHarness.skipSession(before);
      expect(after.remainingSessions, 2);
    });

    testWidgets('streak completion allows one claim per day', (tester) async {
      const todayKey = '2026-03-18';
      var state = seedState(completedSessions: 4, remainingSessions: 0);

      expect(SessionFlowHarness.canClaimStreakReward(state, todayKey), isTrue);

      state = SessionFlowHarness.claimStreakReward(state, todayKey);
      expect(state.remainingSessions, 1);
      expect(state.lastStreakRewardClaimDate, todayKey);
      expect(SessionFlowHarness.canClaimStreakReward(state, todayKey), isFalse);
    });

    testWidgets('reconnect flow triggers sync only on offline to online',
        (tester) async {
      expect(
        SessionFlowHarness.shouldSyncOnReconnect(
            wasOnline: false, isOnline: true),
        isTrue,
      );
      expect(
        SessionFlowHarness.shouldSyncOnReconnect(
            wasOnline: true, isOnline: false),
        isFalse,
      );
      expect(
        SessionFlowHarness.shouldSyncOnReconnect(
            wasOnline: true, isOnline: true),
        isFalse,
      );
    });
  });
}
