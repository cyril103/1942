# Texture du terrain d'assaut

Asset : `assault-ground-detail.png`

- Création originale avec l'outil ImageGen intégré, le 7 octobre 2026.
- Source générée : `C:/Users/cyril/.codex/generated_images/01a11361-40b1-7b33-b70c-f1ea18a2bb11/exec-a67bc73a-ede8-4db1-bce6-94a3ccd539a6.png`.
- Aucune image de référence externe, aucune retouche ni normal map artificielle.
- Résolution effectivement retournée : 1254 × 1254 pixels, PNG RGB opaque. La requête demandait idéalement 2048 × 2048 ; aucun agrandissement artificiel n'a été appliqué.
- Usage : albedo de détail pour le terrain 3D des missions d'assaut. Éclairage neutre, terre/graviers fins et herbe rase ; le shader de terrain doit garder la modulation sobre pour préserver les silhouettes et projectiles.
- La génération est demandée répétable sur les deux axes. Le raccord en rendu devra être vérifié ; ne pas confondre la demande de seamless avec une garantie mathématique de continuité.

## Prompt exact

```text
Use case: photorealistic-natural
Asset type: production game terrain PBR albedo / base-color texture, a single seamless repeatable square tile.
Primary request: Create a highly detailed realistic overhead tropical airfield ground texture covering roughly 6 by 6 metres of ground. Dense short cropped olive grass in irregular subtle patches blends into compacted sandy earth and tiny fine gravel, with natural fine surface variation. This is the diffuse colour texture to apply to 3D terrain in a polished WWII aerial action game.
Composition/framing: perfectly orthographic straight-down plan view, ground extends edge to edge, no perspective, no horizon. Uniform texel scale throughout. Square image, ideally 2048 by 2048 pixels. Match opposite edges for seamless wrapping on both axes; no focal point or obvious repeating motif.
Lighting/mood: neutral diffuse overcast illumination, physically plausible albedo, evenly lit, flat illumination. No baked directional light, no cast shadows, no ambient occlusion, no specular highlights.
Color palette: muted olive / grey-brown / sandy tan. Restrained low macro contrast for excellent visibility of aircraft and enemy projectiles above it. Keep local fine texture rich, avoid strongly dark or bright patches.
Materials/textures: fine short grass, compact fine granular soil, tiny neutral gravel. Ground stays almost flat.
Constraints: one complete opaque colour texture only, no swatches or texture sheet layout, no labels or captions, no border, no objects, no buildings, no vehicles, no people, no roads, no airstrip markings, no footprints, no rocks larger than gravel, no shrubs, no water, no scenery, no vignette. Not a beauty render, not a normal map or height map. No text, logos or watermark.
```
