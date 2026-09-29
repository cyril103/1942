# Zero — chasseur ennemi

Modèle inspiré du Zero pour le shmup, suivant la planche `art/enemies/zero/zero-reference.png`.
Il s'agit d'une interprétation de jeu, pas d'une reconstitution technique d'une variante historique précise.

## Livrables

- `zero-studio.blend` : modèle modifiable, texture source, référence et HDR intégrés ; trois caméras.
- `zero-pbr.blend` : version avec atlas UV et matériaux PBR portables.
- `zero.glb` : avion texturé, hélice séparée pour animation ; aucune logique d'ennemi ajoutée au jeu.
- `../../renders/zero/01-dessus.png`, `02-dessous.png`, `03-trois-quarts.png` : vrais rendus Cycles 2200 × 2200, 128 échantillons et débruitage.
- `../../renders/zero/planche-zero-studio.png` : planche des trois rendus.
- `../../art/enemies/zero/textures/v01/` : peinture source et atlas PBR 2048 pixels (basecolor, roughness, metallic, normal).

## Construction

Fuselage effilé, ailes profilées avec dièdre et extrémités arrondies, capot radial sombre,
verrière allongée à montants géométriques, empennages, portes de train fermées et hélice tripale.
Les cocardes sont projetées sur les surfaces indépendamment des UV de peinture, puis intégrées à l'atlas exporté.
Les panneaux conservent un niveau de détail adapté au jeu vu de dessus.

La texture de peinture a été créée avec image_gen intégré, guidé par la planche.
Les deux prompts complets sont conservés dans `../../art/enemies/zero/generation-prompts.json`.
Les cartes PBR sont calculées dans Blender à partir du véritable modèle et de ses matériaux.
La normale encode le microrelief des matériaux ; elle ne provient pas d'une sculpture haute résolution.
Les UV sources et les UV de destination du bake sont distincts.

## Éclairage et axes

HDR studio 4K local `../studio_small_07_4k.exr`, plus quatre grandes sources.
Fond neutre réservé aux rayons caméra, HDR réel pour l'éclairage et les reflets.
Le HDR est intégré aux fichiers Blender. Sa provenance externe et ses droits de redistribution
n'ont pas été vérifiés ; il n'est pas inclus dans le GLB.

Dans Blender : nez -Y, envergure X, haut Z. Après export glTF : nez +Z, haut +Y.
Les caméras orthographiques dessus et dessous ont toutes deux le nez vers le haut de l'image.

## Reproduction

Blender 4.5.4 portable du projet :

```powershell
& '../../tools/blender-4.5.4-windows-x64/blender.exe' -b -t 6 --python build_zero.py
& '../../tools/blender-4.5.4-windows-x64/blender.exe' -b zero-studio.blend -t 6 --python bake_export.py
```

`-- --preview` après le script de construction produit les contrôles à 900 pixels.
`make_board.ps1` assemble les trois rendus sans en modifier le contenu.
Les statistiques réelles sont conservées dans `build-report.json` et `export-report.json`.
