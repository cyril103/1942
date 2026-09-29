"""WWII fighter engine v2: actual P-51 Merlin recording by doubletrigger (CC BY 3.0)."""
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import butter,sosfilt,resample_poly
R=Path(__file__).resolve().parents[1]; SR=48000
x,rate=sf.read(R/'audio/sources/doubletrigger-p51-merlin.mp3',always_2d=True)
# A short stable section avoids repeating the entire recorded fly-by Doppler.
x=x[int(.75*rate):int(2.65*rate)]
x=resample_poly(x,SR,rate)
def make(name,band,gain):
    y=sosfilt(butter(3,band,btype='bandpass',fs=SR,output='sos'),x,axis=0)
    # Flatten slow recording-level variations while retaining exhaust transients.
    block=2400
    env=np.sqrt(np.convolve(np.mean(y*y,axis=1),np.ones(block)/block,'same')+1e-7)
    y*=np.clip(np.median(env)/env,.7,1.4)[:,None]
    n=int(.12*SR); w=np.linspace(0,1,n)[:,None]
    y=np.concatenate([y[-n:]*(1-w)+y[:n]*w,y[n:-n]])
    # Preserve engine rasp; very gentle peak rounding, not heavy fuzz distortion.
    y=np.tanh(y*1.1)
    y*=gain/max(np.max(abs(y)),.001)
    sf.write(R/'game/assets/audio/engine'/name,y,SR,subtype='PCM_16')
    print(name,'seconds',len(y)/SR,'peak',np.max(abs(y)))
make('merlin-exhaust.wav',[220,8500],.78)
make('merlin-body.wav',[38,420],.70)
