package org.lotzapp.order_manager_client

import android.content.Context

/**
 * Einstellungen, die die native Seite ohne Flutter braucht.
 *
 * Die App-Einstellungen selbst liegen in den SharedPreferences des Flutter-Plugins
 * ("FlutterSharedPreferences", Schluessel mit Praefix "flutter.").
 */
object NativePrefs {
    private const val FLUTTER_FILE = "FlutterSharedPreferences"
    private const val NATIVE_FILE = "order_manager_client_native"
    private const val KEY_LAUNCH_PENDING = "launch_pending"

    private fun flutter(context: Context) = context.getSharedPreferences(FLUTTER_FILE, Context.MODE_PRIVATE)

    /** Nach dem Booten die App oeffnen? (Modus „App-Anzeige“ + Schalter in den Einstellungen) */
    fun launchOnBoot(context: Context): Boolean {
        val p = flutter(context)
        return p.getBoolean("flutter.launch_on_boot", false) &&
            (p.getString("flutter.display_mode", "app") ?: "app") == "app"
    }

    /** Merkt sich den Start, bis der Dienst verbunden ist. */
    fun setLaunchPending(context: Context) {
        context.getSharedPreferences(NATIVE_FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY_LAUNCH_PENDING, true).apply()
    }

    fun takeLaunchPending(context: Context): Boolean {
        val p = context.getSharedPreferences(NATIVE_FILE, Context.MODE_PRIVATE)
        val pending = p.getBoolean(KEY_LAUNCH_PENDING, false)
        if (pending) p.edit().putBoolean(KEY_LAUNCH_PENDING, false).apply()
        return pending
    }
}
