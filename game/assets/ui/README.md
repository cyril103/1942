# Cockpit / proposition 02

Interface intégrée dans `res://scenes/cockpit.tscn`, scène principale du projet.

## Ressources

- `cockpit-metal.png` : métal olive/noir produit avec l'outil intégré ImageGen à partir de la proposition choisie. Prompt : `texture-prompt.txt`. Surface sans texte ; le shader réduit son contraste derrière les instruments.
- `fonts/BlackOpsOne-Regular.ttf` : titre au pochoir, Google Fonts, licence SIL OFL fournie.
- `fonts/BarlowCondensed-Medium.ttf` : libellés et commandes, Google Fonts, licence SIL OFL fournie.
- `fonts/DSEG7Classic-Regular.ttf` : chiffres sept segments, DSEG v0.46, licence SIL OFL fournie.
- Rivets, bordures, silhouettes et cadran : dessin vectoriel Godot dans `scripts/ui/cockpit_panel.gd`.

Sources :
- https://github.com/google/fonts/tree/main/ofl/blackopsone
- https://github.com/google/fonts/tree/main/ofl/barlowcondensed
- https://github.com/keshikan/DSEG/releases/tag/v0.46

## Shaders CanvasItem

`panel_metal.gdshader` : éclairage doux et assombrissement des bords.
`stencil_paint.gdshader` : usure statique de la peinture du titre.
`instrument_glass.gdshader` : reflet et lignes d'affichage ; lueur et segments inactifs dessinés dans l'instrument.
`radar.gdshader` : grille, balayage et cartographie de l'atlas des îles avec positions et rotations réelles. Contacts projetés depuis la caméra du jeu.

## Comportement

SubViewport indépendant au rapport 3:4 exact : 810 × 1080 à 1920 × 1080, panneaux de 555 pixels. Collisions, limites et apparitions utilisent ce viewport. Les fenêtres très étroites conservent l'ensemble du cockpit avec des bandes libres en haut et en bas.

100 points par ennemi détruit. Record dans `user://pilot-record.cfg`. Trois vies ; réapparition après 2,2 secondes puis protection de 3 secondes signalée par clignotement. Défaite finale à zéro vie. Vagues alternées de quatre appareils toutes les 20 secondes de combat actif. Affichage du score, record, vies, vagues, appareils abattus, compte à rebours et inclinaison.

Flèches : piloter. Espace : tirer. R : nouvelle partie. Échap : quitter.

## Validation

`tests/test_cockpit.gd` : 56 contrôles, formats 16:9/ultralarge/5:4/portrait, limites des ailes, collision réelle dans le SubViewport, score et sauvegarde isolée, vies, protection, redémarrage et clavier.
Régressions : `test_combat.gd`, `test_flight.gd`, `test_departure.gd`.
`tests/capture_cockpit.gd` : captures GPU du décollage, du combat et de la défaite dans `renders/cockpit-*.png`. Vérifiées sous Godot 4.7.2 / OpenGL Compatibility / GTX 1650.
