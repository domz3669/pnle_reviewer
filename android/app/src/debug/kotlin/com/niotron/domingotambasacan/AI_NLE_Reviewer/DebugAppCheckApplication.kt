package com.niotron.domingotambasacan.AI_NLE_Reviewer

import android.app.Application
import android.content.Context

/**
 * Debug-only Application subclass that injects a fixed App Check debug token
 * into SharedPreferences BEFORE Firebase initializes. This prevents the debug
 * token from rotating on every app reinstall.
 *
 * Firebase's DebugAppCheckProvider reads from a SharedPreferences file whose
 * name includes the Base64-encoded Firebase app name + app ID suffix.
 *
 * Register the pinned token in Firebase Console → App Check → Manage debug tokens.
 */
class DebugAppCheckApplication : Application() {

    companion object {
        private const val PINNED_TOKEN = "fa4a4a26-c35c-4f3f-ba26-8897e02a61b0"
        private const val TOKEN_KEY = "com.google.firebase.appcheck.debug.DEBUG_SECRET"
        private const val PREFS_BASE = "com.google.firebase.appcheck.debug.store"
        // Base64([DEFAULT]) + Firebase App ID for pnle-reviewer-ios Android app
        private const val PREFS_SUFFIX = ".W0RFRkFVTFRd+MToxNDQxNDk2MjQ1ODc6YW5kcm9pZDpkNzdjZmVkMzQzNzQxZjFhMjZkNDBl"
    }

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        // Write to BOTH the plain and the suffixed SharedPreferences files
        // so the token is picked up regardless of Firebase SDK version.
        for (name in listOf(PREFS_BASE, PREFS_BASE + PREFS_SUFFIX)) {
            base.getSharedPreferences(name, Context.MODE_PRIVATE)
                .edit()
                .putString(TOKEN_KEY, PINNED_TOKEN)
                .apply()
        }
    }
}
