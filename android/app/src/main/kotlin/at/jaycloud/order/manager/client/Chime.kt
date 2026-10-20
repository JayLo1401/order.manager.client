package at.jaycloud.order.manager.client

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.util.Log
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.sin

/**
 * Gong fuer „Bitte abholen“: die klassische Servierglocke am Pass („ding! ding!“),
 * synthetisiert wie bisher im home.radio.
 *
 * Fordert kurzzeitigen Audio-Fokus „mit Ducking“ an (wie die Tuerglocke von home.control):
 * laufende Wiedergabe (home.radio, Spotify, …) wird vom System kurz leiser gestellt statt
 * gestoppt und danach wieder lauter.
 */
object Chime {
    private const val TAG = "OrderClient"
    private const val SAMPLE_RATE = 44100

    @Volatile
    private var playing = false

    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        // SONIFICATION (nicht SPEECH), sonst duckt Android nicht automatisch.
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    // Einmal beim ersten Gebrauch erzeugt.
    private val bellPcm: ShortArray by lazy { synthesizeBell() }

    /** @param volume 0..1 relativ zur Medienlautstaerke. Laeuft der Gong schon, passiert nichts. */
    fun play(context: Context, volume: Float = 1f) {
        if (playing) return
        playing = true
        val am = context.applicationContext.getSystemService(AudioManager::class.java)
        Thread({
            var focus: AudioFocusRequest? = null
            try {
                focus = requestFocus(am)
                playPcm(volume.coerceIn(0f, 1f))
            } catch (t: Throwable) {
                Log.w(TAG, "Gong konnte nicht abgespielt werden", t)
            } finally {
                abandonFocus(am, focus)
                playing = false
            }
        }, "Chime").start()
    }

    private fun playPcm(volume: Float) {
        val pcm = bellPcm
        val track = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(pcm.size * 2)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        try {
            track.write(pcm, 0, pcm.size)
            track.setVolume(volume)
            // Kurz warten, bis das Ducking der anderen App gegriffen hat.
            Thread.sleep(150)
            track.play()
            Thread.sleep(pcm.size * 1000L / SAMPLE_RATE + 100)
        } finally {
            try {
                track.stop()
            } catch (_: Exception) {
            }
            track.release()
        }
    }

    private fun requestFocus(am: AudioManager): AudioFocusRequest? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes)
                .setWillPauseWhenDucked(false)
                .build()
            am.requestAudioFocus(req)
            return req
        }
        @Suppress("DEPRECATION")
        am.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        return null
    }

    private fun abandonFocus(am: AudioManager, req: AudioFocusRequest?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (req != null) am.abandonAudioFocusRequest(req)
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
    }

    /**
     * Zwei schnelle Schlaege auf eine kleine, helle Metallglocke. Jeder Schlag ist eine
     * Summe unharmonischer Teiltoene (das macht den Metallklang aus, statt eines Pieptons),
     * jeder mit eigener Abklingzeit; der Grundton ist leicht verstimmt doppelt (Schwebung)
     * und dazu kommt ein kurzer hoher Klick des Hammers.
     */
    private fun synthesizeBell(): ShortArray {
        val strikeOffsetsSec = doubleArrayOf(0.0, 0.32)
        val ringSec = 2.2
        val totalSamples = ((strikeOffsetsSec.last() + ringSec) * SAMPLE_RATE).toInt()
        val mix = DoubleArray(totalSamples)

        val fundamental = 1760.0 // Hz – heller Grundton einer Servierglocke
        // (Frequenzverhaeltnis, relative Amplitude, Abklingzeit in s)
        val partials = arrayOf(
            doubleArrayOf(1.000, 1.00, 0.90),
            doubleArrayOf(1.0018, 0.70, 0.95), // verstimmter Zwilling -> ~3 Hz Schwebung
            doubleArrayOf(2.72, 0.40, 0.45),
            doubleArrayOf(2.7235, 0.25, 0.50),
            doubleArrayOf(5.18, 0.18, 0.20),
            doubleArrayOf(8.30, 0.10, 0.08),
            doubleArrayOf(0.53, 0.12, 0.60), // leise tiefe Koerperresonanz
        )

        for ((strikeIndex, offset) in strikeOffsetsSec.withIndex()) {
            val start = (offset * SAMPLE_RATE).toInt()
            // Zweiter Schlag etwas leiser, wie mit der Hand zweimal geschlagen.
            val strikeGain = if (strikeIndex == 0) 1.0 else 0.85
            for (n in 0 until (ringSec * SAMPLE_RATE).toInt()) {
                val idx = start + n
                if (idx >= totalSamples) break
                val t = n.toDouble() / SAMPLE_RATE
                val attack = if (t < 0.001) t / 0.001 else 1.0
                var s = 0.0
                for (p in partials) {
                    s += p[1] * exp(-t / p[2]) * sin(2 * PI * fundamental * p[0] * t)
                }
                s += 0.25 * exp(-t / 0.004) * sin(2 * PI * 6300.0 * t)
                mix[idx] += s * attack * strikeGain
            }
        }

        val peak = mix.maxOf { abs(it) }.takeIf { it > 0 } ?: 1.0
        val gain = 0.9 * Short.MAX_VALUE / peak
        return ShortArray(totalSamples) { (mix[it] * gain).toInt().toShort() }
    }
}
