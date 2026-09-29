# 1942 — Premier vol



Première scène jouable sous **Godot 4.7.2**, utilisant le véritable avion 3D créé dans Blender et les textures préparées pour ce projet.



## Jouer



Double-cliquer sur `../Jouer.cmd`. Le lanceur utilise l'installation existante :

`D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe`.



Ou ouvrir `project.godot` dans Godot 4.7.2 puis appuyer sur **F5**.



- **Flèches** : déplacer l'avion ; les diagonales sont normalisées.

- **Gauche / droite** : inclinaison progressive de 28° maximum, puis retour à plat au relâchement.

- **Échap** : fermer le jeu.



Le jeu démarre en plein écran, avec une caméra orthographique de dessus (cadrage de 25 unités). Une introduction de 8,95 secondes fait partir l'avion de l'arrière d'un porte-avions : accélération sur le pont, décollage, montée, looping 3D complet, puis reprise du pilotage. Les flèches sont verrouillées pendant la manœuvre ; Échap fonctionne dès le départ. Un océan animé et quatre variantes d'îles défilent du haut vers le bas. Après le décollage, Espace permet de tirer et des vagues de deux Zero arrivent toutes les 20 secondes.



## Organisation



- `scenes/main.tscn` : scène éditable, caméra, éclairage et avion.

- `scripts/player.gd` : déplacement, inclinaison et limites calculées à partir des dimensions réelles du modèle, avec une marge de 12 pixels du viewport.

- `scripts/departure.gd` : séquence de départ, altitude, échelle visuelle, boucle verticale et restitution des commandes.

- `assets/environment/carrier.png` : porte-avions 2D transparent, avec son prompt dans `carrier.prompt.txt`.

- `scripts/main.gd` : contrôles, fermeture, gestion de perte de focus et capture de contrôle.

- `scripts/seascape.gd` : océan et six îles recyclées, vitesse commune de 2,4 unités/seconde, positions et tailles variées.

- `shaders/ocean.gdshader` : deux couches de vagues, raccords par fondu des bords de texture, ondulations et reflets discrets.

- `shaders/island.gdshader` : lecture de l'atlas 2×2, transparence côtière et animation légère des eaux peu profondes.

- `shaders/ocean_surface.gdshaderinc` : calcul commun de l'eau pour l'océan et les côtes, avec des coordonnées et phases identiques au raccord.

- `assets/environment/` : texture d'océan et atlas d'îles PNG à leur résolution native de 1254×1254, avec les prompts de génération.

- `assets/aircraft.glb` : export du fichier Blender, textures incluses, géométrie regroupée en 12 maillages par matériau (16 158 triangles après conversion des courbes et biseaux).

- `../blender/export_godot.py` : export reproductible, sans modifier la scène Blender d'origine. Les réglages de couleur et le masque des insignes sont convertis en textures compatibles glTF.



Les deux textures d'origine sont utilisées. Les textures de jeu sont des dérivés ; les originaux sont conservés dans `../art/aircraft/textures/v01`. L'éclairage temps réel utilise deux lumières directionnelles et une ambiance colorée. Aucun HDR externe n'est requis pour jouer.



## Vérifications



```powershell

& 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:/ChatGPT/1942/game' --editor --import

& 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:/ChatGPT/1942/game' --script 'res://tests/test_flight.gd'

```



Le test envoie des événements clavier au moteur, vérifie le mouvement, la vitesse diagonale, le sens du roulis, le retour à plat, les limites aux quatre bords et aux quatre coins, plusieurs formats d'écran, et la stabilité à différentes fréquences. Il termine en envoyant Échap ; un code de sortie 0 confirme la fermeture attendue. `tests/results.json` conserve le résultat.



Capture du viewport réel pour vérification visuelle :



```powershell

& 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe' --path 'C:/ChatGPT/1942/game' --windowed --resolution 1280x720 -- --capture-preview

```



La capture est enregistrée dans `../renders/godot-premier-vol.png`, puis la session de contrôle se ferme. Le lancement normal reste en plein écran.



