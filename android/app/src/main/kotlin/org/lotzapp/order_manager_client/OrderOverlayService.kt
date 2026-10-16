package org.lotzapp.order_manager_client

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Hintergrunddienst (wie bei home.control eine Bedienungshilfe).
 *
 * Android haelt den Dienst dauerhaft am Leben; darin laeuft eine vorgewaermte
 * Flutter-Engine (`overlayMain`), die den order.manager abfragt. Angezeigt wird als
 * Accessibility-Overlay – kein „Ueber anderen Apps anzeigen“ noetig, und die App
 * darunter (home.radio, Spotify, …) behaelt Fokus und Wiedergabe.
 *
 * Flutter entscheidet, was zu sehen ist (`setWindow`):
 * - none: kein Fenster
 * - card: kleines Fenster (Kuechenstatus + QR-Code) an der eingestellten Position,
 *         nicht beruehrbar -> blockiert nichts darunter
 * - full: Vollbild fuer „Bitte abholen“; OK/Zurueck werden hier abgefangen und schliessen
 */
class OrderOverlayService : AccessibilityService() {

    companion object {
        private const val TAG = "OrderClient"
        private const val CHANNEL = "order_manager_client/overlay"

        @Volatile
        var instance: OrderOverlayService? = null
            private set
    }

    private val windowManager by lazy { getSystemService(WINDOW_SERVICE) as WindowManager }

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var flutterView: FlutterView? = null

    /** Zuletzt angeforderte Fensterart (fuer Drehung/Aufloesungswechsel). */
    private var windowArgs: Map<String, Any?> = mapOf("mode" to "none")

    /** Tasten, deren DOWN wir verschluckt haben – das passende UP wird ebenfalls verschluckt. */
    private val swallowedDown = mutableSetOf<Int>()

    private val isFull: Boolean get() = flutterView != null && windowArgs["mode"] == "full"

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        startEngine()
        Log.i(TAG, "Dienst verbunden")
        if (NativePrefs.takeLaunchPending(this)) launchApp()
    }

    private fun startEngine() {
        if (engine != null) return
        val e = FlutterEngine(this)
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "overlayMain"
            )
        )
        val ch = MethodChannel(e.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "setWindow" -> {
                    @Suppress("UNCHECKED_CAST")
                    setWindow((call.arguments as? Map<String, Any?>) ?: emptyMap())
                    result.success(null)
                }
                "playChime" -> {
                    Chime.play(this, volume = (call.argument<Double>("volume") ?: 1.0).toFloat())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Die Engine laeuft dauerhaft (Abfragen, Timer), auch ohne sichtbares Fenster.
        e.lifecycleChannel.appIsResumed()
        engine = e
        channel = ch
    }

    // ------------------------------------------------------------------ Fenster

    private fun setWindow(args: Map<String, Any?>) {
        windowArgs = args
        when (args["mode"]) {
            "card" -> showWindow(cardParams(args))
            "full" -> showWindow(fullParams())
            else -> removeWindow()
        }
    }

    private fun baseFlags(touchable: Boolean): Int {
        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        if (!touchable) flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        return flags
    }

    private fun fullParams() = WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        baseFlags(touchable = true),
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.TOP or Gravity.START }

    /** Kleines Fenster: Breite relativ zur Bildschirmbreite, Hoehe ueber das Seitenverhaeltnis. */
    private fun cardParams(args: Map<String, Any?>): WindowManager.LayoutParams {
        val (screenW, screenH) = screenSize()
        val widthFraction = (args["widthFraction"] as? Number)?.toDouble() ?: 0.3
        val aspect = (args["aspect"] as? Number)?.toDouble() ?: 0.62
        val marginFraction = (args["marginFraction"] as? Number)?.toDouble() ?: 0.02
        val margin = (screenW * marginFraction).toInt()
        val w = (screenW * widthFraction).toInt().coerceIn(80, screenW - 2 * margin)
        val h = (w * aspect).toInt().coerceIn(60, screenH - 2 * margin)
        val position = args["position"] as? String ?: "bottomRight"
        val vertical = when {
            position.startsWith("top") -> Gravity.TOP
            position.startsWith("bottom") -> Gravity.BOTTOM
            else -> Gravity.CENTER_VERTICAL
        }
        val horizontal = when {
            position.endsWith("Left") -> Gravity.LEFT
            position.endsWith("Right") -> Gravity.RIGHT
            else -> Gravity.CENTER_HORIZONTAL
        }
        return WindowManager.LayoutParams(
            w, h,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            baseFlags(touchable = false),
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = vertical or horizontal
            x = if (horizontal == Gravity.CENTER_HORIZONTAL) 0 else margin
            y = if (vertical == Gravity.CENTER_VERTICAL) 0 else margin
        }
    }

    @Suppress("DEPRECATION")
    private fun screenSize(): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = windowManager.maximumWindowMetrics.bounds
            return b.width() to b.height()
        }
        val m = android.util.DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(m)
        return m.widthPixels to m.heightPixels
    }

    private fun showWindow(params: WindowManager.LayoutParams) {
        startEngine()
        val e = engine ?: return
        val existing = flutterView
        if (existing != null) {
            try {
                windowManager.updateViewLayout(existing, params)
            } catch (t: Throwable) {
                Log.w(TAG, "updateViewLayout", t)
            }
            return
        }
        val view = FlutterView(this, FlutterTextureView(this))
        try {
            windowManager.addView(view, params)
        } catch (t: Throwable) {
            Log.e(TAG, "Einblendung konnte nicht angezeigt werden", t)
            return
        }
        view.attachToFlutterEngine(e)
        flutterView = view
    }

    private fun removeWindow() {
        val view = flutterView ?: return
        flutterView = null
        swallowedDown.clear()
        view.detachFromFlutterEngine()
        try {
            windowManager.removeView(view)
        } catch (t: Throwable) {
            Log.w(TAG, "removeView", t)
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Drehung/Aufloesung: Kartengroesse neu berechnen.
        if (flutterView != null) setWindow(windowArgs)
    }

    // ------------------------------------------------------------------ Tasten

    /** Nur waehrend „Bitte abholen“: OK/Zurueck schliessen die Meldung, alles andere geht durch. */
    override fun onKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        val down = event.action == KeyEvent.ACTION_DOWN
        if (!down && swallowedDown.remove(code)) return true
        if (!isFull || !isCloseKey(code)) return false
        if (down) {
            swallowedDown.add(code)
            if (event.repeatCount == 0) channel?.invokeMethod("dismiss", null)
        }
        return true
    }

    private fun isCloseKey(code: Int) = when (code) {
        KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BUTTON_A -> true
        else -> false
    }

    // ------------------------------------------------------------------ Aufrufe aus der App

    /** Einstellungen wurden in der App geaendert. */
    fun reloadConfig() {
        channel?.invokeMethod("reload", null)
    }

    /** Einblendung kurz zur Probe zeigen. */
    fun preview() {
        channel?.invokeMethod("preview", null)
    }

    /** „Bitte abholen“ mit Beispieldaten. */
    fun testPickup() {
        channel?.invokeMethod("testPickup", null)
    }

    /**
     * App in den Vordergrund holen (Autostart nach dem Booten im Modus „App-Anzeige“).
     * Eine aktive Bedienungshilfe darf Activities aus dem Hintergrund starten.
     */
    fun launchApp() {
        try {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            )
        } catch (t: Throwable) {
            Log.w(TAG, "App konnte nicht gestartet werden", t)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        removeWindow()
        engine?.destroy()
        engine = null
        channel = null
        instance = null
        super.onDestroy()
    }
}
