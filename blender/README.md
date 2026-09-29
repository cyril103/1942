# Avion joueur — modèle et studio Blender

Ouvrir `avion-joueur-studio.blend` avec Blender 4.5 ou ultérieur.

## Livrables

- Modèle modifiable organisé dans la collection AIRCRAFT.
- Trois caméras : 01 DESSUS, 02 DESSOUS, 03 TROIS QUARTS.
- Éclairage Cycles : HDR studio 4K et quatre grandes sources de studio.
- Images PNG de 2200 × 2200 pixels dans ../renders.
- Planche comparative dans ../renders/planche-avion-studio.png.
- Script reproductible : build_aircraft.py ; --preview produit des contrôles à 900 pixels.

## Construction et matériaux

Fuselage à sections elliptiques, ailes profilées, empennages solides, capot ouvert et moteur radial simplifié. La verrière utilise des panneaux distincts et des montants géométriques. Les trois pales sont parentées à PROPELLER, pour une future animation autour de l'axe Y.

Les deux textures sources sont utilisées : bandes de peinture sur les surfaces principales ; atlas sur les insignes des ailes et sur les hélices. Les insignes sont projetés séparément pour conserver leurs proportions. Les panneaux ont des joints géométriques discrets. Cette réinterprétation des UV évite d'étirer l'atlas préliminaire sur le modèle. Les détails ne reproduisent pas chaque trait de la planche conceptuelle.

La planche de référence, les textures et le HDR sont intégrés au fichier .blend. La référence se trouve dans une collection masquée. Le HDR provient du fichier local D:/hdrs/studio_small_07_4k.exr ; une copie est conservée à côté du projet. Les droits de redistribution du HDR local n'ont pas été vérifiés.

L'avion pointe vers -Y ; X est l'envergure et Z la verticale. Les vues dessus et dessous montrent le nez en haut. Le fond neutre est réservé aux rayons caméra : le HDR éclaire et produit réellement les reflets.

## Reproduction

Depuis PowerShell :

```powershell
& 'C:/ChatGPT/1942/tools/blender-4.5.4-windows-x64/blender.exe' -b -t 6 --python 'C:/ChatGPT/1942/blender/build_aircraft.py'
```

Blender portable téléchargé depuis https://download.blender.org/release/Blender4.5/blender-4.5.4-windows-x64.zip ; les installations existantes n'ont pas été modifiées.

## Portée

Modèle de présentation à géométrie facettée, destiné à servir de base au jeu. Pas encore un asset exporté et validé dans un moteur : conversion des courbes de joints, regroupement des matériaux, gestion des decals, collisions, LOD et test à la taille d'affichage restent à faire lors de l'intégration. Aucun résultat de bake normal/AO n'est revendiqué. Les statistiques du rapport concernent les maillages de base et excluent les courbes et la géométrie ajoutée par les modificateurs.
