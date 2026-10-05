# Bombardier japonais bimoteur

Modèle low poly construit dans Blender à partir de `art/enemies/bomber/bomber-reference-v01.png`. Interprétation pour le jeu : fuselage allongé, nez vitré, cockpit à montants, deux nacelles radiales, hélices tripales, ailes effilées et empennage à dérive unique. Train et soute fermés.

## Livrables

- `bomber-studio.blend` : géométrie modifiable, matériaux source, planche de référence et environnement HDR intégrés.
- `bomber-pbr.blend` : modèle avec atlas UV et cartes PBR portables, studio et caméras conservés.
- `bomber.glb` : 6 830 triangles, trois maillages, trois textures embarquées (couleur, normal, rugosité/métal combinés).
- `../../art/enemies/bomber/textures/v01/` : source de peinture générée avec l'outil ImageGen intégré, prompt et quatre cartes PBR 2048 × 2048 calculées dans Blender.
- `../../renders/bomber/01-dessus.png`, `02-dessous.png`, `03-trois-quarts.png` : rendus du modèle PBR dans Cycles, 2200 × 2200, 96 échantillons, débruitage.

Les UV source et UV de cuisson sont distincts. Cocardes et bandes d'identification sont construites sur le modèle puis cuites dans la couleur. Les normales reproduisent le microrelief des matériaux, sans prétendre à une cuisson de sculpture haute résolution. Le verre du modèle de jeu est opaque et sombre, avec une faible rugosité pour ses reflets. La version studio source conserve son matériau de verrière distinct.

## Orientation et animation

Nez vers -Y et haut +Z dans Blender ; nez +Z et haut +Y dans le GLB. Maillages `Bomber_Airframe`, `Bomber_Propeller_L` et `Bomber_Propeller_R`. Pivots des hélices à (±2,62 ; -5,30 ; -0,04) dans Blender, axes longitudinaux. Envergure de 17 unités avant mise à l'échelle dans le jeu. Le bombardier n'est pas encore ajouté aux vagues.

## Studio

Environnement local `../studio_small_07_4k.exr`, déjà utilisé pour les autres avions, intégré aux fichiers Blender ; quatre grandes sources de lumière complètent l'éclairage. La présente étape réutilise ce fichier local sans nouvelle vérification de sa provenance. Fond gris neutre indépendant de l'éclairage HDR. Vues dessus et dessous orthographiques à échelle identique ; troisième caméra en trois quarts avant.

## Reproduction depuis la racine du dépôt

```powershell
& tools/blender-4.5.4-windows-x64/blender.exe -b -t 6 --python blender/bomber/build_bomber.py
& tools/blender-4.5.4-windows-x64/blender.exe -b blender/bomber/bomber-studio.blend -t 6 --python blender/bomber/bake_export.py
& tools/blender-4.5.4-windows-x64/blender.exe -b blender/bomber/bomber-pbr.blend -t 6 --python blender/bomber/render_pbr.py
& tools/blender-4.5.4-windows-x64/blender.exe -b blender/bomber/bomber-pbr.blend -t 6 --python blender/bomber/verify_bomber.py
```

`verification.json` confirme la réimportation GLB, les UV, les textures intégrées, les trois maillages, le budget de triangles et les pivots des hélices. Les rendus finaux sont contrôlés visuellement après cuisson.
