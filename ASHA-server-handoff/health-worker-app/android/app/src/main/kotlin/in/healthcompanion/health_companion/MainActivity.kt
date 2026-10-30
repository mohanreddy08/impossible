package `in`.healthcompanion.health_companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

private const val REQ_MIC = 4711

class MainActivity : FlutterActivity() {
    private val asr = WhisperAsr()
    private val worker = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private val releaseModel = Runnable { if (!asr.isRecording) asr.release() }
    private var pendingMic: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "asha/speech").setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> speechCapabilities(result)
                // the phone's own keyboard settings, for the "Telugu voice with the Google keyboard" help screen
                "openKeyboardSettings" -> result.success(
                    try {
                        startActivity(Intent(android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        true
                    } catch (e: Exception) {
                        false
                    }
                )
                else -> result.notImplemented()
            }
        }
        // Offline Telugu recognition with the app's own model (see WhisperAsr). Audio never leaves the phone.
        MethodChannel(messenger, "asha/te_asr").setMethodCallHandler { call, result ->
            val dir = call.argument<String>("dir") ?: ""
            when (call.method) {
                "installed" -> result.success(asr.installed(dir))
                "start" -> startListening(result)
                "stop" -> worker.execute {
                    try {
                        val text = asr.stopAndRecognise(dir)
                        ui.post { result.success(text) }
                    } catch (e: Throwable) {
                        ui.post { result.error("asr_failed", e.javaClass.simpleName, null) }
                    }
                    ui.removeCallbacks(releaseModel)
                    ui.postDelayed(releaseModel, WhisperAsr.IDLE_RELEASE_MS)
                }
                "cancel" -> {
                    asr.cancel()
                    result.success(null)
                }
                // the Voice Test (and adb tests) recognise a recorded 16 kHz WAV without speaking
                "recogniseWav" -> {
                    val wav = call.argument<String>("wav") ?: ""
                    worker.execute {
                        try {
                            val t0 = System.currentTimeMillis()
                            val text = asr.recogniseWav(dir, wav)
                            val ms = System.currentTimeMillis() - t0
                            ui.post { result.success(mapOf("text" to text, "ms" to ms)) }
                        } catch (e: Throwable) {
                            ui.post { result.error("asr_failed", e.javaClass.simpleName + ":" + e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Test hook, present only when the app is a debuggable build: lets a phone be tested with a recorded WAV instead of a live voice.
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            val rx = object : BroadcastReceiver() {
                override fun onReceive(c: Context, i: Intent) {
                    val wav = i.getStringExtra("wav") ?: return
                    val d = i.getStringExtra("dir") ?: return
                    worker.execute {
                        val t0 = System.currentTimeMillis()
                        val ids = try { asr.recogniseWav(d, wav) } catch (e: Throwable) { "ERROR " + e }
                        val line = "wav=" + File(wav).name + " ms=" + (System.currentTimeMillis() - t0) + " ids=" + ids + "\n"
                        android.util.Log.e("ASHA_ASR", line)
                        File(filesDir, "asr_test_out.txt").appendText(line)
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(rx, IntentFilter("in.healthcompanion.TEST_ASR"), Context.RECEIVER_EXPORTED)
            else registerReceiver(rx, IntentFilter("in.healthcompanion.TEST_ASR"))
        }
    }

    private fun startListening(result: MethodChannel.Result) {
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingMic?.success("permission")
            pendingMic = result
            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQ_MIC)
            return
        }
        result.success(if (asr.start()) "ok" else "mic_unavailable")
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_MIC) return
        val r = pendingMic ?: return
        pendingMic = null
        // the worker taps the mic again after allowing it: nothing records until then
        r.success(if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) "granted" else "permission")
    }

    override fun onDestroy() {
        asr.cancel()
        asr.release()
        super.onDestroy()
    }

    /**
     * What the phone can really do for speech, asked from the OS instead of assumed:
     *  - onDeviceAvailable: an on-device recogniser exists (Android 12+). Only then can recognition be guaranteed not to leave the phone.
     *  - installed: languages whose offline model is downloaded (Android 13+). Null when the OS cannot say.
     * Nothing is recorded here; no audio is captured.
     */
    private fun speechCapabilities(result: MethodChannel.Result) {
        val ctx = applicationContext
        val main = Handler(Looper.getMainLooper())
        val out = HashMap<String, Any?>()
        out["sdk"] = Build.VERSION.SDK_INT
        out["recognitionAvailable"] = SpeechRecognizer.isRecognitionAvailable(ctx)
        val onDevice = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && SpeechRecognizer.isOnDeviceRecognitionAvailable(ctx)
        out["onDeviceAvailable"] = onDevice
        out["micPermission"] = ctx.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || !onDevice) {
            result.success(out)
            return
        }
        var answered = false
        fun finish() {
            if (!answered) {
                answered = true
                result.success(out)
            }
        }
        main.post {
            try {
                val rec = SpeechRecognizer.createOnDeviceSpeechRecognizer(ctx)
                rec.checkRecognitionSupport(
                    Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH),
                    Executors.newSingleThreadExecutor(),
                    object : RecognitionSupportCallback {
                        override fun onSupportResult(s: RecognitionSupport) {
                            main.post {
                                out["installed"] = ArrayList(s.installedOnDeviceLanguages)
                                out["supportedOnDevice"] = ArrayList(s.supportedOnDeviceLanguages)
                                out["pending"] = ArrayList(s.pendingOnDeviceLanguages)
                                rec.destroy()
                                finish()
                            }
                        }

                        override fun onError(error: Int) {
                            main.post {
                                out["probeError"] = error
                                rec.destroy()
                                finish()
                            }
                        }
                    })
            } catch (e: Exception) {
                out["probeError"] = -1
                finish()
            }
        }
        main.postDelayed({
            out["probeTimeout"] = true
            finish()
        }, 3000)
    }
}
