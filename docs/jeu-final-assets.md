# Assets de campagne

## Révision dynamique

La musique active est désormais **5 Chiptunes (Action)** de **Juhani Junkala / SubspaceAudio**, CC0 : https://opengameart.org/content/5-chiptunes-action. Les cinq fichiers sont normalisés à une crête de 0,75 par `audio/build_action_music.py` sans changement de tempo. Attribution et notice de l'artiste dans `game/assets/campaign/music/`.

Les trois icônes SVG des bonus sont dessinées pour le projet dans `game/assets/campaign/icons/`. Le laser utilise un shader additif original, un rayon physique et une boucle sonore originale d'une seconde. Les explosions gardent les samples crédités, avec un master raccourci à 1,9 s et une animation de 1,35 s.

La liste ci-dessous décrit les assets de la première version ; ses musiques procédurales ont été remplacées par les morceaux ci-dessus.

Les avions, textures, animations, samples et effets précédemment validés restent utilisés. Cette campagne ajoute :

- `game/assets/campaign/title-ocean.png` : illustration d'accueil, créée avec l'outil imagegen intégré. Prompt conservé dans `title-prompt.txt`.
- `sector-islands.png` : atlas RGBA de volcan, archipel arctique, port et piste de jungle. Prompt `sector-islands-prompt.txt`. Le shader existant assure les faibles profondeurs et le raccord à l'océan.
- `material-atlas.png` : atlas de pont bois, acier naval, peinture aéronautique et mécanique. Prompt `material-prompt.txt`. Projection triplanaire sur les nouveaux modèles.
- `models/destroyer.glb`, `battleship.glb`, `carrier.glb` : modèles construits par le script Blender du projet, avec tourelles, superstructures, ponts et détails lisibles de dessus.
- `models/fortress.glb` : adaptation du bombardier texturé existant à six moteurs. Sources `.blend` dans `blender/campaign/`.
- `music/menu.wav`, `flight.wav`, `boss.wav` : compositions synthétiques originales de `audio/build_campaign_music.py`, bouclées et fondues par `scripts/campaign/music.gd`.
- Shaders `campaign_surface`, `campaign_weather`, `naval_wake` : surfaces, nuages/pluie/neige/cendres et sillages.

Les images ont été générées avec l'outil intégré. Les prompts sont des fichiers de production exclus de l'exécutable.

Les samples du prototype gardent leurs attributions dans `game/assets/audio/{engine,weapons}/CREDITS.md`. Les licences des polices sont dans `game/assets/ui/fonts/`. La distribution ajoute les notices officielles Godot 4.7.2 et ses dépendances, conservées dans `docs/licenses/`.

Référence de conception : attaques chargées et rythme arcade de 1942: Joint Strike. Aucun asset du jeu de référence n'a été extrait.
