package org.lotzapp.order_manager_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ServiceEnabler.ensureEnabled(context)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED || !NativePrefs.launchOnBoot(context)) return
        // Der Dienst darf die App starten – laeuft er schon, sofort, sonst sobald er verbunden ist.
        val service = OrderOverlayService.instance
        if (service != null) service.launchApp() else NativePrefs.setLaunchPending(context)
    }
}
