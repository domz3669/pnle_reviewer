import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

// Initialize Firebase Admin SDK
admin.initializeApp();

const db = admin.firestore();

interface LeaderboardEntry {
  userId: string;
  name: string;
  photoUrl: string | null;
  averageScore: number;
  sessionCount: number;
  rank: number;
}

interface UserDailyData {
  userId: string;
  name: string;
  photoUrl: string | null;
  sessionCount: number;
  averageScore: number;
}

/**
 * Scheduled function that runs daily at midnight UTC (00:00 UTC)
 * Creates leaderboard snapshots for today, yesterday, and this week
 */
export const generateDailyLeaderboard = functions.pubsub
  .schedule("0 0 * * *") // Daily at midnight UTC
  .timeZone("UTC")
  .onRun(async (context) => {
    try {
      functions.logger.info("Starting daily leaderboard snapshot generation...");

      const now = new Date();
      const todayKey = formatDate(now);
      const yesterdayKey = formatDate(new Date(now.getTime() - 24 * 60 * 60 * 1000));

      // Step 1: Archive today's leaderboard to yesterday
      await archiveYesterdayLeaderboard();

      // Step 2: Generate new today's leaderboard
      await generateTodayLeaderboard(todayKey);

      // Step 3: Generate this week's aggregated leaderboard
      await generateWeekLeaderboard();

      functions.logger.info("Daily leaderboard snapshot generation completed successfully");
      return null;
    } catch (error) {
      functions.logger.error("Error generating daily leaderboard:", error);
      throw error;
    }
  });

/**
 * Archive today's leaderboard entries to yesterday
 */
async function archiveYesterdayLeaderboard(): Promise<void> {
  try {
    // Get all current today entries
    const todaySnapshot = await db
      .collection("leaderboards")
      .doc("today")
      .collection("entries")
      .orderBy("rank")
      .get();

    // If no entries exist, skip archiving
    if (todaySnapshot.empty) {
      functions.logger.info("No today entries to archive");
      return;
    }

    // Delete yesterday's entries first
    const yesterdaySnapshot = await db
      .collection("leaderboards")
      .doc("yesterday")
      .collection("entries")
      .get();

    const batch = db.batch();

    yesterdaySnapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    // Copy today's entries to yesterday
    todaySnapshot.docs.forEach((doc) => {
      const yesterdayRef = db
        .collection("leaderboards")
        .doc("yesterday")
        .collection("entries")
        .doc(doc.id);
      batch.set(yesterdayRef, doc.data());
    });

    await batch.commit();
    functions.logger.info(`Archived ${todaySnapshot.size} entries to yesterday`);
  } catch (error) {
    functions.logger.error("Error archiving yesterday leaderboard:", error);
    throw error;
  }
}

/**
 * Generate today's leaderboard from user daily scores
 */
async function generateTodayLeaderboard(dateKey: string): Promise<void> {
  try {
    // Query all users with their today's session data
    const usersSnapshot = await db.collection("users").get();

    const leaderboardCandidates: UserDailyData[] = [];

    // Process each user
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;

      // Get session count from user profile
      const sessionCount = userData.completedSessions || 0;

      // Only include users with 4+ sessions
      if (sessionCount < 4) {
        continue;
      }

      // Get today's leaderboard data if it exists
      const leaderboardDataRef = db
        .collection("users")
        .doc(userId)
        .collection("leaderboardData")
        .doc(dateKey);

      const leaderboardDataDoc = await leaderboardDataRef.get();

      if (leaderboardDataDoc.exists) {
        const data = leaderboardDataDoc.data();
        leaderboardCandidates.push({
          userId,
          name: userData.displayName || "Anonymous",
          photoUrl: userData.photoURL || null,
          sessionCount,
          averageScore: (data && data.averageScore) || 0,
        });
      }
    }

    // Sort by average score descending
    leaderboardCandidates.sort((a, b) => b.averageScore - a.averageScore);

    // Create batch write for top 10
    const batch = db.batch();

    // Delete existing today entries
    const existingEntries = await db
      .collection("leaderboards")
      .doc("today")
      .collection("entries")
      .get();

    existingEntries.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    // Write top 10 entries
    for (let rank = 0; rank < Math.min(10, leaderboardCandidates.length); rank++) {
      const candidate = leaderboardCandidates[rank];
      const entryRef = db
        .collection("leaderboards")
        .doc("today")
        .collection("entries")
        .doc((rank + 1).toString());

      const entry: LeaderboardEntry = {
        userId: candidate.userId,
        name: candidate.name,
        photoUrl: candidate.photoUrl,
        averageScore: candidate.averageScore,
        sessionCount: candidate.sessionCount,
        rank: rank + 1,
      };

      batch.set(entryRef, entry);
    }

    await batch.commit();
    functions.logger.info(
      `Generated today's leaderboard with ${Math.min(10, leaderboardCandidates.length)} entries`
    );
  } catch (error) {
    functions.logger.error("Error generating today leaderboard:", error);
    throw error;
  }
}

