package `in`.healthcompanion.health_companion

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.LongBuffer
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Offline Telugu speech recognition, entirely on the phone. No network, nothing is uploaded, and the audio is kept only in memory
 * until the text is produced (it is never written to storage).
 *
 *   microphone (16 kHz mono) -> 80-band log-mel spectrogram, padded to 30 s (Whisper's front end, computed here)
 *   -> encoder.int8.onnx -> decoder.int8.onnx run token by token with a key/value cache (greedy) -> tokens.txt -> UTF-8 text
 *
 * Model: Whisper-tiny fine-tuned for Telugu (vasista22/whisper-telugu-tiny), sherpa-onnx int8 export from ippocode/indic-asr-onnx,
 * Apache-2.0; its 80 MB full-precision token-embedding table is stored as int8 (per-row scales) to bring the pack to about 44 MB.
 * The model files are downloaded once from the project's own server by the app (see TeluguModelStore in Dart) into [dir].
 * Every step mirrors tool/whisper_reference.py, which is how the phone's output is checked against a known-good decode.
 */
class WhisperAsr {
    companion object {
        const val RATE = 16000
        const val MAX_SECONDS = 30
        val FILES = listOf("encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt")
        // the model (about 100 MB of memory while loaded) is freed this long after the last recognition; it loads again in a few seconds
        const val IDLE_RELEASE_MS = 20_000L

        private const val N_FFT = 400
        private const val HOP = 160
        private const val N_MELS = 80
        private const val N_FREQ = N_FFT / 2 + 1
        private const val N_FRAMES = 3000
        private const val N_SAMPLES = RATE * MAX_SECONDS
        private const val MAX_TOKENS = 200

        private val window = FloatArray(N_FFT) { (0.5 - 0.5 * cos(2.0 * PI * it / N_FFT)).toFloat() }
        private val cosT: FloatArray by lazy { FloatArray(N_FREQ * N_FFT) { cos(2.0 * PI * (it / N_FFT) * (it % N_FFT) / N_FFT).toFloat() } }
        private val sinT: FloatArray by lazy { FloatArray(N_FREQ * N_FFT) { sin(2.0 * PI * (it / N_FFT) * (it % N_FFT) / N_FFT).toFloat() } }
        private val filters: FloatArray by lazy { melFilters() }

        private fun hzToMel(f: Double) = if (f >= 1000.0) 15.0 + ln(f / 1000.0) / (ln(6.4) / 27.0) else f / (200.0 / 3)
        private fun melToHz(m: Double) = if (m >= 15.0) 1000.0 * exp((ln(6.4) / 27.0) * (m - 15.0)) else m * (200.0 / 3)

        /** The Slaney-scale, Slaney-normalised triangular mel filter bank Whisper uses (80 x 201). */
        private fun melFilters(): FloatArray {
            val fft = DoubleArray(N_FREQ) { it * (RATE / 2.0) / (N_FREQ - 1) }
            val lo = hzToMel(0.0)
            val hi = hzToMel(RATE / 2.0)
            val hz = DoubleArray(N_MELS + 2) { melToHz(lo + (hi - lo) * it / (N_MELS + 1)) }
            val out = FloatArray(N_MELS * N_FREQ)
            for (i in 0 until N_MELS) {
                val fa = hz[i + 1] - hz[i]
                val fb = hz[i + 2] - hz[i + 1]
                val enorm = 2.0 / (hz[i + 2] - hz[i])
                for (k in 0 until N_FREQ) {
                    val lower = -(hz[i] - fft[k]) / fa
                    val upper = (hz[i + 2] - fft[k]) / fb
                    out[i * N_FREQ + k] = (max(0.0, min(lower, upper)) * enorm).toFloat()
                }
            }
            return out
        }
    }

    private var env: OrtEnvironment? = null
    private var enc: OrtSession? = null
    private var dec: OrtSession? = null
    private var loadedFrom: String? = null
    private var tokenBytes: Array<ByteArray?> = emptyArray()
    private var sot = 0L
    private var eot = 0
    private var lang = 0L
    private var transcribeTok = 0L
    private var noTimestamps = 0L
    private var suppressed = BooleanArray(0)
    private var textCtx = 448

    private var rec: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var recording = false
    private val pcm = ShortArray(N_SAMPLES)
    @Volatile private var n = 0

    fun installed(dir: String): Boolean = FILES.all { File(dir, it).isFile }

    val isRecording: Boolean get() = recording

    @Synchronized
    private fun load(dir: String) {
        if (dec != null && loadedFrom == dir) return
        release()
        val e = OrtEnvironment.getEnvironment()
        // Full graph optimisation, as in the Python reference. Note: on the Android build of ONNX Runtime this model's encoder output
        // still differs from the Mac build by about 27% (relative RMS; the Mac matches it only at ALL/EXTENDED, the phone behaves like
        // BASIC): the quantised graph gets different fusions there. Measured effect: 60 clips word error 39.1% (Mac) vs 44.8% (BASIC).
        val o = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(4)
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
        }
        val en = e.createSession(File(dir, "encoder.int8.onnx").absolutePath, o)
        val de = e.createSession(File(dir, "decoder.int8.onnx").absolutePath, o)
        val m = en.metadata.customMetadata
        fun get(k: String) = m[k] ?: throw IllegalStateException("model metadata missing: $k")
        val codes = get("all_language_codes").split(",")
        val langTokens = get("all_language_tokens").split(",").map { it.trim().toLong() }
        lang = langTokens[codes.indexOf("te")]
        sot = get("sot").toLong()
        eot = get("eot").toInt()
        transcribeTok = get("transcribe").toLong()
        noTimestamps = get("no_timestamps").toLong()
        textCtx = get("n_text_ctx").toInt()
        val nVocab = get("n_vocab").toInt()
        suppressed = BooleanArray(nVocab)
        for (t in get("non_speech_tokens").split(",")) t.trim().toIntOrNull()?.let { if (it in 0 until nVocab) suppressed[it] = true }
        val tb = arrayOfNulls<ByteArray>(nVocab)
        File(dir, "tokens.txt").forEachLine { line ->
            val sp = line.lastIndexOf(' ')
            if (sp > 0) {
                val id = line.substring(sp + 1).trim().toIntOrNull()
                val b64 = line.substring(0, sp).trim('=')
                // a token that is only "=" (the last id, an end marker) decodes to nothing: Android's decoder refuses it, Python's reads it as empty
                if (id != null && id in 0 until nVocab && b64.isNotEmpty()) {
                    tb[id] = try { Base64.decode(line.substring(0, sp), Base64.DEFAULT) } catch (_: IllegalArgumentException) { null }
                }
            }
        }
        tokenBytes = tb
        env = e
        enc = en
        dec = de
        loadedFrom = dir
    }

    @Synchronized
    fun release() {
        try { enc?.close() } catch (_: Exception) {}
        try { dec?.close() } catch (_: Exception) {}
        enc = null
        dec = null
        loadedFrom = null
    }

    /** Starts capturing. Returns false if the microphone could not be opened. Needs RECORD_AUDIO to be granted already. */
    @Synchronized
    fun start(): Boolean {
        if (recording) return true
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) return false
        val r = try {
            AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, RATE))
        } catch (e: Exception) {
            return false
        }
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            return false
        }
        n = 0
        rec = r
        recording = true
        r.startRecording()
        thread = Thread {
            val buf = ShortArray(1600)
            while (recording) {
                val got = r.read(buf, 0, buf.size)
                if (got <= 0) continue
                val take = minOf(got, pcm.size - n)
                System.arraycopy(buf, 0, pcm, n, take)
                n += take
                if (n >= pcm.size) recording = false // 30 s cap: the Dart side is told by stop()'s result
            }
        }.also { it.start() }
        return true
    }

    /** Stops capturing and recognises what was said. Blocks: call off the main thread. */
    fun stopAndRecognise(dir: String): String {
        val r = synchronized(this) {
            recording = false
            val x = rec
            rec = null
            x
        }
        thread?.join(1000)
        thread = null
        try { r?.stop() } catch (_: Exception) {}
        r?.release()
        val samples = n
        n = 0
        return recognise(pcm, samples, dir)
    }

    @Synchronized
    fun cancel() {
        recording = false
        try { rec?.stop() } catch (_: Exception) {}
        rec?.release()
        rec = null
        n = 0
    }

    /** Recognises a 16 kHz mono 16-bit WAV file (44-byte header). Used by the Voice Test and the debug hook to test without speaking. */
    fun recogniseWav(dir: String, path: String): String {
        RandomAccessFile(path, "r").use { f ->
            val bytes = ByteArray((f.length() - 44).toInt())
            f.seek(44)
            f.readFully(bytes)
            val s = ShortArray(minOf(bytes.size / 2, pcm.size))
            for (i in s.indices) s[i] = ((bytes[2 * i + 1].toInt() shl 8) or (bytes[2 * i].toInt() and 0xff)).toShort()
            return recognise(s, s.size, dir)
        }
    }

    /** Whisper's log-mel front end: (80 x 3000) values, row = mel band. Frames that only see padding are all the same, so they are filled in. */
    private fun logMel(src: ShortArray, samples: Int): FloatArray {
        val len = min(samples, N_SAMPLES)
        val a = FloatArray(len) { src[it] / 32768f }
        // the padded signal is the audio then zeros up to 30 s, reflected by N_FFT/2 at the start and end
        fun sample(i: Int): Float {
            var j = i - N_FFT / 2
            if (j < 0) j = -j
            if (j >= N_SAMPLES) j = 2 * (N_SAMPLES - 1) - j
            return if (j < len) a[j] else 0f
        }
        val active = min(N_FRAMES, len / HOP + 3)
        val spec = FloatArray(N_MELS * N_FRAMES)
        val x = FloatArray(N_FFT)
        val power = FloatArray(N_FREQ)
        for (f in 0 until active) {
            for (t in 0 until N_FFT) x[t] = sample(f * HOP + t) * window[t]
            for (k in 0 until N_FREQ) {
                var re = 0f
                var im = 0f
                val base = k * N_FFT
                for (t in 0 until N_FFT) {
                    re += x[t] * cosT[base + t]
                    im += x[t] * sinT[base + t]
                }
                power[k] = re * re + im * im
            }
            for (m in 0 until N_MELS) {
                var s = 0f
                val base = m * N_FREQ
                for (k in 0 until N_FREQ) s += filters[base + k] * power[k]
                spec[m * N_FRAMES + f] = log10(max(s, 1e-10f))
            }
        }
        val silent = log10(1e-10f)
        for (m in 0 until N_MELS) for (f in active until N_FRAMES) spec[m * N_FRAMES + f] = silent
        var top = -Float.MAX_VALUE
        for (v in spec) if (v > top) top = v
        val floor = top - 8f
        for (i in spec.indices) spec[i] = (max(spec[i], floor) + 4f) / 4f
        return spec
    }

    @Synchronized
    private fun recognise(src: ShortArray, samples: Int, dir: String): String {
        if (samples < RATE / 5) return "" // under 0.2 s: nothing was said
        load(dir)
        val e = env!!
        val mel = logMel(src, samples)
        val melBuf = ByteBuffer.allocateDirect(mel.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(mel); rewind() }
        OnnxTensor.createTensor(e, melBuf, longArrayOf(1, N_MELS.toLong(), N_FRAMES.toLong())).use { melT ->
            enc!!.run(mapOf("mel" to melT)).use { eo ->
                val ck = eo[0] as OnnxTensor
                val cv = eo[1] as OnnxTensor
                return decode(e, ck, cv)
            }
        }
    }

    private fun decode(e: OrtEnvironment, ck: OnnxTensor, cv: OnnxTensor): String {
        val dim = 384
        val layers = 4
        fun zeros() = OnnxTensor.createTensor(
            e,
            ByteBuffer.allocateDirect(layers * textCtx * dim * 4).order(ByteOrder.nativeOrder()).asFloatBuffer(),
            longArrayOf(layers.toLong(), 1, textCtx.toLong(), dim.toLong()),
        )
        var kc = zeros()
        var vc = zeros()
        var ownCaches = true
        var prev: OrtSession.Result? = null
        var cur = longArrayOf(sot, lang, transcribeTok, noTimestamps)
        var offset = 0L
        val out = ByteArrayOutputStream()
        try {
            for (step in 0 until MAX_TOKENS) {
                val tok = OnnxTensor.createTensor(e, LongBuffer.wrap(cur), longArrayOf(1, cur.size.toLong()))
                val off = OnnxTensor.createTensor(e, LongBuffer.wrap(longArrayOf(offset)), longArrayOf(1))
                val res = dec!!.run(
                    mapOf(
                        "tokens" to tok,
                        "in_n_layer_self_k_cache" to kc,
                        "in_n_layer_self_v_cache" to vc,
                        "n_layer_cross_k" to ck,
                        "n_layer_cross_v" to cv,
                        "offset" to off,
                    ),
                )
                tok.close()
                off.close()
                val logitsT = res[0] as OnnxTensor
                val vocab = logitsT.info.shape[2].toInt()
                val logits = logitsT.floatBuffer
                val row = (cur.size - 1) * vocab
                var best = -1
                var bv = -Float.MAX_VALUE
                for (i in 0 until vocab) {
                    if (i < suppressed.size && suppressed[i]) continue
                    if (step == 0 && (i == 220 || i == eot)) continue
                    val v = logits.get(row + i)
                    if (v > bv) {
                        bv = v
                        best = i
                    }
                }
                if (ownCaches) {
                    kc.close()
                    vc.close()
                    ownCaches = false
                } else {
                    prev?.close()
                }
                prev = res
                kc = res[1] as OnnxTensor
                vc = res[2] as OnnxTensor
                offset += cur.size
                if (best < 0 || best == eot) break
                tokenBytes.getOrNull(best)?.let { out.write(it) }
                cur = longArrayOf(best.toLong())
                if (offset + 1 >= textCtx) break
            }
        } finally {
            if (ownCaches) {
                kc.close()
                vc.close()
            }
            prev?.close()
        }
        return String(out.toByteArray(), Charsets.UTF_8).trim()
    }
}
