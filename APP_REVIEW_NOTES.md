App Review Notes (Guideline 2.3.1(a) and 4.2)

Paste-Ready App Review Note
ACET Reviewer 2027 is a native Flutter quiz app for ACET preparation. It is not a webview or browser wrapper.

This build launches to the native home screen even when the device starts offline. Random Quiz, Focus Mode, and Timed Exam can start from local seeded question sets without internet. Internet access is only required for progress syncing, streak rewards, ads, Challenge Mode generation, report submission, and optional AI-generated Coach Note explanations requested during a quiz.

Core features visible in this build are Random Quiz, Focus Mode, Timed Exam, Challenge Mode, Saved Sessions, History, Results Analytics, and optional Coach Note explanations. No subscriptions, hidden reviewer-only paths, or post-review feature switches are included.

Suggested Rejection Response
Thank you for the review. We revised the app to make the core experience clearer and immediately accessible. The app launches directly to its native home screen, and the core quiz modes Random Quiz, Focus Mode, and Timed Exam can start from local seeded question sets even without internet. We also updated the in-app disclosures and metadata to clarify that Coach Note explanations are optional AI-generated features requested by the user from within a quiz, while syncing, rewards, ads, report submission, and Challenge Mode generation require internet access. The visible features in this build are aligned with the current metadata and screenshots.

Summary
- This build is a native Flutter app and is not a web wrapper.
- No subscriptions or in-app purchase flows are included in this build.
- Core quiz features are available immediately after onboarding, including when the device starts offline.

Reviewer Test Path
1. Launch the app.
2. Complete onboarding by entering a nickname.
3. On the Quiz section:
   - Tap Random Quiz to open Test Coverage and create a local quiz.
   - Tap Focus Mode to open its coverage dialog and create a targeted quiz.
   - Tap Timed Exam to start a timed local session.
   - Tap Challenge Mode while online to start advanced mixed practice.
4. During or after a quiz:
   - Submit answers to view results and analytics.
   - Save a session and use Load Saved Test.
   - Tap Coach Note after answering to request an optional AI-generated explanation.
5. Open History:
   - View recent performance, category insights, and 10-day records.

Feature Notes
- Random Quiz: 15-question mixed ACET practice.
- Focus Mode: category-targeted practice available on first launch.
- Timed Exam: countdown-based practice mode.
- Challenge Mode: advanced mixed simulation when online generation is available.
- History: local performance and recent activity insights.
- Saved Tests: replay previously saved sessions.
- Coach Note: optional AI-generated explanation requested from inside a quiz after answering.
- Rewards: optional daily session-reward tasks and ad-based session refill.

Network and Fallback Behavior
- The app launches even without internet and shows the native home screen.
- Random Quiz, Focus Mode, and Timed Exam can start from local seeded question pools while offline.
- Syncing, streak rewards, ads, report submission, Challenge Mode generation, and Coach Note explanations resume when internet access returns.
- If remote generation or online services are unavailable, the app degrades gracefully and shows a clear message.

Current Build Clarifications
- Report Inaccuracy is available from the question and explanation flow. If the report service is unavailable, the app stores the report locally instead of blocking the user.
- Coach Note is optional and user-invoked only after answering a question.
- Paused sessions expire at the next daily reset and do not carry across days.

Metadata Alignment
- Screenshots and metadata should match this build's visible features:
  Random Quiz, Focus Mode, Timed Exam, Challenge Mode, Coach Note, History, and Saved Tests.

Reviewer Advice
- Do not mention features that are planned, partially wired, or only conditionally available.
- Avoid saying the app works fully offline. Be precise: core seeded quiz modes start offline, while syncing and Coach Note explanations require internet.
- If Challenge Mode is shown in screenshots, capture it from a successful online session and avoid wording that implies offline availability.
- Keep screenshot captions and metadata aligned with visible labels like Random Quiz, Focus Mode, Timed Exam, Challenge Mode, Saved Tests or Continue Session, History, and Coach Note.
