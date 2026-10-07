"""Original 140 BPM adaptive score. Three sample-aligned 16-bar stems, no samples.
Run with Blender's bundled Python (NumPy). Produces PCM16 assets and radio cues.
"""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/campaign/music'
RATE = 44100
BEAT = 60 / 140
LENGTH = int(round(64 * BEAT * RATE))
rng = np.random.default_rng(1942)
stems = {name: np.zeros((LENGTH, 2), np.float64) for name in ['pulse', 'drive', 'hero']}

def add(stem, beat, signal, gain, pan=0):
    at = int(round(beat * BEAT * RATE))
    signal = np.asarray(signal)
    indexes = (np.arange(len(signal)) + at) % LENGTH
    for channel, weight in enumerate([np.sqrt((1-pan)/2), np.sqrt((1+pan)/2)]):
        np.add.at(stems[stem][:, channel], indexes, signal * gain * weight)

def tone(note, duration, kind='pluck'):
    t = np.arange(int(duration*RATE))/RATE
    frequency = 440*2**((note-69)/12)
    attack = np.minimum(1, t/.008)
    tail = np.minimum(1, np.maximum(0, duration-t)/.045)
    if kind == 'bass':
        sound = np.sin(2*np.pi*frequency*t) + .25*np.sin(4*np.pi*frequency*t)
        env = np.exp(-t*4)*attack*tail
    elif kind == 'brass':
        sound = sum(np.sin(2*np.pi*frequency*h*t)/h**1.6 for h in range(1, 7))
        env = np.minimum(1,t/.04)*tail*(.7+.3*np.exp(-t*6))
    else:
        sound = np.sin(2*np.pi*frequency*t+1.3*np.exp(-t*9)*np.sin(4*np.pi*frequency*t))
        env = np.exp(-t*5)*attack*tail
    return sound*env

def drum(kind):
    duration = {'kick':.32, 'snare':.2, 'hat':.075, 'crash':1.2}[kind]
    t=np.arange(int(duration*RATE))/RATE
    noise=rng.normal(0,1,len(t))
    high=noise-np.convolve(noise,np.ones(11)/11,mode='same')
    if kind=='kick':
        phase=2*np.pi*(49*t+70*.028*(1-np.exp(-t/.028)))
        sound=np.sin(phase)*np.exp(-t*13)+high*.12*np.exp(-t*150)
    elif kind=='snare': sound=(high*.5+np.sin(2*np.pi*185*t)*.4)*np.exp(-t*22)
    else: sound=high*.35*np.exp(-t*(60 if kind=='hat' else 5))
    return np.tanh(sound)*np.minimum(1,t/.001)

# D minor / Bb / F / C: bright forward motion, four increasingly developed phrases.
roots=[38,34,41,36]
chords=[[62,65,69],[58,62,65],[60,65,69],[60,64,67]]
motifs=[[74,77,81,79,77,74,72,69],[74,77,82,81,77,74,70,72],
        [77,81,84,81,79,77,76,74],[76,79,84,83,79,76,74,72]]
for bar in range(16):
    chord=bar%4
    for beat in range(4):
        when=bar*4+beat
        add('drive',when,drum('kick'),.65)
        if beat%2: add('drive',when,drum('snare'),.48, .08)
        for half in [0,.5]:
            add('drive',when+half,drum('hat'),.24 if half else .15,-.22 if half else .22)
            add('pulse',when+half,tone(roots[chord]+(12 if half else 0),BEAT*.44,'bass'),.32)
        if bar%4==3 and beat==3:
            for roll in [.5,.75]: add('drive',when+roll,drum('snare'),.23,roll-.6)
    if bar%4==0: add('drive',bar*4,drum('crash'),.26)
    for step in range(8):
        note=chords[chord][step%3]+(12 if step%4==3 else 0)
        add('pulse',bar*4+step*.5,tone(note,BEAT*.8),.13,(-.35 if step%2 else .35))
        melody=motifs[chord][step]
        line=tone(melody,BEAT*.75,'brass')
        add('hero',bar*4+step*.5,line,.14, -.12)
        add('hero',bar*4+step*.5+.75,line,.035, .45)

def save(path, samples):
    pcm=(np.clip(samples,-.98,.98)*32767).astype('<i2')
    with wave.open(str(path),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(pcm.tobytes())

OUT.mkdir(parents=True,exist_ok=True)
for name,samples in stems.items():
    # Shared headroom; no independent normalization that would upset the mix.
    save(OUT/f'top-{name}.wav',np.tanh(samples)*.65)
    print(name,LENGTH/RATE,'seconds',float(np.max(np.abs(samples))))
save(ROOT/'audio/toppissime-preview.wav',sum(np.tanh(x)*.65 for x in stems.values())*.6)
t=np.arange(int(.22*RATE))/RATE
cue=(np.sin(2*np.pi*880*t)+.35*np.sin(2*np.pi*1320*t))*np.exp(-t*18)*np.minimum(1,t/.006)*.16
save(OUT/'radio-cue.wav',np.column_stack([cue,cue]))
