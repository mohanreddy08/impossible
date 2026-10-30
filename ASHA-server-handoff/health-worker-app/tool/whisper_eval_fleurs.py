"""Word / character error rate of a Whisper pack on FLEURS Telugu clips: python3 whisper_eval_fleurs.py DATA_DIR N PACK_DIR (needs jiwer, soundfile)."""
import csv, re, sys, time, jiwer, unicodedata
import soundfile as sf
from whisper_reference import Whisper
S=sys.argv[1]; N=int(sys.argv[2]); d=sys.argv[3] if len(sys.argv)>3 else 'whisper-te'
w=Whisper(f"{S}/{d}")
rows=list(csv.reader(open(f"{S}/fleurs/test.tsv",encoding="utf-8"),delimiter="\t"))[:N]
def norm(t):
    t="".join(" " if unicodedata.category(c)[0] in "PS" else c for c in t.lower())
    return re.sub(r"\s+"," ",t).strip()
refs,hyps,t0,dur=[],[],time.time(),0
for r in rows:
    a,sr=sf.read(f"{S}/fleurs/test/{r[1]}",dtype="float32"); dur+=len(a)/sr
    hyps.append(norm(w.transcribe_audio(a))); refs.append(norm(r[3]))
el=time.time()-t0
print("whisper",d,"utterances",len(refs),"audio sec",round(dur),"decode sec",round(el),"RTF",round(el/dur,2))
print("WER %.1f%%  CER %.1f%%"%(100*jiwer.wer(refs,hyps),100*jiwer.cer(refs,hyps)))
