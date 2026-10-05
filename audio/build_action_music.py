"""Prepare credited CC0 tracks without changing their melodies or tempo.
Source ZIP: https://opengameart.org/content/5-chiptunes-action
Extract into tools/action-chiptunes before running. Also builds original laser SFX.
"""
from pathlib import Path
import numpy as np
import soundfile as sf
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'game/assets/campaign/music'
for target, title in [('menu','Title Screen'),('flight','Level 1'),('flight2','Level 2'),('boss','Level 3'),('victory','Ending')]:
    source = ROOT/'tools/action-chiptunes'/f'Juhani Junkala [Retro Game Music Pack] {title}.wav'
    samples, rate = sf.read(source)
    samples *= .75/max(.001,np.max(np.abs(samples)))
    sf.write(OUT/f'{target}.wav', samples, rate, subtype='PCM_16')
    print(target, len(samples)/rate, 'seconds')
rate=44100
t=np.arange(rate)/rate
# Integer-period carriers make a seamless one-second loop, bright but not shrill.
wave=(np.sin(2*np.pi*110*t+1.4*np.sin(2*np.pi*220*t))*.22+np.sin(2*np.pi*880*t)*.05)
wave*=.8+.2*np.cos(2*np.pi*12*t)
sf.write(ROOT/'game/assets/campaign/laser-loop.wav', np.column_stack((wave,np.roll(wave,70))),rate,subtype='PCM_16')