API utilisées : [Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html), [Input](https://docs.godotengine.org/en/stable/classes/class_input.html). Version : [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/).



## Décor océanique



Les décors restent des images 2D sur des plans plats non éclairés, placés sous l'avion 3D. L'atlas contient une île boisée, un atoll, un îlot rocheux et une île allongée. Les PNG ont été créés avec l'outil image_gen intégré ; leur alpha natif est conservé. La séparation des quatre images et l'adoucissement des côtes se font dans le shader, sans recadrage destructif des sources.



Le raccord côtier utilise maintenant les mipmaps de l'alpha à deux échelles pour construire un fondu large et légèrement irrégulier. La couleur de l'eau turquoise rejoint exactement celle de l'océan animé avant la fin de l'alpha de l'image ; les plages et la végétation sont protégées par le masque de couleur. Les deux fichiers `.png.import` activent explicitement les mipmaps : conserver ce réglage, nécessaire au fondu et à la stabilité des détails. Le test vérifie leur présence dans les textures importées ainsi que la synchronisation des phases après recyclage.



Le même déplacement anime l'eau et les îles. La géométrie d'une île ne se déplace qu'une fois par tick ; seuls les détails de l'eau ont une animation relative. Les îles ne sont replacées qu'après leur sortie complète et reviennent au-dessus du cadre. Il n'y a jamais de création continue d'objets. Les phases des shaders restent bornées et leurs fonctions sont périodiques pour éviter les sauts lors des boucles.



Réglages exposés sur le nœud **Seascape** : vitesse, graine aléatoire, tailles et espacement. Le plan d'océan s'ajuste au format de l'écran. Le contrôleur de l'avion conserve ses limites d'écran et son inclinaison.



Test de 30 minutes simulées (recyclage, direction, synchronisation, formats d'écran et nombre constant d'objets) :



```powershell

& 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:/ChatGPT/1942/game' --script 'res://tests/test_seascape.gd'

```



Résultat conservé dans `tests/seascape-results.json`. Le script `tests/capture_seascape.gd` produit des captures GPU à quatre instants et une vue de survol d'île pour vérifier la composition et l'ordre d'affichage. Ces scripts sont des outils de développement ; le lancement normal utilise toujours `scenes/main.tscn`.



## Départ du porte-avions



Le porte-avions utilise une image RGBA créée avec l'outil image_gen intégré, conservée à sa résolution native de 887×1774 pixels. Un shader ajoute un sillage discret ; une ombre de contact accompagne le décollage. Le signal `Seascape.scrolled` donne au navire exactement le même déplacement que l'océan.



L'avion démarre à une altitude de -2,45, juste au-dessus du pont situé à -2,70. Le looping utilise une trajectoire circulaire dans le plan vertical YZ, de rayon 1,6, et une rotation de tangage complète de 360°. La projection orthographique ne changeant pas la taille avec l'altitude, une variation d'échelle mesurée rend la montée lisible. La taille et l'altitude habituelles sont rétablies à la fin.



Validation dédiée :



```powershell

& 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:/ChatGPT/1942/game' --script 'res://tests/test_departure.gd'

```



Le test couvre le départ sur le pont, la course, les phases, la rotation complète, l'altitude, les limites d'écran, le verrouillage puis le retour des commandes, la synchronisation du navire et Échap pendant l'introduction. Il utilise les formats 16:9 et portrait. Le rapport est dans `tests/departure-results.json`. Les captures GPU de `tests/capture_departure.gd` sont enregistrées dans `../renders/departure-00.png` à `departure-07.png`.





## Projectiles



` scripts/weapons.gd ` gère deux traceurs par salve, huit salves par seconde, à 32 unités/seconde. Leurs points de départ suivent les ailes inclinées ; ils avancent ensuite vers le haut. Les shaders `tracer.gdshader` et `bullet_impact.gdshader` produisent les traceurs, les lueurs de bouche et les éclats d’impact.



La réserve contient exactement 96 projectiles et huit effets d’impact, réutilisés sans création en cours de tir. Un projectile dont le centre sort du viewport est immédiatement masqué et désactivé. Il n’a plus de collision ni de déplacement et son emplacement est disponible pour un nouveau tir. Une durée maximale de trois secondes assure aussi sa récupération. Tout est libéré avec la scène.



Les collisions balaient le segment parcouru sur le plan Y=0. Les futurs ennemis doivent utiliser la couche physique 2, avoir une forme traversant ce plan et exposer `take_damage(amount)` sur le collider. Chaque projectile inflige un point de dégâts puis retourne en réserve. Les ennemis sont créés séparément par le directeur de combat.



Validation : `tests/test_weapons.gd` simule cinq minutes de tir continu, vérifie la cadence et le nombre constant de nœuds, la récupération hors écran et après impact, le blocage pendant le départ et les collisions rapides sur une cible fine. `tests/capture_weapons.gd` produit `../renders/projectiles.png` pour vérifier le rendu dans le moteur.





## Son des mitrailleuses — version 2



Six variantes stéréo 48 kHz / PCM 16 bits combinent les attaques et la décroissance enregistrées de **The Free Firearm Sound Library** (CC0) avec le corps grave de **Light Machine Gun**, par **KuraiWolf** (CC BY 4.0). Les crédits à distribuer avec le jeu sont dans `assets/audio/weapons/CREDITS.md`.



Le relief stéréo des prises est conservé. Le sample de mitrailleuse est ralenti légèrement et filtré pour renforcer le corps grave, tandis que les attaques gardent leur précision. Une décroissance de 600 ms et de discrètes réflexions asymétriques donnent de la profondeur. Les deux armes sont décalées de 8 à 9,2 ms ; aucune grande réverbération de salle n’est ajoutée à cette scène en plein air.



` scripts/weapon_audio.gd ` précharge six fichiers et réutilise huit lecteurs fixes. Un son correspond à une salve, sans répétition immédiate. Les variations de hauteur sont limitées à ±0,8 %, et le niveau de base vaut -5 dB. Les dernières résonances finissent naturellement quand Espace est relâché ; perdre le focus coupe les lecteurs. Le tir reste bloqué pendant le décollage. Aucun lecteur n’est créé pendant les tirs.



Reconstruction : `../audio/.venv/Scripts/python.exe ../audio/build_weapon_audio.py` (NumPy, SciPy, SoundFile). Les originaux restent dans `../audio/sources`. Les fichiers de jeu représentent environ 675 Ko. `../audio/weapon-preview-v2.wav` fournit un aperçu ; `../audio/weapon-comparison.wav` présente l’ancienne version puis la nouvelle, à niveau RMS comparable. La première synthèse et le traitement v1 sont conservés pour comparaison.



`tests/test_weapon_audio.gd` enregistre le mixeur Godot dans `../audio/weapon-ingame.wav`, vérifie le signal, la marge avant saturation, les variations, la synchronisation, la fin des résonances et le nombre fixe de lecteurs. `tests/test_weapons.gd` vérifie cinq minutes simulées de tir avec le système sonore activé.





## Vagues de combat — prototype



La première paire de Zero apparaît 1,5 seconde après la restitution des commandes. Les paires suivantes arrivent toutes les 20 secondes, indépendamment des destructions. Elles entrent au-dessus du cadre, tirent chacune trois salves doubles dirigées vers la position du joueur au moment du tir, exécutent un looping vertical complet de 2,4 secondes près du centre, puis repartent vers le bas. Les formations suivantes changent légèrement de position horizontale.



- `scripts/combat.gd` : vagues, projectiles ennemis, explosions, sons et affichage du test.

- `scripts/enemy_zero.gd` : Zero, déplacement, looping et deux points de résistance.

- `assets/enemies/zero.glb` : modèle PBR 4 952 triangles, hélice séparée, ressources partagées entre instances.

- `scripts/player_hurtbox.gd` : réception des impacts ennemis ; un impact détruit le joueur.

- **R** : recommencer la scène, y compris le décollage ; **Échap** : quitter.



Les tirs ennemis sont rouges, ceux du joueur restent dorés. Les ennemis utilisent la couche de collision 2, le joueur la couche 4. Chaque projectile teste le segment parcouru pour éviter de traverser sa cible entre deux images. Le looping est visuel en altitude ; les collisions restent sur le plan de jeu Y=0. La zone sensible du joueur est centrée sur le fuselage pour conserver une esquive lisible. Les contacts entre avions ne causent pas de dégâts dans ce prototype.



Un ennemi détruit ou entièrement sorti par le bas est libéré avec `queue_free()`. Les projectiles ennemis utilisent 64 emplacements réutilisables, rendus inactifs hors écran, après impact ou après six secondes. Huit explosions sont réutilisées. Les lecteurs audio sont fixes, avec une polyphonie plafonnée. Une limite supplémentaire protège contre les formations persistantes lors de formats de fenêtre extrêmes. Après destruction du joueur, les nouvelles vagues et les tirs ennemis cessent ; les projectiles ennemis présents sont retirés et R permet de recommencer.



Les tirs ennemis réutilisent les sons déjà crédités, à niveau plus bas. Explosion v2 : sources CC0, attaque, grave, souffle et craquements ; reproduction avec `../audio/build_explosion.py`, sources et licences dans `assets/audio/weapons/CREDITS.md`.



Validation : `tests/test_combat.gd` vérifie 180 secondes simulées, neuf vagues de deux avions, la cadence de 20 secondes, le tir avant looping, la rotation complète, la sortie, le nombre de nœuds borné, les vraies collisions dans les deux sens, la destruction unique et le redémarrage par événement clavier R. Résultat : `tests/combat-results.json`. Les captures GPU de `tests/capture_combat.gd` sont dans `../renders/combat-*.png`.



### Explosion v2

Atlas RGBA imagegen : `assets/effects/explosion-atlas.png`, prompt adjacent. Cinq couches feu/fumee animees par `shaders/explosion_cloud.gdshader`, flash bref, 16 etincelles et six debris par effet. Huit effets prealloues, recyclage apres 3,5 secondes. Audio stereo 48 kHz, 3,4 secondes. Validation : `tests/test_explosion.gd`, captures GPU : `tests/capture_explosion.gd`.


## Enemy formations v2

Each 20-second wave now contains two staggered pairs (four Zero). Speed: 7.2 units/s, previously 4.06. Curved approaches use a smooth lateral arc; heading follows the path tangent and bank follows turn rate. One pair performs a 1.6-second vertical loop, the other a tight horizontal circle with progressive coordinated banking. Roles alternate per wave. Three twin salvos precede each maneuver. Collision boxes rotate with heading; muzzle offsets use the aircraft basis. Enemy objects are freed after leaving the bottom. Validation: test_combat.gd, 180 simulated seconds / 9 waves / 216 enemy rounds, plus actual projectile collisions and restart.


### Independent enemy paths (v3)

Four viewport-relative entry lanes now span the playable width with wingspan margins. Every aircraft has its own speed (10 to 11.4 units/s), entry delay, approach curvature/weave, maneuver depth, loop duration and turn radius. Profiles rotate between lanes each wave. Heading follows the analytic path tangent; bank tracks turn rate. Transition tolerances avoid float precision stalls. Combat regression includes lane spacing, horizontal coverage, distinct profiles and cleanup over nine waves.


### Smoother enemy flight (v4)

Approaches now converge toward a centre/player target sampled once at spawn, with quintic lateral easing and forward speed corrected for heading. Wide banked arcs replace tight horizontal circles; bank capped at 37 degrees and eased. Loop pitch rate eases in/out over 2.4-2.8 seconds. Enemies begin farther above the viewport to establish their turn smoothly. Enemy bullets now travel at 14 units/s (previously 8.5). Nine-wave regression verifies convergence, heading continuity, collisions, recycling and restart.


### Takeoff engine audio

Two fixed AudioStreamPlayer3D sample layers follow the player during the opening: propeller texture and vintage engine body. Sources and attribution: `assets/audio/engine/CREDITS.md`; reproducible preparation: `../audio/build_engine_audio.py`. Seamless PCM loops, throttle-driven RPM, manual radial-velocity Doppler relative to the camera (8 metres per game unit, 343 m/s), smoothed pitch/distance gain and 1.5-second fade after introduction. No duplicate built-in Doppler. Skip and destruction stop the loops. `tests/test_takeoff_audio.gd` records the actual mixer to `../audio/takeoff-ingame.wav` and checks Doppler, headroom and voice cleanup.


### Fighter engine v2

The active engine layers now derive from doubletrigger's P-51 Merlin recording (CC BY 3.0), replacing the generic propeller/interior sources. Exhaust bite and low engine body have separate loops. Doppler acoustic scale is 24 metres/unit, with bounded pitch ratio 0.74-1.46 and smoothed radial velocity. This exaggeration is intentional for the top-down presentation. Current mix is captured by test_takeoff_audio.gd; v1 capture retained as audio/takeoff-ingame-v1.wav.


### Deep engine mix v3

Longer slowed P-51 excerpt, softened 1.9 kHz exhaust ceiling, dominant recorded bass plus harmonic pressure pulses. Stronger throttle volume ramp. Doppler scale reduced to 14 metres/unit to preserve engine weight. Actual mixer test: ratio 0.846-1.220, peak PCM 16121; 35-250 Hz RMS during seconds 2-8 is -20.5 dBFS versus -31.9 in v2. Source credits describe the synthesized reinforcement.
