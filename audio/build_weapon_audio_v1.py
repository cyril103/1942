"""Build six sample-based aircraft gun salvos from CC0 recordings (NumPy).
See game/assets/audio/weapons/CREDITS.md for provenance.
"""
import hashlib
import json
import wave
import numpy as np
from build_synthetic_audio import ROOT, OUT, SR, gun, pan, write

SOURCES = ROOT / "audio/sources/Prepared SFX Library/PPSh"


def read_pcm24(path):
    with wave.open(str(path)) as wav:
        assert wav.getsampwidth() == 3 and wav.getframerate() == 96000
        channels = wav.getnchannels()
        data = np.frombuffer(wav.readframes(wav.getnframes()), np.uint8).reshape(-1, 3).astype(np.int32)
    ints = ((data[:, 0] | data[:, 1] << 8 | data[:, 2] << 16) ^ 0x800000) - 0x800000
    mono = (ints.reshape(-1, channels) / 8388608.0).mean(axis=1)
    frequencies = np.fft.rfftfreq(len(mono), 1 / 96000)
    mono = np.fft.irfft(np.fft.rfft(mono) * np.exp(-(frequencies / 14500) ** 12), n=len(mono))
    return mono[::2]


def extract(source, onset):
    start = int((onset - .003) * SR)
    clip = source[start:start + int(.28 * SR)].copy()
    t = np.arange(len(clip)) / SR
    frequencies = np.fft.rfftfreq(len(clip), 1 / SR)
    eq = (1 - np.exp(-(frequencies / 65) ** 4)) * np.exp(-(frequencies / 8500) ** 6)
    clip = np.fft.irfft(np.fft.rfft(clip) * eq, n=len(clip))
    clip *= np.exp(-np.maximum(t - .04, 0) / .047)
    clip *= np.minimum(t / .0003, 1) * np.minimum((t[-1] - t) / .02, 1)
    return clip / max(np.max(np.abs(clip)), 1e-9)


sources = {name: read_pcm24(SOURCES / name) for name in ["P_30P.wav", "P_16P.wav"]}
cuts = [("P_30P.wav", t) for t in [.965, 4.385, 8.24, 11.42, 15.09]] + [("P_16P.wav", .29)]
takes = [extract(sources[name], t) for name, t in cuts]
salvos, report = [], []
for index in range(6):
    rng = np.random.default_rng(194242 + index)
    left = takes[index] * .88 + gun(rng) * .12
    right = takes[(index + 2) % 6] * .88 + gun(rng) * .12
    delay = int(SR * rng.uniform(.006, .009))
    mix = np.zeros((len(left) + delay, 2))
    mix[:len(left)] += pan(left, -.28)
    mix[delay:] += pan(right, .28) * .95
    mix = np.tanh(mix * 1.15)
    mix *= 10 ** (-5.5 / 20) / np.max(np.abs(mix))
    filename = f"salvo_{index + 1:02}.wav"
    write(OUT / filename, mix)
    salvos.append(mix)
    report.append({"file": filename, "cuts": [cuts[index], cuts[(index + 2) % 6]],
                   "duration": len(mix) / SR, "peak_dbfs": -5.5})

preview = np.zeros((SR * 7, 2))
events = [.25, 1.1, 1.225, 1.35, 1.475] + list(np.arange(2.2, 5.7, .125))
for index, when in enumerate(events):
    sample = salvos[index % 6] * 10 ** (-7 / 20)
    start = int(when * SR)
    preview[start:start + len(sample)] += sample
write(ROOT / "audio/weapon-preview.wav", preview)
for path in OUT.glob("*.wav.import"):
    path.write_text(path.read_text().replace("compress/mode=2", "compress/mode=0"))
report_data = {"sample_rate": SR, "variants": report,
               "preview_peak_dbfs": float(20 * np.log10(np.max(np.abs(preview)))),
               "source": "The Free Firearm Sound Library (CC0), layered with original synthesis",
               "source_sha256": {name: hashlib.sha256((SOURCES / name).read_bytes()).hexdigest() for name in sources}}
(OUT / "analysis.json").write_text(json.dumps(report_data, indent=2))
print(json.dumps(report_data, indent=2))
