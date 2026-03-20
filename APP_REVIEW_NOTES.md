App Review Notes (Guideline 2.3.1(a) and 4.2)

Summary
- This build is a native Flutter app and is not a web wrapper.
- No subscriptions or in-app purchase flows are included in this build.
- Core quiz features are available immediately after onboarding.

Reviewer Test Path
1. Launch the app.
2. Complete onboarding by entering a nickname.
3. On the home/start screen:
   - Tap Random Quiz to start immediately.
   - Tap Focus Mode to start targeted practice immediately.
   - Tap Challenge Mode to start advanced mixed practice.
4. During/after a quiz:
   - Submit answers to view results and analytics.
   - Save a session and use Load Saved Test.
5. Open History tab:
   - View 10-day performance record and summary stats.

Feature Notes
- Random Quiz: 15-question mixed UPCAT practice.
- Focus Mode: category-targeted practice available on first launch.
- Challenge Mode: advanced mixed simulation.
- History: local performance and recent activity insights.
- Saved Tests: replay previously saved sessions.

Network and Fallback Behavior
- If network is unstable, the app uses local seeded content where available.
- If remote generation is unavailable, the app degrades gracefully and shows a clear message.

Metadata Alignment
- Screenshots and metadata should match this build's visible features:
  Random Quiz, Focus Mode, Challenge Mode, History, and Saved Tests.
