App Review Notes (Guideline 2.3.1(a) and 4.2)

Paste-Ready App Review Note
USTET Reviewer 2027 is a native Flutter quiz app for UST entrance exam preparation. It is not a webview or browser wrapper.

This build launches to the native home screen even when the device starts offline. Random Quiz, Focus Mode, and Timed Exam can start from local seeded question sets without internet. Internet access is only required for progress syncing, streak rewards, ads, Challenge Mode generation, and optional AI-generated Coach Note explanations requested during a quiz.

Core features visible in this build are Random Quiz, Focus Mode, Timed Exam, Saved Sessions, History, Results Analytics, and Coach Note explanations. No subscriptions or hidden post-review features are included.

Suggested Rejection Response
Thank you for the review. We revised the app to make the core experience clearer and immediately accessible. The app now launches to its native home screen even without internet, and core quiz modes can start from local seeded question sets. We also updated the in-app disclosures and metadata to clarify that Coach Note explanations are optional AI-generated features requested from within a quiz, while syncing and certain online-only features require internet access. The visible features in this build are fully aligned with the current metadata and screenshots.

Summary
- This build is a native Flutter app and is not a web wrapper.
- No subscriptions or in-app purchase flows are included in this build.
- Core quiz features are available immediately after onboarding, including when the device starts offline.

Reviewer Test Path
1. Launch the app.
2. Complete onboarding by entering a nickname.
3. On the home/start screen:
   - Tap Random Quiz to start immediately.
   - Tap Focus Mode to start targeted practice immediately.
   - Tap Timed Exam to start a timed local session immediately.
   - Tap Challenge Mode to start advanced mixed practice when online.
4. During/after a quiz:
   - Submit answers to view results and analytics.
   - Save a session and use Load Saved Test.
   - Tap Coach Note to request an AI-generated explanation for the current question.
5. Open History tab:
   - View 10-day performance record and summary stats.

Feature Notes
- Random Quiz: 15-question mixed UPCAT practice.
- Focus Mode: category-targeted practice available on first launch.
- Timed Exam: countdown-based practice mode.
- Challenge Mode: advanced mixed simulation when online generation is available.
- History: local performance and recent activity insights.
- Saved Tests: replay previously saved sessions.
- Coach Note: optional AI-generated explanation requested from inside a quiz.

Network and Fallback Behavior
- The app launches even without internet and shows the native home screen.
- Random Quiz, Focus Mode, and Timed Exam can start from local seeded question pools while offline.
- Syncing, streak rewards, ads, and Coach Note explanations resume when internet access returns.
- If remote generation is unavailable, online-only features degrade gracefully and show a clear message.

Metadata Alignment
- Screenshots and metadata should match this build's visible features:
   Random Quiz, Focus Mode, Timed Exam, Coach Note, History, and Saved Tests.

Reviewer Advice
- Do not mention features that are planned, partially wired, or only conditionally available.
- Avoid saying the app works fully offline. Be precise: core seeded quiz modes start offline, while syncing and Coach Note explanations require internet.
- If Challenge Mode is shown in screenshots, capture it from a successful online session and avoid wording that implies offline availability.
