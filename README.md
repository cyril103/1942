# Pacific Strike — Campagne 1942

Campagne solo de **32 missions** sous Godot 4.7.2, sur la branche `codex/jeu-final` : huit secteurs, huit combats de boss à trois phases, avions 3D low poly, décor océanique 2D et cockpit 3:4. Menus, hangar, améliorations permanentes, trois difficultés, médailles et sauvegarde automatique.

## Lancer

Ouvrir `game/project.godot` avec Godot 4.7.2, puis lancer la scène principale.
Sur cette machine, `Jouer.cmd` et `Jouer.ps1` lancent le projet. `Jouer-Final.cmd` lance la distribution autonome `dist/PacificStrike/PacificStrike.exe`, sans installation de Godot.

- Flèches / WASD / ZQSD : déplacement ; Espace maintenu : tirs ; Maj : précision.
- X : bombe ; C : frappe spéciale à 100 % ; Échap : pause / retour, puis quitter depuis l'accueil.
- Manette : stick ou croix, A pour tirer, B pour la bombe, X pour la frappe, LB pour la précision, Start pour la pause.
- Détruire les cinq avions rouges puis ramasser le POW débloque quatre tirs en éventail.

Le briefing indique l'objectif principal et les conditions de maîtrise pour l'or. Les premières victoires et les meilleures médailles donnent des pièces pour le hangar. Trois configurations du même avion privilégient polyvalence, vitesse ou résistance. La campagne traverse récifs, convois, mousson, mangroves, volcans, crépuscule et mer arctique.

La progression reprend au début de la mission débloquée, sans sauvegarde en plein vol. Le fichier `pacific-campaign-v1.json` est dans le dossier utilisateur Godot du jeu, avec copie `.bak`. Les niveaux restent rejouables. Nouvelle campagne demande confirmation et conserve options et record.

`Exporter-Windows.ps1` reconstruit l'exécutable et le ZIP. Il utilise les templates officiels 4.7.2 dans `tools/godot-export/templates/`. La distribution contient les licences et les crédits.

## Contenu

- `game/` : projet jouable, assets, shaders et tests.
- `art/` : références, textures et prompts de génération.
- `blender/` : modèles modifiables, studio et scripts de construction/export.
- `audio/` : scripts de préparation, sources utilisées et captures du mix.
- `renders/` : planches studio et captures de validation.

Les 32 chronologies sont dans `game/data/missions.json`, le système de campagne dans `game/scripts/campaign/`. Les sources des nouveaux modèles sont dans `blender/campaign/`, celles des musiques dans `audio/build_campaign_music.py`.

Manuel : `docs/manuel-joueur.txt`. Validation : `docs/jeu-final-validation.md`. Provenance : `docs/jeu-final-assets.md`. Les notes du prototype restent dans `game/README.md` et les README Blender.
Les crédits des samples sont conservés dans `game/assets/audio/`.
Les outils portables, environnements Python et caches ne sont pas versionnés.

Les tests Godot se lancent avec `--headless --path game --script res://tests/test_combat.gd`
(ou un autre script `test_*.gd`). La préparation audio utilise Python avec NumPy,
SciPy et SoundFile. Les chemins des outils dans les lanceurs correspondent à
l'installation locale et peuvent devoir être adaptés sur une autre machine.