/**
 * Generate this week's aggregated leaderboard
 */
async function generateWeekLeaderboard(): Promise<void> {
  try {
    const now = new Date();
    const dayOfWeek = now.getUTCDay(); // 0 = Sunday
    const daysBack = dayOfWeek === 0 ? 6 : dayOfWeek - 1; // Monday = 0

    const weekStart = new Date(now.getTime() - daysBack * 24 * 60 * 60 * 1000);
    weekStart.setUTCHours(0, 0, 0, 0);

    const usersSnapshot = await db.collection("users").get();
    const leaderboardCandidates: Map<string, UserDailyData> = new Map();

    // Aggregate scores for each user across the week
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      const sessionCount = userData.completedSessions || 0;

      // Only include users with 4+ sessions
      if (sessionCount < 4) {
        continue;
      }

      let totalScore = 0;
      let scoreCount = 0;

      // Get all leaderboard data for this week
      const leaderboardDataRef = db
        .collection("users")
        .doc(userId)
        .collection("leaderboardData");

      const leaderboardSnapshot = await leaderboardDataRef.get();

      for (const doc of leaderboardSnapshot.docs) {
        const entryDate = new Date(doc.id);
        if (entryDate >= weekStart && entryDate <= now) {
          totalScore += doc.data().averageScore || 0;
          scoreCount++;
        }
      }

      if (scoreCount > 0) {
        const averageScore = totalScore / scoreCount;
        leaderboardCandidates.set(userId, {
          userId,
          name: userData.displayName || "Anonymous",
          photoUrl: userData.photoURL || null,
          sessionCount,
          averageScore,
        });
      }
    }

    // Sort by average score descending
    const sortedCandidates = Array.from(leaderboardCandidates.values()).sort(
      (a, b) => b.averageScore - a.averageScore
    );

    // Create batch write for top 10
    const batch = db.batch();

    // Delete existing week entries
    const existingEntries = await db
      .collection("leaderboards")
      .doc("thisWeek")
      .collection("entries")
      .get();

    existingEntries.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    // Write top 10 entries
    for (let rank = 0; rank < Math.min(10, sortedCandidates.length); rank++) {
      const candidate = sortedCandidates[rank];
      const entryRef = db
        .collection("leaderboards")
        .doc("thisWeek")
        .collection("entries")
        .doc((rank + 1).toString());

      const entry: LeaderboardEntry = {
        userId: candidate.userId,
        name: candidate.name,
        photoUrl: candidate.photoUrl,
        averageScore: candidate.averageScore,
        sessionCount: candidate.sessionCount,
        rank: rank + 1,
      };

      batch.set(entryRef, entry);
    }

    await batch.commit();
    functions.logger.info(
      `Generated this week's leaderboard with ${Math.min(10, sortedCandidates.length)} entries`
    );
  } catch (error) {
    functions.logger.error("Error generating week leaderboard:", error);
    throw error;
  }
}

/**
 * Format date to YYYY-MM-DD string
 */
function formatDate(date: Date): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}
