"""Layered gun sound design v2. Rebuild with audio/.venv/Scripts/python.exe.
Dependencies: numpy, scipy, soundfile. See bundled CREDITS.md for licenses.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt, resample_poly

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/audio/weapons'
SR, LENGTH = 48000, 28800  # 600 ms; at most five overlapping tails at 8 Hz.
SOURCES = ROOT / 'audio/sources'


def band(x, low, high):
    return sosfilt(butter(2, [low, high], btype='bandpass', fs=SR, output='sos'), x, axis=0)


def load(path):
    x, rate = sf.read(path, always_2d=True)
    divisor = np.gcd(rate, SR)
    return resample_poly(x, SR // divisor, rate // divisor, axis=0)


def cut(x, onset, length=.55):
    # Keep the pre-transient stereo material, with a sub-millisecond fade.
    start = max(0, int((onset - .006) * SR))
    result = np.zeros((LENGTH, x.shape[1]))
    segment = x[start:start + int(length * SR)]
    result[:len(segment)] = segment
    result[:24] *= np.linspace(0, 1, 24)[:, None]
    return result


def envelope(hold, decay):
    t = np.arange(LENGTH) / SR
    return (np.exp(-np.maximum(t - hold, 0) / decay) * np.minimum((t[-1] - t) / .045, 1))[:, None]


def rms(x):
    return np.sqrt(np.mean(x * x)) + 1e-10


def place(x, pan):
    # Keep some actual stereo ambience while positioning each wing's gun.
    mid = x.mean(axis=1)
    side = (x[:, 0] - x[:, -1]) * .22
    angle = (pan + 1) * np.pi / 4
    return np.column_stack([mid * np.cos(angle) + side, mid * np.sin(angle) - side])


near_path = SOURCES / 'Prepared SFX Library/PPSh/P_30P.wav'
far_path = SOURCES / 'Prepared SFX Library/PPSh/P_16P.wav'
body_path = SOURCES / 'lmg_fire01-KuraiWolf.mp3'
near, distant, lmg = load(near_path), load(far_path), load(body_path)
onset = np.flatnonzero(np.max(np.abs(lmg), axis=1) > .10)[0] / SR
# Slower recorded pressure body, not a synthesized bass note.
body = resample_poly(cut(lmg, onset), 6, 5, axis=0)[:LENGTH]
body = band(body, 48, 1150) * envelope(.035, .105)
body /= rms(body[:5760])
near_times = [.965, 4.385, 8.24, 11.42, 15.09]
far_times = [.29, 5.25, 9.045, 12.995]
guns = []
for i in range(6):
    raw = cut(near if i < 5 else distant, near_times[i] if i < 5 else .29)
    direct = band(raw, 85, 10500) * envelope(.028, .090)
    direct *= .18 / rms(direct[:5760])
    pressure = body * (.085 + .003 * (i % 3))
    # Distant recorded decay supplies air; suppress its initial gunshot.
    air = band(cut(distant, far_times[i % 4]), 200, 4200)
    air *= envelope(.040, .14)
    air *= (1 - np.exp(-np.arange(LENGTH) / (SR * .024)))[:, None]
    air *= .027 / rms(air[:9600])
    gun = direct + pressure + air
    guns.append(gun)

salvos, metrics = [], []
for i in range(6):
    delay = int(SR * (.008 + .0006 * (i % 3)))
    dry = place(guns[i], -.34)
    dry[delay:] += place(guns[(i + 2) % 6], .34)[:-delay] * .94
    # Quiet asymmetric reflections add space, without an indoor reverb wash.
    reflection = band(dry, 280, 2500)
    wet = np.zeros_like(dry)
    for seconds, left, right in [(.021, .065, .025), (.038, .025, .060), (.067, .022, .014), (.097, .009, .017)]:
        offset = int(seconds * SR)
        wet[offset:] += reflection[:-offset] * [left, right]
    mix = np.tanh((dry + wet) * 1.08)
    mix *= envelope(.20, .20)
    mix *= .21 / rms(mix[:5760])
    mix *= min(1.0, 10 ** (-2.5 / 20) / np.max(np.abs(mix)))
    assert np.isfinite(mix).all() and np.max(np.abs(mix)) < .8
    name = f'salvo_{i + 1:02}.wav'
    sf.write(OUT / name, mix, SR, subtype='PCM_16')
    salvos.append(mix)
    metrics.append({'file': name, 'duration': LENGTH / SR,
                    'peak_dbfs': float(20 * np.log10(np.max(np.abs(mix)))),
                    'attack_rms_dbfs': float(20 * np.log10(rms(mix[:5760])))})

preview = np.zeros((SR * 8, 2))
for i, time in enumerate([.3, 1.4, 1.525, 1.65, 1.775] + list(np.arange(2.9, 6.4, .125))):
    start = int(time * SR)
    preview[start:start + LENGTH] += salvos[i % 6] * 10 ** (-5 / 20)
assert abs(preview).max() < .9
sf.write(ROOT / 'audio/weapon-preview.wav', preview, SR, subtype='PCM_16')
sf.write(ROOT / 'audio/weapon-preview-v2.wav', preview, SR, subtype='PCM_16')
# A/B at matched RMS, to distinguish extra depth from a mere volume increase.
old, _ = sf.read(ROOT / 'audio/weapon-preview-v1.wav', always_2d=True)
old *= rms(preview) / rms(old)
comparison = np.concatenate([old, np.zeros((SR, 2)), preview])
comparison *= min(1, .8 / np.max(np.abs(comparison)))
sf.write(ROOT / 'audio/weapon-comparison.wav', comparison, SR, subtype='PCM_16')
for path in OUT.glob('*.wav.import'):
    path.write_text(path.read_text().replace('compress/mode=2', 'compress/mode=0'))
report = {'version': 2, 'sample_rate': SR, 'variants': metrics,
          'preview_peak_dbfs': float(20 * np.log10(abs(preview).max())),
          'source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [near_path, far_path, body_path]},
          'layers': ['stereo recorded attack', 'recorded low pressure body', 'recorded distant air', 'subtle early reflections']}
(OUT / 'analysis.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
