# Batterie antiaérienne mobile

Modèle original procédural préparé pour Pacific Strike dans
`blender/ground-forces/build_mobile_aa.py`. Le châssis compact à six roues, la
cabine, le plateau et les doubles canons sont construits avec des primitives
Blender, sans modèle tiers téléchargé. Deux meshes exportés : `Hull` et `Turret`.

Le modèle réutilise `field-material-atlas.png`, les UV `FieldUV` et les couleurs
de sommet `FieldFinish` des installations militaires existantes. La provenance
de cet atlas est documentée dans le fichier `CREDITS.md` du même dossier.
Les matériaux sont appliqués par le shader du jeu ; le GLB ne fournit pas un
nouveau matériau ou une nouvelle texture externe.

La variante de gameplay reste `battery`, avec une empreinte de collision de
2,8 × 2,8 et les mêmes règles de dégâts et de blindage. Le générateur refuse un
modèle au-dessus de 2 200 triangles et contrôle l'encombrement de sa tourelle.
La génération CPU a produit 1 768 triangles et deux surfaces, pour un
encombrement de 1,742 × 2,334 × 1,495. Le rapport
`blender/ground-forces/battery-mobile-build-report.json` consigne ces mesures.
Le GLB conserve les normales, UV et couleurs de sommet, sans fichier externe.
Ces contrôles ne constituent pas une validation visuelle en jeu ni une promesse
de FPS.
