"""Original deterministic aircraft gun sound design. Requires NumPy, no samples.

48 kHz stereo PCM. Each salvo contains two subtly staggered, independent guns.
Layering: pressure transient, combustion noise, low body, bolt/feed mechanism.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game/assets/audio/weapons"
SR = 48000
OUT.mkdir(parents=True, exist_ok=True)


def noise(rng, length, low, high):
    source = rng.normal(size=length)
    freqs = np.fft.rfftfreq(length, 1 / SR)
    curve = (1 - np.exp(-(freqs / low) ** 4)) * np.exp(-(freqs / high) ** 4)
    filtered = np.fft.irfft(np.fft.rfft(source) * curve, n=length)
    return filtered / (np.std(filtered) + 1e-9)


def gun(rng):
    t = np.arange(int(SR * .28)) / SR
    n = len(t)
    attack = 1 - np.exp(-t / .00018)
    # Short broadband pressure crack, rounded above 8 kHz to avoid harshness.
    crack = noise(rng, n, 850, 7400) * np.exp(-t / .0045) * .52
    body = noise(rng, n, 100, 1900) * np.exp(-t / rng.uniform(.025, .033)) * .32
    freq = rng.uniform(105, 125)
    phase = 2 * np.pi * (freq * t + 55 * .012 * (1 - np.exp(-t / .012)))
    thump = np.sin(phase) * np.exp(-t / .025) * .22
    blast = noise(rng, n, 230, 3400) * np.exp(-t / .062) * .065
    result = attack * (crack + body + thump + blast)
    # Mechanical movement behind the blast: short, inharmonic resonances.
    for offset, gain in [(rng.uniform(.016, .021), .105), (.053, .047)]:
        q = np.maximum(t - offset, 0)
        env = (t >= offset) * (1 - np.exp(-q / .0003)) * np.exp(-q / .008)
        metal = sum(np.sin(2 * np.pi * f * rng.uniform(.97, 1.03) * q)
                    for f in (930, 1780, 2910)) / 3
        result += env * gain * (metal + noise(rng, n, 1400, 6500) * .4)
    # Gentle saturation glues layers; remove subsonic energy/DC afterward.
    result = np.tanh(result * 1.35) / 1.35
    freq_axis = np.fft.rfftfreq(n, 1 / SR)
    result = np.fft.irfft(np.fft.rfft(result) * (1 - np.exp(-(freq_axis / 48) ** 4)), n=n)
    result *= np.minimum(t / .00035, 1) * np.minimum((t[-1] - t) / .025, 1)
    return result


def pan(mono, position):
    angle = (position + 1) * np.pi / 4
    return mono[:, None] * np.array([np.cos(angle), np.sin(angle)])


def write(path, signal):
    assert np.isfinite(signal).all() and np.max(np.abs(signal)) < 1
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(np.round(signal * 32767).astype("<i2").tobytes())


def main():
    salvos = []
    report = []
    for i in range(6):
        rng = np.random.default_rng(194200 + i)
        left, right = gun(rng), gun(rng)
        delay = int(SR * rng.uniform(.006, .010))
        shot = np.zeros((len(left) + delay, 2))
        shot[:len(left)] += pan(left, -.28)
        shot[delay:] += pan(right, .28) * rng.uniform(.91, .98)
        shot *= 10 ** (-5.5 / 20) / np.max(np.abs(shot))
        write(OUT / f"salvo_{i + 1:02}.wav", shot)
        salvos.append(shot)
        report.append({"file": f"salvo_{i + 1:02}.wav", "duration": len(shot) / SR,
                       "peak_dbfs": float(20 * np.log10(np.max(np.abs(shot)))),
                       "rms_dbfs": float(20 * np.log10(np.sqrt(np.mean(shot ** 2))))})

    # Listening preview at the game gain: isolated salvo, short then sustained burst.
    preview = np.zeros((SR * 7, 2))
    events = [.25, 1.1, 1.225, 1.35, 1.475] + list(np.arange(2.2, 5.7, .125))
    for i, when in enumerate(events):
        sample = salvos[i % 6] * 10 ** (-7 / 20)
        start = int(when * SR)
        preview[start:start + len(sample)] += sample
    write(ROOT / "audio/weapon-preview.wav", preview)
    (OUT / "analysis.json").write_text(json.dumps({"sample_rate": SR, "variants": report,
        "preview_peak_dbfs": float(20 * np.log10(np.max(np.abs(preview)))),
        "source": "Original procedural synthesis; no external recordings."}, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
