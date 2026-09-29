"""Engine v3: low recorded roar, irregular exhaust pulses and controlled bass."""
from pathlib import Path
import json
import numpy as np
import soundfile as sf
from scipy.signal import butter,sosfilt,resample_poly
R=Path(__file__).resolve().parents[1]; SR=48000
x,rate=sf.read(R/'audio/sources/doubletrigger-p51-merlin.mp3',always_2d=True)
x=resample_poly(x[int(.65*rate):int(4.85*rate)],SR,round(rate*.82))
def band(x,lo,hi):
    return sosfilt(butter(3,[lo,hi],btype='bandpass',fs=SR,output='sos'),x,axis=0)
def seam(y):
    n=int(.22*SR);w=np.linspace(0,1,n)[:,None]
    return np.concatenate([y[-n:]*(1-w)+y[:n]*w,y[n:-n]])
def norm(x,rms):
    return x*rms/max(np.sqrt(np.mean(x*x)),1e-8)
# Soften the whistle, retaining real combustion/exhaust texture.
roar=seam(band(x,140,1900))
roar=norm(roar,.19)
roar=np.tanh(roar*1.1)
body=seam(band(x,32,260)).mean(axis=1)
body=norm(body,.19)
n=len(body); t=np.arange(n)/SR; duration=n/SR
# Periodic harmonic pressure supports the recording rather than a pure sub sine.
f=round(47*duration)/duration
phase=2*np.pi*f*t + .045*np.sin(2*np.pi*round(3.2*duration)*t/duration)
pulses=np.sin(phase)+.48*np.sin(2*phase+.3)+.25*np.sin(3*phase+.7)+.12*np.sin(5*phase+.2)
pulses*=1+.12*np.sin(2*np.pi*round(11*duration)*t/duration)
body=body*.85+norm(pulses,.16)
body=np.tanh(body*1.15)
body=np.column_stack([body,body]) # bass stays centred and mono compatible
for name,y in [('merlin-exhaust.wav',roar),('merlin-body.wav',body)]:
    y*=min(1,.88/np.max(abs(y)))
    sf.write(R/'game/assets/audio/engine'/name,y,SR,subtype='PCM_16')
    print(name,'duration',len(y)/SR,'rms',np.sqrt(np.mean(y*y)),'peak',np.max(abs(y)))
