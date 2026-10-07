# Pacific Strike — Campagne 1942

Campagne solo de **32 missions** sous Godot 4.7.2, sur la branche `jeu_toppissime` : huit secteurs, huit combats de boss à trois phases, avions 3D low poly, océan et raids terrestres. Le jeu occupe toute la largeur avec deux fines bandes de HUD, soit 90 % de la surface de l'écran. Menus, hangar, améliorations permanentes, trois difficultés, médailles et sauvegarde automatique.

## Lancer

Ouvrir `game/project.godot` avec Godot 4.7.2, puis lancer la scène principale.
Sur cette machine, `Jouer.cmd` et `Jouer.ps1` lancent le projet. `Jouer-Final.cmd` lance la distribution autonome `dist/PacificStrike/PacificStrike.exe`, sans installation de Godot.

- Flèches / WASD / ZQSD : déplacement ; Espace maintenu : tirs ; Maj : précision.
- X : bombe ; C : frappe spéciale à 100 % ; Échap : pause / retour, puis quitter depuis l'accueil.
- Manette : stick ou croix, A pour tirer, B pour la bombe, X pour la frappe, LB pour la précision, Start pour la pause.
- Détruire les cinq avions rouges fait apparaître un bonus à icône : éventail cyan, laser violet ou vie supplémentaire verte. Chaque bonus remplace le précédent. La vie est acquise immédiatement et rétablit le tir standard ; elle n'est pas retirée au bonus suivant.

Les missions proposent 19 à 35 rencontres avec des vagues de huit chasseurs, des trajectoires réparties sur la largeur et des renforts pendant les boss. Chaque mission commence par un décollage du porte-avions et se termine par un appontage animé. Les explosions sont plus brèves et la bande originale utilise les morceaux d'action CC0 de Juhani Junkala, crédités dans le jeu.

Le score total, les vies restantes et l'arme équipée sont conservés entre les missions. Le bilan distingue le total de la partie des points de la mission. Recommencer une mission reprend son état de départ sauvegardé : cela évite de dupliquer les points d'une tentative abandonnée. Les anciennes sauvegardes sont compatibles ; leur total initial est reconstitué à partir des scores enregistrés.

Le briefing indique l'objectif principal et les conditions de maîtrise pour l'or. Les premières victoires et les meilleures médailles donnent des pièces pour le hangar. Trois avions, Vanguard, P-38 Interceptor et Corsair Bulwark, privilégient polyvalence, vitesse ou résistance. La campagne traverse récifs, convois, mousson, mangroves, volcans, crépuscule et mer arctique.

La version 1.8 distingue les huit raids par leurs infrastructures, réseaux radar et objectifs. Le plan de briefing montre les priorités ; le quota et les cibles obligatoires doivent être accomplis ensemble. Les batteries mobiles annoncent leur trajet et cessent de tirer pendant le déplacement. Le basalte et la neige utilisent des textures natives, avec routes et pistes intégrées au terrain. Les validations et leurs limites sont décrites dans `docs/validation/raids-1.8.txt`.

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
