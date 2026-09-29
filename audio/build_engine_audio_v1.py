"""Build seamless engine layers from credited recordings, 48 kHz PCM."""
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import butter,sosfilt,resample_poly
R=Path(__file__).resolve().parents[1]; sr=48000
out=R/'game/assets/audio/engine'
def loop(x,fade=.18):
    n=int(sr*fade); w=np.linspace(0,1,n)[:,None]
    seam=x[-n:]*(1-w)+x[:n]*w
    return np.concatenate([seam,x[n:-n]])
def build(name,filename,start,end,band,slow=1):
    x,rate=sf.read(R/'audio/sources'/filename,always_2d=True)
    x=x[int(start*rate):int(end*rate)]
    x=resample_poly(x,sr,round(rate*slow))
    x=sosfilt(butter(3,band,btype='bandpass',fs=sr,output='sos'),x,axis=0)
    x=loop(x)
    x=np.tanh(x*1.2)
    x*=.65/max(abs(x).max(),.001)
    sf.write(out/name,x,sr,subtype='PCM_16')
    print(name,len(x)/sr,'peak',abs(x).max(),'seam',abs(x[0]-x[-1]).max())
build('propeller.wav','airplane_prop.flac',0,4.957,[65,5800],.88)
build('radial-body.wav','craigsmith-engine-steady.mp3',5,15,[40,1250],.95)
