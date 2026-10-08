# Aircraft engine samples

## Active version 3: deep P-51-based engine design

**P51 with supercharger.wav**, by **doubletrigger**, CC BY 3.0.
- https://freesound.org/people/doubletrigger/sounds/110736/
- License: https://creativecommons.org/licenses/by/3.0/
- Public HQ MP3 preview downloaded 2026-09-29; retained as
  `audio/sources/doubletrigger-p51-merlin.mp3`.
- Author identifies a fast P-51 Mustang pass with Merlin supercharger whine.
- Adaptation: 0.75-2.65 second excerpt, 48 kHz resampling, separate exhaust and
  low engine bands, slow envelope leveling, gentle saturation, crossfaded loops.
  Version 3 uses a longer 0.65-4.85 second excerpt slowed to 82%, softened
  exhaust highs, a stronger 32-260 Hz recorded body and an original synthesized
  pressure layer (47 Hz fundamental with harmonics and subtle irregularity).
  Bass stays mono compatible. Runtime RPM, radial Doppler and distance gain
  follow the introduction; the extreme version-2 Doppler is reduced.
  The recording is a P-51, not a historical identification of the game's model.
- Outputs: `merlin-exhaust.wav`, `merlin-body.wav`.
- Attribution must accompany distribution. No endorsement is implied.

## Archived version 1 sources (no longer played)

1. **Airplane Prop Loop** by AntumDeluge, derived from **Porter Prop plane Int.WAV**
   recorded by **jakobthiesen**. CC BY 3.0.
   - https://opengameart.org/content/airplane-prop-loop
   - Original: https://freesound.org/people/jakobthiesen/sounds/188423/
   - License: https://creativecommons.org/licenses/by/3.0/
   - Downloaded lossless `airplane_prop.flac` on 2026-09-29.
2. **R03-04-Airplane Engine Steady.wav**, **craigsmith**, CC0.
   - https://freesound.org/people/craigsmith/sounds/479512/
   - License: https://creativecommons.org/publicdomain/zero/1.0/
   - Public HQ MP3 preview used, downloaded 2026-09-29.
   - Author describes a vintage prop aircraft or helicopter effect, digitized
     from historic Hollywood/USC effects. Exact engine type is not established.

Adaptations: cuts, resampling, lowered pitch, bandpass EQ, subtle saturation,
crossfaded loops and peak mastering with `audio/build_engine_audio.py`.
Runtime: two layers, RPM ramp, radial-velocity Doppler, distance gain and fades.
This is a designed game engine sound, not an authentic recording of this fighter.
Include this attribution with distributed builds; no endorsement is implied.
