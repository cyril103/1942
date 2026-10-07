# Installations terrestres — révision visuelle

Modélisation originale Blender 4.5.4 pour Pacific Strike. Les cinq assets sont fabriqués par le script reproductible `blender/ground-forces/build_ground_forces.py`, à partir de silhouettes fonctionnelles de matériels de campagne de la période 1940. Ce sont des représentations artistiques, sans revendication de reproduction exacte d'un modèle historique.

- `battery.glb` : affût double, boucliers, culasses, optique, volants de pointage, douilles, caisses et sacs de sable. 3 028 triangles.
- `bunker.glb` : casemate à murs biseautés, embrasure, porte blindée, aérateurs, tourelle et mitrailleuses. 1 516 triangles.
- `radar.glb` : pylône réellement ajouré et triangulé, antenne dipolaire tournante, échelle, cabine radio et groupe électrogène. 2 764 triangles.
- `fuel.glb` : citernes rivetées avec bandes, échelles, évents, réseau de conduites, pompes et vannes. 4 308 triangles.
- `runway.glb` : hangar cintré ouvert, nervures, tour vitrée, camion de service, caisses, fûts et manche à air. 4 159 triangles.

Chaque asset emploie deux meshes opaques, chacun avec une seule surface. La texture et le shader sont communs aux installations. Les GLB incluent UV, normales, et couleurs de finition (alpha = métal), et le moteur attache l'atlas externe pour ne pas dupliquer cinq fois la même texture en mémoire. Le `.blend` source contient les matériaux complets et l'atlas embarqué.

Les objets sont posés individuellement au sol : aucune grande dalle rectangulaire ne simule une fondation. Les empreintes de collision du gameplay sont conservées. Le pied visuel est ajusté par `set_visual_altitude(base_y)` sans déplacer les colliders logiques.

## ImageGen intégré : atlas original

Fichier : `field-material-atlas.png`. Généré avec l'outil ImageGen intégré, puis mappé explicitement dans Blender. Aucun échantillon téléchargé n'est employé dans cet atlas.

Prompt final :

> Use case: stylized-concept. Asset type: square 2048 by 2048 physically based video game material albedo atlas, six equal rectangular panels in 3 columns and 2 rows, fully edge to edge with absolutely no borders or text. Completely flat perpendicular orthographic surface scans, NO object renders, NO lighting baked into material, NO shadow, NO labels. Intended for realistic WWII tropical Pacific Japanese ground military models. Top row left: warm faded olive green painted steel with thin seam lines, occasional fine rivets and subtle bright edge chips and tiny oxidation patches; top row middle: sun-warmed gray beige poured bunker concrete with aggregate, small cracks, rain stains and slight moss, detailed natural surface not too dark; top row right: aged desaturated blue gray galvanized corrugated steel roof, tightly spaced parallel ridges vertical, subtle rust, pleasing medium tone. Bottom row left: woven khaki sandbag canvas, detailed rough textile weave, dirt streaks, slight golden sun bleaching; bottom row middle: gunmetal blackened brushed steel with polished wear, medium dark gray, readable rather than black; bottom row right: weathered rich brown wooden boards, fine grain, screws, faded field crates. Rich nuanced clean realistic texture fidelity with micro surface detail, coherent physically plausible saturated-but-natural palette, high-end game scanned materials. No words, no logos, no checkerboard, no vignettes, no cast shadows. Each panel strictly occupies one third image width and one half image height.

## Rendu de contrôle

`renders/ground-forces-studio.png` est un vrai rendu Cycles des meshes de production avec le HDRI existant `blender/studio_small_07_4k.exr` (Poly Haven, CC0, déjà livré et crédité dans le projet), deux éclairages de studio et aucune illustration substituée aux modèles. Source : `blender/ground-forces/ground-forces-studio.blend`.

Reproduction :

```powershell
& tools/blender-4.5.4-windows-x64/blender.exe --background --threads 4 --python blender/ground-forces/build_ground_forces.py -- --render
```
