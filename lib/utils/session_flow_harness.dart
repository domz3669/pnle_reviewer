class SessionFlowState {
  final int remainingSessions;
  final int adChances;
  final int maxAdChances;
  final DateTime? nextAdRefillAt;
  final Duration adRefillDuration;
  final int completedSessions;
  final String? lastStreakRewardClaimDate;
  final bool isOnline;

  const SessionFlowState({
    required this.remainingSessions,
    required this.adChances,
    required this.maxAdChances,
    required this.nextAdRefillAt,
    required this.adRefillDuration,
    required this.completedSessions,
    required this.lastStreakRewardClaimDate,
    required this.isOnline,
  });

  SessionFlowState copyWith({
    int? remainingSessions,
    int? adChances,
    int? maxAdChances,
    DateTime? nextAdRefillAt,
    bool clearNextAdRefillAt = false,
    Duration? adRefillDuration,
    int? completedSessions,
    String? lastStreakRewardClaimDate,
    bool clearLastStreakRewardClaimDate = false,
    bool? isOnline,
  }) {
    return SessionFlowState(
      remainingSessions: remainingSessions ?? this.remainingSessions,
      adChances: adChances ?? this.adChances,
      maxAdChances: maxAdChances ?? this.maxAdChances,
      nextAdRefillAt:
          clearNextAdRefillAt ? null : (nextAdRefillAt ?? this.nextAdRefillAt),
      adRefillDuration: adRefillDuration ?? this.adRefillDuration,
      completedSessions: completedSessions ?? this.completedSessions,
      lastStreakRewardClaimDate: clearLastStreakRewardClaimDate
          ? null
          : (lastStreakRewardClaimDate ?? this.lastStreakRewardClaimDate),
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

class SessionFlowHarness {
  const SessionFlowHarness._();

  static SessionFlowState consumeSession(SessionFlowState state) {
    if (!state.isOnline || state.remainingSessions <= 0) {
      return state;
    }

    return state.copyWith(remainingSessions: state.remainingSessions - 1);
  }

  static SessionFlowState skipSession(SessionFlowState state) {
    return consumeSession(state);
  }

  static SessionFlowState processAdRefill(
    SessionFlowState state,
    DateTime now,
  ) {
    var chances = state.adChances.clamp(0, state.maxAdChances);
    var nextRefillAt = state.nextAdRefillAt;

    if (chances >= state.maxAdChances) {
      return state.copyWith(
        adChances: state.maxAdChances,
        clearNextAdRefillAt: true,
      );
    }

    if (nextRefillAt == null) {
      nextRefillAt = now.add(state.adRefillDuration);
    }

    while (nextRefillAt != null &&
        !now.isBefore(nextRefillAt) &&
        chances < state.maxAdChances) {
      chances += 1;
      if (chances < state.maxAdChances) {
        nextRefillAt = nextRefillAt.add(state.adRefillDuration);
      } else {
        nextRefillAt = null;
      }
    }

    return state.copyWith(
      adChances: chances,
      nextAdRefillAt: nextRefillAt,
      clearNextAdRefillAt: nextRefillAt == null,
    );
  }

  static SessionFlowState rewardedAdSuccess(
    SessionFlowState state,
    DateTime now,
  ) {
    if (!state.isOnline) return state;

    final refilled = processAdRefill(state, now);
    if (refilled.adChances <= 0) {
      return refilled;
    }

    final updatedChances = refilled.adChances - 1;
    final shouldTrackRefill = updatedChances < refilled.maxAdChances;

    return refilled.copyWith(
      remainingSessions: refilled.remainingSessions + 1,
      adChances: updatedChances,
      nextAdRefillAt:
          shouldTrackRefill ? now.add(refilled.adRefillDuration) : null,
      clearNextAdRefillAt: !shouldTrackRefill,
    );
  }

  static bool canClaimStreakReward(
    SessionFlowState state,
    String todayKey,
  ) {
    return state.isOnline &&
        state.completedSessions >= 4 &&
        state.lastStreakRewardClaimDate != todayKey;
  }

  static SessionFlowState claimStreakReward(
    SessionFlowState state,
    String todayKey,
  ) {
    if (!canClaimStreakReward(state, todayKey)) {
      return state;
    }

    return state.copyWith(
      remainingSessions: state.remainingSessions + 1,
      lastStreakRewardClaimDate: todayKey,
    );
  }

  static bool shouldSyncOnReconnect({
    required bool wasOnline,
    required bool isOnline,
  }) {
    return !wasOnline && isOnline;
  }
}
