"""Reference Whisper (sherpa-onnx export) greedy decoder in numpy + onnxruntime. The phone's Kotlin port (WhisperAsr.kt) must give the same text.

    python3 -c "import soundfile as sf; from whisper_reference import Whisper; a,_=sf.read('x.wav',dtype='float32'); print(Whisper('models/te-asr').transcribe_audio(a))"

Needs numpy and onnxruntime. The model folder holds encoder.int8.onnx, decoder.int8.onnx and tokens.txt."""
import base64, math, sys, time
import numpy as np
import onnxruntime as ort

SR, NFFT, HOP, NMELS, NSAMP = 16000, 400, 160, 80, 480000

def hz_to_mel(f):  # slaney
    f = np.asarray(f, dtype=np.float64); lin = f / (200.0 / 3)
    logstep = math.log(6.4) / 27.0
    return np.where(f >= 1000.0, 15.0 + np.log(np.maximum(f, 1e-9) / 1000.0) / logstep, lin)
def mel_to_hz(m):
    m = np.asarray(m, dtype=np.float64); logstep = math.log(6.4) / 27.0
    return np.where(m >= 15.0, 1000.0 * np.exp(logstep * (m - 15.0)), m * (200.0 / 3))

def mel_filters():
    nfreq = NFFT // 2 + 1
    fftfreqs = np.linspace(0, SR / 2, nfreq)
    mels = np.linspace(hz_to_mel(0.0), hz_to_mel(SR / 2), NMELS + 2)
    hz = mel_to_hz(mels)
    fdiff = np.diff(hz)
    ramps = hz[:, None] - fftfreqs[None, :]
    w = np.zeros((NMELS, nfreq))
    for i in range(NMELS):
        lower = -ramps[i] / fdiff[i]; upper = ramps[i + 2] / fdiff[i + 1]
        w[i] = np.maximum(0, np.minimum(lower, upper))
    enorm = 2.0 / (hz[2:NMELS + 2] - hz[:NMELS])
    return (w * enorm[:, None]).astype(np.float32)

FILT = mel_filters()
WIN = (0.5 - 0.5 * np.cos(2 * np.pi * np.arange(NFFT) / NFFT)).astype(np.float32)  # periodic hann

def log_mel(audio):
    a = np.zeros(NSAMP, dtype=np.float32); n = min(len(audio), NSAMP); a[:n] = audio[:n]
    p = np.pad(a, (NFFT // 2, NFFT // 2), mode="reflect")
    nfr = 1 + (len(p) - NFFT) // HOP
    idx = np.arange(NFFT)[None, :] + HOP * np.arange(nfr)[:, None]
    spec = np.abs(np.fft.rfft(p[idx] * WIN, axis=1)) ** 2  # (frames, 201)
    spec = spec[:-1].T                                        # drop last frame -> (201, 3000)
    mel = FILT @ spec
    ls = np.log10(np.maximum(mel, 1e-10))
    ls = np.maximum(ls, ls.max() - 8.0)
    return ((ls + 4.0) / 4.0).astype(np.float32)             # (80, 3000)

class Whisper:
    def __init__(self, d, threads=4):
        o = ort.SessionOptions(); o.intra_op_num_threads = threads
        self.enc = ort.InferenceSession(f"{d}/encoder.int8.onnx", o, providers=["CPUExecutionProvider"])
        self.dec = ort.InferenceSession(f"{d}/decoder.int8.onnx" if not hasattr(self, "decname") else self.decname, o, providers=["CPUExecutionProvider"])
        m = self.enc.get_modelmeta().custom_metadata_map
        codes = m["all_language_codes"].split(","); toks = [int(x) for x in m["all_language_tokens"].split(",")]
        self.sot, self.eot = int(m["sot"]), int(m["eot"])
        self.lang = toks[codes.index("te")]; self.transcribe = int(m["transcribe"]); self.nots = int(m["no_timestamps"])
        self.suppress = [int(x) for x in m["non_speech_tokens"].split(",")]
        self.vocab = {}
        for line in open(f"{d}/tokens.txt", encoding="utf-8"):
            b, i = line.split(); self.vocab[int(i)] = base64.b64decode(b)
        self.ntext = int(m["n_text_ctx"])
    def transcribe_audio(self, audio, max_tokens=440):
        mel = log_mel(audio)[None]
        ck, cv = self.enc.run(None, {"mel": mel})
        L = 4; kc = np.zeros((L, 1, self.ntext, 384), np.float32); vc = np.zeros_like(kc)
        toks = [self.sot, self.lang, self.transcribe, self.nots]
        out = []; offset = 0; cur = np.array([toks], dtype=np.int64)
        for step in range(max_tokens):
            logits, kc, vc = self.dec.run(None, {"tokens": cur, "in_n_layer_self_k_cache": kc, "in_n_layer_self_v_cache": vc,
                                                  "n_layer_cross_k": ck, "n_layer_cross_v": cv, "offset": np.array([offset], dtype=np.int64)})
            lg = logits[0, -1].copy()
            lg[self.suppress] = -1e30
            if step == 0: lg[220] = -1e30; lg[self.eot] = -1e30   # no blank / immediate end
            nxt = int(np.argmax(lg))
            offset += cur.shape[1]
            if nxt == self.eot: break
            out.append(nxt); cur = np.array([[nxt]], dtype=np.int64)
        return b"".join(self.vocab.get(t, b"") for t in out).decode("utf-8", errors="replace").strip()
