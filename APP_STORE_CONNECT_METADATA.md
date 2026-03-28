# ACET Reviewer 2027 - App Store Connect Metadata

## App Name
ACET Reviewer 2027

## Subtitle
Practice, analytics, AI coach

## Promotional Text
Prepare for ACET with native quiz modes, targeted practice, score breakdowns, saved sessions, and optional AI-generated Coach Note explanations after answering.

## Keywords
acet,reviewer,exam,quiz,practice,college,entrance,test,math,reasoning,reading,language

## Category
Education

## Description
ACET Reviewer 2027 is a native mobile review app built for students preparing for ACET.

The app focuses on fast, repeatable practice sessions with local question sets, post-quiz score breakdowns, progress history, saved sessions, and optional AI-assisted review guidance.

What you can do:
- Start Random Quiz sessions for mixed ACET practice
- Use Focus Mode for targeted review by subject area
- Train with Timed Exam mode for faster decision-making
- Use Challenge Mode for advanced mixed practice when online generation is available
- Review results with subtest breakdowns and session insights
- Track recent performance history inside the app
- Save sessions and continue them later
- Request optional AI-generated Coach Note explanations after answering
- Claim optional daily session rewards and ad-based session refills

Network behavior:
- The app launches to a native home screen even without internet
- Random Quiz, Focus Mode, and Timed Exam can start from local seeded question sets
- Internet is required for syncing, rewards, ads, Challenge Mode generation, report submission, and online AI Coach Note generation

AI disclosure:
Coach Note is an optional feature that generates review guidance after a question is answered. It is user-invoked from inside a quiz and may require internet access unless a saved explanation is already available locally.

## App Review Notes
ACET Reviewer 2027 is a native Flutter quiz app for ACET preparation. It is not a webview or browser wrapper.

This build launches to the native home screen even when the device starts offline. Random Quiz, Focus Mode, and Timed Exam can start from local seeded question sets without internet. Internet access is only required for progress syncing, streak rewards, ads, Challenge Mode generation, report submission, and optional AI-generated Coach Note explanations requested during a quiz.

Visible features in this build:
- Random Quiz
- Focus Mode
- Timed Exam
- Challenge Mode
- Saved Sessions
- History
- Results Analytics
- Coach Note explanations
- Daily rewards and session refill tasks

No subscriptions or hidden post-review features are included in this build.

Reviewer path:
1. Launch the app.
2. Complete onboarding by entering a nickname.
3. On the Quiz screen, start Random Quiz, Focus Mode, or Timed Exam immediately.
4. Start Challenge Mode while online.
5. Answer questions to open the native results screen.
6. Use Coach Note after answering a question to request an optional explanation.
7. Open History and Saved Sessions from the main app flow.

Coach Note disclosure:
Coach Note is an optional AI-generated explanation feature requested by the user after answering a question. It is not required to use the core quiz modes.

## Screenshot Captions
1. Practice with native ACET study modes built for daily review.
2. Answer timed multiple-choice questions in a focused test flow.
3. Review scores, subtest breakdowns, and session insights after every run.
4. Track recent performance with native in-app progress history.
5. Save sessions and continue unfinished tests later.
6. Request optional AI Coach Note explanations after answering.

## Submission Guardrails
- Do not mention features that are planned, hidden, or conditionally unavailable in the submitted build.
- Do not imply that Challenge Mode or Coach Note works offline.
- Keep screenshots aligned with visible UI labels in the current build.
- If only five screenshots are used, drop Challenge Mode before dropping the core native quiz flow.