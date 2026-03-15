# CSE Reviewer Cloud Functions

Cloud Functions for the CSE Reviewer app, including daily leaderboard snapshot generation.

## Setup

### Prerequisites
- Node.js 20+
- Firebase CLI (`npm install -g firebase-tools`)
- Google Cloud project with Firestore enabled

### Installation

```bash
cd functions
npm install
```

### Build

```bash
npm run build
```

### Local Testing (Emulators)

```bash
npm run serve
```

This will start the Firebase emulators for functions and Firestore. You can test locally before deploying.

## Deployment

### Deploy to Firebase

```bash
npm run deploy
```

Or from the project root:

```bash
firebase deploy --only functions
```

### View Logs

```bash
npm run logs
```

Or using Firebase CLI:

```bash
firebase functions:log
```

## Functions

### `generateDailyLeaderboard`

**Trigger:** Cloud Pub/Sub (Scheduled)  
**Schedule:** Daily at 00:00 UTC (midnight)

**What it does:**

1. **Archives Yesterday's Snapshot**
   - Moves current `/leaderboards/today/entries` → `/leaderboards/yesterday/entries`

2. **Generates Today's Snapshot**
   - Queries all users with `completedSessions >= 4`
   - Gets each user's daily average score from `/users/{uid}/leaderboardData/{YYYY-MM-DD}`
   - Ranks users by average score (highest first)
   - Saves top 10 entries to `/leaderboards/today/entries/{rank}`

3. **Generates This Week's Snapshot**
   - Aggregates user scores from Monday 00:00 UTC to now
   - Ranks users by weekly average score
   - Saves top 10 entries to `/leaderboards/thisWeek/entries/{rank}`

## Firestore Structure

```
/leaderboards/
├── today/
│   └── entries/
│       ├── 1 → { userId, name, photoUrl, averageScore, sessionCount, rank }
│       ├── 2 → { ... }
│       └── ... (up to 10)
├── yesterday/
│   └── entries/
│       └── { ... same structure ... }
└── thisWeek/
    └── entries/
        └── { ... same structure ... }

/users/{userId}/
├── displayName
├── photoURL
├── completedSessions
└── leaderboardData/
    ├── 2024-03-01 → { averageScore, sessionCount, updatedAt }
    ├── 2024-03-02 → { ... }
    └── ... (daily entries)
```

## Data Requirements

For a user to appear in the leaderboard:
- **Minimum Sessions:** 4 completed sessions required
- **Daily Score:** Must have a leaderboard entry for the current date
- **Session Count:** Must match the user's `completedSessions` field

## Time Zone Notes

- Function runs at **00:00 UTC** (midnight UTC)
- All dates stored in `YYYY-MM-DD` UTC format
- Week spans Monday 00:00 UTC to current time

## Error Handling

- Function logs are available in Firebase Console → Cloud Functions
- Errors do not prevent partial success (e.g., if one user's data is corrupted, others still process)
- All operations use Firestore batch writes for atomicity

## Testing

### Manual Test via Firebase Console

1. Go to Cloud Functions in Firebase Console
2. Click the `generateDailyLeaderboard` function
3. Click "Testing" tab
4. Click "Create test event"
5. Select "Cloud Pub/Sub"
6. Leave message empty or add `{}`
7. Click "Create and publish"

### Local Emulator Test

Use the emulator UI at `http://localhost:4000` to trigger the function manually.

## Performance Notes

- **Execution Time:** ~2-5 seconds for typical user base
- **Scalability:** Optimized with batch writes and indexed queries
- **Cost:** Minimal - uses scheduled Pub/Sub trigger (free tier eligible)

## Future Enhancements

- [ ] Add time-zone aware scheduling (let users configure)
- [ ] Implement leaderboard reset logic for monthly/yearly rankings
- [ ] Add performance metrics and analytics
- [ ] Support for regional leaderboards (by state/region)
