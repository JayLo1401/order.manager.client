package at.jaycloud.order.manager.client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ServiceEnabler.ensureEnabled(context)
        val open = if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            // Selbst-Update, waehrend die Vollbild-Anzeige offen war: wieder oeffnen.
            NativePrefs.takeReopenAfterUpdate(context)
        } else {
            NativePrefs.launchOnBoot(context)
        }
        if (!open) return
        // Der Dienst darf die App starten – laeuft er schon, sofort, sonst sobald er verbunden ist.
        val service = OrderOverlayService.instance
        if (service != null) service.launchApp() else NativePrefs.setLaunchPending(context)
    }
}
