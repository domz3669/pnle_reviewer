# Cloud Functions Deployment Guide

## Overview

This guide explains how to deploy the leaderboard Cloud Functions to your Firebase project.

## Prerequisites

1. **Firebase Account**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Create a new project or use existing one

2. **Firebase CLI**
   ```bash
   npm install -g firebase-tools
   ```

3. **Node.js 20+**
   - Download from [nodejs.org](https://nodejs.org)

## Step-by-Step Deployment

### 1. Configure Firebase Project

Create a `.firebaserc` file in the project root:

```bash
firebase login
firebase init
```

Or manually create `.firebaserc`:

```json
{
  "projects": {
    "default": "your-firebase-project-id"
  }
}
```

Replace `your-firebase-project-id` with your actual Firebase project ID.

### 2. Install Cloud Functions Dependencies

```bash
cd functions
npm install
npm run build
```

### 3. Deploy Functions to Firebase

```bash
cd ..
firebase deploy --only functions
```

Or deploy everything (functions + firestore rules):

```bash
firebase deploy
```

### 4. Verify Deployment

Check Firebase Console:
1. Go to **Cloud Functions**
2. You should see `generateDailyLeaderboard` function
3. Status should be "Green" (active)
4. Region should be `us-central1` or your configured region

### 5. Test the Function

#### Option A: Manual Test via Console

1. Open Firebase Console → Cloud Functions
2. Click `generateDailyLeaderboard`
3. Click "Testing" tab
4. Click "Create test event"
5. Leave default settings, click "Create and publish"
6. Watch the logs for execution output

#### Option B: First-Time Manual Trigger

```bash
firebase functions:call generateDailyLeaderboard --region us-central1
```

### 6. Monitor Logs

View real-time function logs:

```bash
firebase functions:log
```

Or in Firebase Console:
1. Cloud Functions → `generateDailyLeaderboard`
2. Logs tab

## Firestore Setup

The Cloud Function expects this Firestore structure:

### Collections Required:

```
/leaderboards/
├── today/
│   └── entries/ (auto-created by function)
├── yesterday/
│   └── entries/ (auto-created by function)
└── thisWeek/
    └── entries/ (auto-created by function)

/users/{userId}/
├── (user profile fields)
└── leaderboardData/
    └── {YYYY-MM-DD} documents (created by app)
```

### Create Initial Collections (Optional)

You can pre-create empty collections to avoid first-run delays:

1. Firebase Console → Firestore Database
2. Click "Start Collection"
3. Create: `leaderboards` → `today` → `entries`
4. Create: `leaderboards` → `yesterday` → `entries`
5. Create: `leaderboards` → `thisWeek` → `entries`

## Data Format

### User Document (`/users/{uid}`)

```json
{
  "displayName": "John Doe",
  "photoURL": "https://...",
  "completedSessions": 4,
  "email": "user@example.com"
}
```

### Daily Leaderboard Entry (`/users/{uid}/leaderboardData/{YYYY-MM-DD}`)

```json
{
  "averageScore": 87.5,
  "sessionCount": 4,
  "updatedAt": "2024-03-01T10:30:00Z"
}
```

### Leaderboard Snapshot (`/leaderboards/today/entries/{rank}`)

```json
{
  "userId": "uid123",
  "name": "John Doe",
  "photoUrl": "https://...",
  "averageScore": 87.5,
  "sessionCount": 4,
  "rank": 1
}
```

## Troubleshooting

### Function Not Triggering

**Problem:** Function isn't running at scheduled time  
**Solutions:**
- Check Cloud Scheduler in Google Cloud Console
- Verify timezone is set to UTC
- Check functions logs for errors: `firebase functions:log`

### Permission Denied Errors

**Problem:** `Permission denied on resource` errors  
**Solutions:**
1. Ensure service account has permissions:
   - Go to Google Cloud Console
   - IAM & Admin → Service Accounts
   - Find `Firebase Functions` service account
   - Ensure it has `Cloud Datastore User` and `Cloud Functions Service Agent` roles

2. Check Firestore Rules:
   - Rules must allow Cloud Functions to write to `/leaderboards/`
   - Default rules in `firestore.rules` already configured

### Data Not Appearing in Leaderboard

**Problem:** Function runs but leaderboard stays empty  
**Solutions:**
1. Check user has `completedSessions >= 4`
2. Verify leaderboard data exists in `/users/{uid}/leaderboardData/{YYYY-MM-DD}`
3. Check function logs: `firebase functions:log | grep generateDailyLeaderboard`
4. Manually trigger function and review output

### Build Errors

**Problem:** `npm run deploy` fails with TypeScript errors  
**Solutions:**
```bash
cd functions
npm install
npm run build  # Check for TypeScript errors
npm run deploy
```

## Updating Functions

### Deploy Updated Code

```bash
cd functions
npm run build
cd ..
firebase deploy --only functions
```

### Rollback to Previous Version

Firebase automatically keeps previous versions. In Firebase Console:
1. Cloud Functions → `generateDailyLeaderboard`
2. Manage → Versions
3. Select previous version
4. Click "Promote"

## Performance & Cost

### Cost Estimate

- **Invocation Cost:** $0.40 per 1M invocations
- **Daily runs:** 1 × 365 = 365/year ≈ **$0.0001/year**
- **Compute Cost:** 2-5 seconds per run ≈ **$0.002-0.005/run**
- **Total:** Typically **$5-15/month** depending on execution time

### Optimization Tips

- Function is already optimized with batch writes
- Uses indexed queries for better performance
- Stops early if < 10 eligible users

## Next Steps

1. **Deploy:** Follow the step-by-step guide above
2. **Test:** Manually trigger and verify output
3. **Monitor:** Set up log alerts in Cloud Logging
4. **Verify:** Check leaderboard appears in app after first run

## Support

If issues arise:
1. Check [Firebase Documentation](https://firebase.google.com/docs/functions)
2. Review function logs: `firebase functions:log`
3. Check Firestore rules: Firestore Database → Rules tab
4. Verify Firestore structure matches expected format
