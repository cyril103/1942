# Aircraft gun audio

Campaign pacing revision, 2026-10-05: the explosion master now lasts 1.9 seconds,
rebuilt by `audio/build_explosion.py` from the same credited sources below.

## Explosion version 2

CC0 sources, downloaded 2026-09-29:
- **Explosions**, EZduzziteh: https://opengameart.org/content/explosions-4 (`explosion1_0.ogg`).
- **Muffled Distant Explosion**, NenadSimic: https://opengameart.org/content/muffled-distant-explosion.
  The author describes a pitched log-drum sound with delayed reverberation, not an actual explosion recording.

Both use CC0: https://creativecommons.org/publicdomain/zero/1.0/
Rebuilt with `audio/build_explosion.py`: resampled and slowed sources, layered attack,
low-frequency body, synthesized pressure, filtered stereo air and crackles, short
reflections, 28 Hz high-pass, fades and peak mastering. Stereo 48 kHz / 16-bit,
3.4 seconds. Source files retained under `audio/sources`. Runtime gain: -9 dB.

## Guns

Source: **The Free Firearm Sound Library**, recorded by **Ben Jaszczak,
Brian Nelson, Kevin Heras and Matthew Nanney**.

- Source page: https://opengameart.org/node/21826
- Download: https://opengameart.org/sites/default/files/Prepared%20SFX%20Library.7z
- License stated on the source page: **CC0 1.0**.
- License: https://creativecommons.org/publicdomain/zero/1.0/
- Retrieved: 2026-09-29.

Recordings used: `PPSh/P_30P.wav` (near perspective, individual shots) and
`PPSh/P_16P.wav` (mid perspective, individual shots), originally 96 kHz / 24 bit.
The source archive and its master sheet are retained under `audio/sources` outside
the Godot project. This is stylized sound design, not a historically exact
recording of the aircraft's mounted guns.

Additional source in version 2: **Light Machine Gun** by **KuraiWolf**,
licensed **Creative Commons Attribution 4.0 International (CC BY 4.0)**.

- Source: https://opengameart.org/content/light-machine-gun
- File: https://opengameart.org/sites/default/files/lmg_fire01.mp3
- License: https://creativecommons.org/licenses/by/4.0/
- Retrieved: 2026-09-29. Original saved as `audio/sources/lmg_fire01-KuraiWolf.mp3`.

Modifications in version 2: CC0 recordings retain their stereo field; transients
are isolated and downsampled with anti-aliasing to 48 kHz. The KuraiWolf recording
is slowed to 5/6 speed, filtered to a low pressure-body layer, and mixed with the
CC0 attacks and distant decay. Subtle asymmetric early reflections, paired guns,
equalization, fades and peak mastering are applied. Six 600 ms stereo PCM 16-bit
variants are preloaded. These are adaptations; no endorsement is implied.

The CC BY attribution above must accompany distributed versions of these sounds.
`50cal-qubodup-239138.mp3` was evaluated but is NOT used in the game: its transients
were too saturated for this mix. Its source is https://freesound.org/people/qubodup/sounds/239138/
(qubodup, CC0).

Rebuild using `audio/build_weapon_audio.py` (Python + NumPy, SciPy, SoundFile). Cut timestamps,
source hashes and levels are saved in `analysis.json`. Original synthesized
version: `audio/build_synthetic_audio.py`, retained for comparison.
