"""Build original Pacific Strike event cues using only Python's standard library.

No external recordings, models or downloads. Run with --verify to check the
committed PCM files without replacing them. The game keeps its existing gains.
"""

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import random
import struct
import wave


RATE = 44100
PEAK = 0.18  # Below the previous radio cue's measured 0.18338 full-scale peak.
ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "game/assets/campaign/audio/events"
# (start, duration, fundamental Hz, end Hz, relative amplitude, radio texture)
SCORES = {
    "boss": (0.69, [(0.015, .29, 320, 275, 1.0, 0.0),
                     (.345, .32, 240, 220, .95, 0.0)]),
    "danger": (.405, [(0.01, .105, 1050, 920, 1.0, .035),
                       (.15, .09, 1050, 920, .9, .035),
                       (.275, .105, 1050, 920, .85, .035)]),
    "radio": (.245, [(.01, .075, 740, 755, 1.0, .15),
                     (.125, .095, 960, 960, .8, .12)]),
    "radio_important": (.43, [(.01, .11, 610, 610, .85, .10),
                               (.15, .11, 815, 815, .9, .09),
                               (.29, .115, 1085, 1085, 1.0, .06)]),
    "reward": (.48, [(.01, .14, 660, 660, .9, 0.0),
                      (.13, .15, 825, 825, .85, 0.0),
                      (.25, .205, 990, 990, 1.0, 0.0)]),
}


def build(kind):
    duration, notes = SCORES[kind]
    samples = [0.0] * round(duration * RATE)
    rng = random.Random(1942 + list(SCORES).index(kind))
    for start, length, first, last, gain, texture in notes:
        offset = round(start * RATE)
        count = round(length * RATE)
        previous_noise = 0.0
        filtered_noise = 0.0
        for index in range(count):
            time = index / RATE
            progress = index / (count - 1)
            # Smooth attack/release for each note, including overlapping notes.
            attack = min(1.0, time / .009)
            release = min(1.0, (count - 1 - index) / RATE / .045)
            envelope = math.sin(attack * math.pi / 2) ** 2
            envelope *= math.sin(release * math.pi / 2) ** 2
            envelope *= .8 + .2 * math.cos(progress * math.pi / 2)
            phase = 2 * math.pi * (first * time + .5 * (last - first) * time * time / length)
            # Low warning has a rounded horn timbre; other cues use clear pips.
            if kind == "boss":
                tone = math.sin(phase) + .28 * math.sin(phase * 2) + .10 * math.sin(phase * 3)
            else:
                tone = math.sin(phase) + .12 * math.sin(phase * 2)
            noise = rng.uniform(-1.0, 1.0)
            filtered_noise = .70 * filtered_noise + .30 * (noise - previous_noise)
            previous_noise = noise
            samples[offset + index] += gain * envelope * (tone + texture * filtered_noise)
    scale = PEAK / max(abs(value) for value in samples)
    pcm = [round(max(-1.0, min(1.0, value * scale)) * 32767) for value in samples]
    output = io.BytesIO()
    with wave.open(output, "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(struct.pack("<" + "h" * len(pcm), *pcm))
    # These bounds detect clipping, discontinuities and accidental DC/noise tails.
    assert max(abs(value) for value in pcm) <= round(PEAK * 32767)
    assert pcm[:256] == [0] * 256 and pcm[-256:] == [0] * 256
    assert max(abs(right - left) for left, right in zip(pcm, pcm[1:])) < 1800
    assert abs(sum(pcm) / len(pcm)) < 5
    return output.getvalue(), {
        "duration_seconds": len(pcm) / RATE,
        "peak_dbfs": 20 * math.log10(max(abs(value) for value in pcm) / 32768),
        "rms_dbfs": 20 * math.log10(math.sqrt(sum(value * value for value in pcm) / len(pcm)) / 32768),
        "largest_sample_step": max(abs(right - left) for left, right in zip(pcm, pcm[1:])),
        "sha256": hashlib.sha256(output.getvalue()).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    report = {}
    if not args.verify:
        DESTINATION.mkdir(parents=True, exist_ok=True)
    for kind in SCORES:
        content, report[kind] = build(kind)
        path = DESTINATION / (kind + ".wav")
        if args.verify:
            assert path.read_bytes() == content, f"Generated PCM differs: {path}"
        else:
            path.write_bytes(content)
    assert len({entry["sha256"] for entry in report.values()}) == len(SCORES)
    print(json.dumps({"verified": args.verify, "cues": report}, indent=2))


if __name__ == "__main__":
    main()
