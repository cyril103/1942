# Pacific Strike Ultimate 2.3 — Campagne 1942

Campagne solo de **32 missions** sous Godot 4.7.2, sur la branche `jeu_toppissime` : huit secteurs, huit combats de boss à trois phases, avions 3D low poly, océan et raids terrestres. Le jeu occupe toute la largeur avec deux fines bandes de HUD, soit 90 % de la surface de l'écran. Menus, hangar, améliorations permanentes, trois difficultés, médailles et sauvegarde automatique.

## Lancer

Version **2.3.0 Ultimate** : jeu disponible en **français et en anglais**.
Choisir « Français / English » à l'accueil, ou **Options > Langue / Language**.
Le changement est immédiat, y compris depuis la pause, et mémorisé dans le profil.
Les anciennes sauvegardes conservent le français et toute leur progression.
Les catalogues sont dans `game/data/localization/` ; la traduction couvre menus,
missions, radio, HUD, raids, équipements, aides et résultats.
Manuel anglais : `docs/player-guide-en.txt` (livré aussi dans la distribution).
Validation : `docs/validation/localisation-2.3.txt`. Maintenance des traductions :
`docs/localisation.txt`.

Version **2.2.0 Ultimate** : écume animée le long des plages et des rochers,
ressac irrégulier, reflets de houle et nuages dispersés sur toute la largeur.
Les nuages sont décoratifs et leur placement ne dépend plus des routes des navires.
Les traits prédictifs des boss ont été retirés ; le HUD et la charge locale
annoncent toujours leurs attaques. Validation : `docs/validation/atmosphere-2.2.txt`.

La version conserve les ajouts **2.1** : mer à grandes houles et reflets, relief géométrique des
îles, éclairage propre à chaque secteur, surfaces métalliques et ombres aériennes,
explosions en feu et fumée, hangar avec les trois appareils en 3D et inspection
interactive. Les réglages de réduction des flashes et des mouvements restent actifs.
Validation visuelle et performances : `docs/validation/presentation-2.1.txt`.

La version conserve les ajouts **2.0** : huit familles de boss avec motifs propres,
attaques annoncées dans le HUD et rafales espacées ; **Boss Rush** de huit duels avec vies partagées
et records par avion ; **frôlements** récompensés (+25 points et jusqu'à +0,6 % de
charge par projectile évité) ; HUD de boss à trois phases, guide du pilote,
accueil animé et tir automatique facultatif dans Options > Commandes.

Le Boss Rush utilise un équipement fixe et n'avance pas la campagne. Le blindage
et les bombes sont restaurés entre les duels ; score et vies restent communs.
Le record est validé seulement après les huit victoires. Les sauvegardes 1.x restent
compatibles, sans modifier les commandes ni activer le tir automatique par défaut.
Voir `docs/validation/ultimate-2.0.txt` pour les validations et leurs limites.

Correctif **1.10.1** : préparation des matériaux et effets sous un écran de chargement
avant le décollage. Le jeu reste figé pendant cette préparation, puis le vol démarre
normalement. Voir `docs/validation/fluidite-1.10.1.txt` pour les mesures comparatives.

Version **1.10** : bonus de vague parfaite animé dans la scène, impacts à étincelles,
signatures visuelles des trois capacités, laser retravaillé et nouveaux paysages
volcaniques/arctiques. Les rochers occupent aussi les espaces libres au centre des
raids, en gardant les routes et installations dégagées. Voir
`docs/validation/finition-1.10.txt` pour les contrôles et limites.

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

Les tests se lancent sans son et avec un profil isolé via
`./Tester-Silencieux.ps1 -Script res://tests/test_combat.gd` (ou un autre `test_*.gd`).
Ajouter `-Rendered` pour les contrôles avec rendu GPU. Toute invocation directe
de Godot pour un test doit inclure `--audio-driver Dummy`. Le volume du joueur
n'est pas modifié. La préparation audio utilise Python avec NumPy,
SciPy et SoundFile. Les chemins des outils dans les lanceurs correspondent à
l'installation locale et peuvent devoir être adaptés sur une autre machine.
