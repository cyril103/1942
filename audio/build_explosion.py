"""Layered CC0 explosion design, reproducible stereo master."""
from pathlib import Path
import json
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt, resample_poly
ROOT=Path(__file__).resolve().parents[1]
SR=48000
N=int(1.9*SR)
t=np.arange(N)/SR
rng=np.random.default_rng(194244)
def filt(x,f,k):
    return sosfilt(butter(2,f,btype=k,fs=SR,output='sos'),x,axis=0)
def source(name,speed=1):
    x,rate=sf.read(ROOT/'audio/sources'/name,always_2d=True)
    x=resample_poly(x,SR,round(rate*speed))
    onset=np.flatnonzero(np.max(abs(x),axis=1)>np.max(abs(x))*.035)[0]
    x=x[max(0,onset-48):]
    out=np.zeros((N,2)); out[:min(N,len(x))]=x[:N]
    return out/max(np.max(abs(out)),.001)
attack=filt(source('EZduzziteh-explosion1.ogg',.87),[90,8000],'bandpass')
body=filt(source('NenadSimic-Muffled-Distant-Explosion.wav',.9),[35,650],'bandpass')
pressure=np.sin(2*np.pi*(44*t+42*.055*(1-np.exp(-t/.055))))
pressure*=(1-np.exp(-t/.003))*np.exp(-t/.28)
air=filt(rng.normal(size=(N,2)),[110,1500],'bandpass')
air*=((1-np.exp(-t/.07))*np.exp(-t/.58))[:,None]
crackle=np.zeros((N,2))
for delay in [.08,.13,.21,.34,.46,.68,.89]:
    start=int(delay*SR); length=int(.085*SR)
    burst=filt(rng.normal(size=(length,2)),[550,5200],'bandpass')
    burst*=(np.exp(-np.arange(length)/SR/.014)*.11*np.exp(-delay))[:,None]
    crackle[start:start+length]+=burst
x=attack*.85+body*.65+pressure[:,None]*.43+air*.30+crackle
for delay,gain in [(.057,.10),(.103,.075),(.167,.04)]:
    offset=int(delay*SR); x[offset:]+=attack[:-offset,::-1]*gain
x=filt(x,28,'highpass')
x*=(np.minimum(t/.0008,1)*np.minimum((t[-1]-t)/.24,1))[:,None]
x=np.tanh(x*1.15); x*=.84/np.max(abs(x))
sf.write(ROOT/'game/assets/audio/weapons/explosion.wav',x,SR,subtype='PCM_16')
sf.write(ROOT/'audio/explosion-preview.wav',x,SR,subtype='PCM_16')
report={'duration':N/SR,'peak_dbfs':float(20*np.log10(np.max(abs(x)))),'two_voices_at_game_gain_peak':float(np.max(abs(x))*2*10**(-9/20))}
(ROOT/'audio/explosion-analysis.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(report)
