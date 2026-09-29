# Hayabusa — second type d'ennemi

Interprétation low poly inspirée du Ki-43 et de la planche
`art/enemies/hayabusa/hayabusa-reference-v01.png`.

## Livrables

- `hayabusa-studio.blend` : géométrie modifiable, matériaux, référence et HDR intégrés.
- `hayabusa-pbr.blend` : version avec atlas UV et matériaux PBR portables.
- `hayabusa.glb` : modèle texturé avec hélice séparée pour animation.
- `../../art/enemies/hayabusa/textures/v01/` : texture source imagegen et cartes
  PBR 2048 × 2048 (basecolor, roughness, metallic, normal) calculées dans Blender.
- `../../renders/hayabusa/` : trois rendus Cycles 2200 × 2200, 96 échantillons,
  débruitage, et planche comparative.

## Construction et matériaux

Fuselage affiné, ailes profilées, empennages, verrière à montants, capot et moteur
radial simplifié, hélice tripale et portes de train fermées. Livrée aluminium
mouchetée d'olive, capot sombre, cocardes, bande ivoire et marquage bordeaux.
Les proportions et détails sont une interprétation de jeu de la référence.

La texture source est créée avec imagegen, guidé par la planche ; son prompt est
conservé à côté. Les bandes sont affectées aux surfaces par UV. Les cocardes et
marquages sont construits sur le modèle puis intégrés dans l'atlas final.
Les normales proviennent du microrelief des matériaux, pas d'une sculpture haute
résolution. Les UV de peinture et les UV de cuisson sont distincts.

Studio : HDR `../studio_small_07_4k.exr` et quatre grandes sources de lumière.
Trois caméras : dessus, dessous et trois quarts avant. Nez orienté vers -Y dans
Blender, +Z dans le GLB ; haut +Y dans le GLB.

## Reproduction

Depuis la racine, avec Blender 4.5.4 :

```powershell
& tools/blender-4.5.4-windows-x64/blender.exe -b -t 6 --python blender/hayabusa/build_hayabusa.py
& tools/blender-4.5.4-windows-x64/blender.exe -b blender/hayabusa/hayabusa-studio.blend -t 6 --python blender/hayabusa/bake_export.py
& tools/blender-4.5.4-windows-x64/blender.exe -b blender/hayabusa/hayabusa-studio.blend -t 6 --python blender/hayabusa/verify_hayabusa.py
& blender/hayabusa/make_board.ps1
```

L'export est intégré au jeu dans les vagues paires : arrivée latérale, tonneau et attaque en courbe.
