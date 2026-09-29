"""Original procedural explosion for the combat prototype; NumPy/SciPy/SoundFile."""
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

sr = 48000
t = np.arange(int(sr * .85)) / sr
rng = np.random.default_rng(194244)
noise = sosfilt(butter(2, [60, 1700], btype='bandpass', fs=sr, output='sos'), rng.normal(size=len(t)))
signal = noise * np.exp(-t / .14) * .7
signal += np.sin(2 * np.pi * (48 * t + 44 * .045 * (1 - np.exp(-t / .045)))) * np.exp(-t / .12) * .35
signal *= np.minimum(t / .001, 1) * np.minimum((t[-1] - t) / .04, 1)
signal = np.tanh(signal * 1.8)
signal *= .7 / max(abs(signal))
path = Path(__file__).resolve().parents[1] / 'game/assets/audio/weapons/explosion.wav'
sf.write(path, np.column_stack([signal, signal * .95]), sr, subtype='PCM_16')
