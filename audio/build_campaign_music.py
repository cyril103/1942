"""Original deterministic instrumental loops. No external recordings or melodies."""
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import butter,sosfilt
RATE=44100
OUT=Path('C:/ChatGPT/1942/game/assets/campaign/music')
rng=np.random.default_rng(1942)
def render(mode,bpm):
 beat=60/bpm;duration=64*beat;n=int(duration*RATE);mix=np.zeros((n,2),dtype=np.float64)
 def add(x,start,pan=0):
  index=(np.arange(len(x))+int(start*RATE))%n
  np.add.at(mix[:,0],index,x*np.sqrt((1-pan)*.5))
  np.add.at(mix[:,1],index,x*np.sqrt((1+pan)*.5))
 def note(midi,length,voice='pad'):
  t=np.arange(int(length*RATE))/RATE;f=440*2**((midi-69)/12)
  if voice=='pad':
   wave=sum(np.sin(2*np.pi*f*(1+(h%2)*.0008)*h*t+0.007*np.sin(t*8))*(.36/h**1.6) for h in range(1,7))
   env=np.minimum(t/.32,1)*np.minimum((length-t)/.75,1)
  elif voice=='pluck':
   wave=np.sin(2*np.pi*f*t+1.5*np.exp(-t*9)*np.sin(2*np.pi*f*2*t))*.5
   env=np.minimum(t/.004,1)*np.exp(-t*5)
  else:
   wave=(np.sin(2*np.pi*f*t)+.25*np.sin(2*np.pi*f*2*t)+.12*np.sin(2*np.pi*f*3*t))*.6
   env=np.minimum(t/.015,1)*np.minimum((length-t)/.08,1)*np.exp(-t*1.4)
  return wave*np.clip(env,0,1)
 roots=[38,34,41,36,38,34,43,45]
 for chord,root in enumerate(roots):
  start=chord*8*beat
  for j,interval in enumerate([0,7,15,19]):add(note(root+12+interval,8*beat+.5),start,(j-1.5)*.42)
  for b in range(8):
   add(note(root if b%4<2 else root+7,beat*.85,'bass')*.65,start+b*beat)
  motif=[0,7,12,10,7,3,5,7] if chord%2==0 else [12,10,7,5,3,7,5,0]
  for j,interval in enumerate(motif):
   if mode=='menu' and j%2: continue
   add(note(root+24+interval,beat*1.7,'pluck')*(.22 if mode=='menu' else .36),start+j*beat,(j%3-1)*.5)
 if mode!='menu':
  for b in range(64):
   t=np.arange(int(.38*RATE))/RATE
   if b%4 in [0,2] or mode=='boss':
    kick=np.sin(2*np.pi*(53*t+1.8*(1-np.exp(-t*35))))*np.exp(-t*15)*.8
    add(kick,b*beat)
   if b%4 in [1,3]:
    noise=rng.normal(0,1,len(t));noise=sosfilt(butter(2,[700,7000],fs=RATE,btype='bandpass',output='sos'),noise)
    add((noise*.25+np.sin(2*np.pi*180*t)*.15)*np.exp(-t*23),b*beat,.12)
   for j in range(2 if mode=='flight' else 4):
    ht=np.arange(int(.075*RATE))/RATE
    hat=sosfilt(butter(2,6500,fs=RATE,btype='highpass',output='sos'),rng.normal(0,1,len(ht)))
    add(hat*np.exp(-ht*65)*.08,b*beat+j*beat/(2 if mode=='flight' else 4),-.35 if j%2 else .35)
 # Wraparound reflections provide a seamless spatial bed.
 dry=mix.copy()
 mix += np.roll(dry,int(beat*.75*RATE),axis=0)[:,::-1]*.14
 mix += np.roll(dry,int(beat*1.5*RATE),axis=0)*.07
 mix=np.tanh(mix*.72)
 mix *= .68/max(np.max(np.abs(mix)),.001)
 sf.write(OUT/(mode+'.wav'),mix,RATE,format='WAV',subtype='PCM_16')
 print(mode,round(duration,2),'seconds','peak',round(np.max(np.abs(mix)),3),'rms',round(np.sqrt(np.mean(mix*mix)),3))
for mode,bpm in [('menu',76),('flight',108),('boss',128)]:render(mode,bpm)
