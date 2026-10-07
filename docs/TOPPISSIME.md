# Pacific Strike — édition Toppissime

Branche : `jeu_toppissime`, issue de `dbcdd8e`. Le titre conserve ses 32 missions et sa progression existante. Les nouveaux champs de profil restent compatibles avec les anciennes sauvegardes.

## Les neuf axes livrés

1. **Mise en scène** : quatre actes par mission, messages radio contextualisés, pauses d'apparition de chasseurs aux transitions. La mission 1 devient *Opération Brise-Lames*, 105 secondes avant récupération, avec une confrontation au bombardier de commandement. La campagne comprend maintenant neuf rencontres de boss.
2. **Décisions tactiques** : chasseurs d'interception plus rapides avec légère anticipation de la position du joueur, escortes visant la position annoncée, artilleurs plus lents au tir décalé. Une couronne annonce le tir 0,22 seconde avant le départ. Sur sept missions, un navire allié doit survivre 32 secondes ; les bombardiers le ciblent réellement. Il suit le chenal et ne peut pas être touché par les projectiles du joueur.
3. **Scoring** : chaîne de 4,5 secondes, multiplicateur jusqu'à ×5, objectif secondaire récompensé une seule fois, précision, meilleure chaîne et rang D à S. Le rang S exige une victoire sans vie perdue, au plus un impact, l'objectif secondaire et une chaîne de 16. Les anciennes médailles et récompenses de campagne restent compatibles.
4. **Trois styles** : surcharge de cadence du Vanguard (5 s), poursuite du P-38 (vitesse et dégâts, 4 s), bastion du Corsair (protection, dégâts et frappe large, 3,5 s). Recharge par destructions et temps de combat, sans remplacer le POW actif.
5. **Boss** : deux points faibles visés avec les projectiles ou le laser, dégâts doublés sur un composant actif, neutralisation de défenses, incendies localisés et transition de phase protégée de 1,2 seconde avec nettoyage des tirs. La destruction en plusieurs explosions demeure.
6. **Décor et lumière** : quatre nouvelles îles militaires (port, piste, radar, dépôt) intégrées aux banques de variantes avec le même fondu côtier et les mêmes garanties de navigation. Ciel de réflexion préfiltré 128 pixels, verrières ajustées, lumière adaptée au crépuscule et aux tempêtes. Aucun retournement supplémentaire des îles.
7. **Effets lisibles** : débris opaques dans un MultiMesh de 64 instances, traînées d'ailes en virage, incendies procéduraux sur les composants. Les tirs conservent leurs couleurs lisibles.
8. **Audio** : les pistes d'action de `codex/jeu-final` sont rétablies en version 1.5, avec les fondus entre vol et boss. La composition adaptative originale à 140 BPM reste conservée comme source historique. Messages radio sous-titrés avec indicatif sonore ; pas de comédiens enregistrés. Les morceaux CC0 sont conservés avec leurs crédits.
9. **Finition et rejouabilité** : modes arcade à équipement fixe et entraînement direct aux boss, records arcade locaux par avion/mission, sauvegarde de campagne isolée, touches reconfigurables avec conflits détectés, conservation des commandes manette, trois profils graphiques, VSync et compteur FPS. Les indications de capacités dans le HUD suivent les touches attribuées.

## Fiabilité et interface — version 1.6.1

La passe de revue corrige les règles de DCA, les contacts des tirs, les récompenses de points faibles, les modes de session et la récupération des sauvegardes. Le HUD de brouillage, les briefings et les aides de commandes sont adaptés aux différentes résolutions. Les crédits distinguent les musiques actives des compositions historiques. Détails, commandes de reproduction et limites : [suivi des corrections](suivi-corrections.txt).

Validation de l'interface : **1 110 assertions avec rendu réel**, dont 25 captures, sans échec. Session : 165 assertions sans échec. Les [captures avant/après](../renders/validation-interface/README.md) et les [mesures de géométrie](../game/tests/ui-readability-results.json) sont versionnées. La manette physique et une campagne humaine complète restent à vérifier.

**Distribution actuelle : Windows 1.6.1**, `dist/PacificStrike/PacificStrike.exe` et `dist/PacificStrike-Windows-x64.zip`. Nom produit Pacific Strike, versions Windows 1.6.1.0, icône propre au jeu. SHA256 : `06BF66C22393B14A67512688E126D63048B5A09C4680214EC8AA5584EDB5B78A`. Le test du ZIP passe ses **27 contrôles**, dont un lancement normal de 180 images depuis un dossier temporaire extérieur au dépôt. Ce test ne remplace pas une partie complète ; l'observation visuelle des propriétés dans l'Explorateur reste à faire. Le ZIP et l'EXE sont générés localement et exclus du dépôt Git. Lancement : `Jouer-Final.cmd`, ou extraire le ZIP et ouvrir l'EXE.

## Interceptions pendant le retour — version 1.6 (historique)

Après le raid, le retour à l'altitude de croisière au-dessus de l'océan réactive les avions dès que la côte est derrière le joueur. Ce seuil est indépendant de la marge maritime plus large nécessaire au porte-avions. La première vague arrive immédiatement ; Zero de face et Hayabusa latéraux alternent ensuite toutes les 4,8 à 3,4 secondes selon le secteur, dans le même budget de chasseurs et de projectiles que les autres missions.

L'extraction dispose d'au moins douze secondes avant la récupération : la durée nominale est conservée lorsqu'elle laisse déjà assez de temps. Les apparitions s'arrêtent cinq secondes avant l'atterrissage automatique. Le vol rasant reste exclusivement défendu par la DCA. Pause, mort et reprise ne cumulent pas de vagues en attente, et les avions restants sont retirés au début de l'atterrissage. Un message radio annonce les contacts au retour.

Validation 1.6 : **4 997 contrôles de raids** et **130 contrôles de caméra** réussis. Les huit missions comprennent trois à cinq vagues d'extraction dans le parcours testé, sans allongement de leur durée nominale : par exemple, mission 03 à 65,25 s, 70,07 s et 74,88 s avant récupération à 82 s ; mission 31 à 75,88 s, 79,30 s, 82,72 s, 86,13 s et 89,55 s avant récupération à 96 s. Un scénario supplémentaire vérifie l'extension minimale de douze secondes après une sortie tardive, la pause et le respawn sans rafale de rattrapage. Les tests couvrent également les trois avions du joueur, le verrouillage pendant le vol rasant et l'arrêt pendant l'atterrissage.

Capture réelle : `renders/assault-interception-retour.png`. Résultats détaillés des horaires : `game/tests/ground-assault-results.json`. Les pools et plafonds d'acteurs existants sont conservés ; aucun nouveau shader ou effet n'est ajouté par cette séquence.

Les **4 997 contrôles de raids passent également contre le paquet Windows final**, sans erreur ni avertissement. Le ZIP contient le même exécutable (hash vérifié) et le manuel 1.6.

**Distribution antérieure : Windows 1.6**, `dist/PacificStrike/PacificStrike.exe` et `dist/PacificStrike-Windows-x64.zip`. SHA256 de l'exécutable : `B1EBED616A0EDF05E680E514CFF3A9821D8AB9CB17CB40663A8E5C10884612AA`. Lancement : `Jouer-Final.cmd`. Essai direct : **Arcade / Score Attack → 03 / Opération Coupe-Circuit**.

## Approche aérienne et assaut renforcé — version 1.5 (historique)

Les raids commencent avec trois vagues de chasseurs et un bombardier au-dessus de l'océan. Le passage en vol rasant, lié à l'altitude réelle et non à un simple délai, ferme l'espace aérien : les avions cessent de tirer et de collider, leurs modèles montent au-dessus de la caméra pendant 0,75 seconde, puis sont libérés. Leurs projectiles sont nettoyés une fois à la transition. Aucun score ni POW n'est accordé pour cette sortie ; les apparitions directes et renforts restent verrouillés au ras du sol. La remontée au large rend les apparitions possibles, sans vague différée pendant l'atterrissage.

Les huit bases comportent maintenant **30 à 45 installations**, dont **24 à 36 positions armées**, réparties en groupes de cinq sur la largeur du terrain. Deux canons restent proches du support pour préserver les réactions en chaîne des réservoirs ; les flancs croisent leur feu. La piste reste dégagée. Les radars arrivent après la première ligne pour que le brouillage ne neutralise pas toute l'ouverture. L'objectif va de 12 à 26 destructions ; les POW à trois puis neuf destructions sont conservés.

Les batteries ont 22 PV, les bunkers 32, avant la progression de secteur. La première salve part en environ 0,40–0,52 seconde après l'entrée visible, plus un décalage de position de 0–0,18 seconde. Le préavis vaut 0,48–0,36 seconde, avec visée verrouillée : l'esquive après l'annonce reste utile. Les batteries envoient 6 à 10 tirs par attaque ; les bunkers croisent deux ou trois éventails, soit 10 à 21 projectiles. Un canon rapide par groupe alterne ses tubes avec 6 à 9 tirs rapprochés. Les repos entre attaques sont raccourcis et respectent encore la difficulté sélectionnée. Sons de canons graves et rapides partagent un budget de quatre voix et un espacement minimum de 75 ms.

Les cinq WAV `menu`, `flight`, `flight2`, `boss`, `victory` ont été comparés à `codex/jeu-final` : contenus identiques. Le lecteur joue à nouveau les pistes d'action CC0 de Juhani Junkala, avec les gains et fondus de cette branche, en conservant les annonces radio et les réglages de volume. Les trois pistes procédurales Toppissime ne sont plus jouées.

Validation 1.5 : **4 923 contrôles de raids**, **195 contrôles DCA**, **127 contrôles de caméra**, **790 contrôles de campagne**, **106 contrôles Toppissime**, tous réussis. Les tests de fondations couvrent aussi une fenêtre étroite ; les tests de transition vérifient le retrait des trois familles aériennes sans récompense fictive, le nettoyage des balles et l'absence d'avions au sol. Les 4 923 contrôles de raids et 195 contrôles DCA passent également contre le paquet Windows, sans erreur ni avertissement.

Test de pression supplémentaire : **16 contrôles réussis** avec les HP authentiques, le Vanguard sans amélioration, tir continu réel, déplacement à vitesse normale et visée maintenue sur les canons. Sur 25 secondes de vol rasant, la mission 03 émet 161 projectiles, avec un pic de 29, seize installations ayant tiré et dix cibles détruites. La mission 31 émet 563 projectiles, avec un pic de 49, dix-neuf installations ayant tiré et deux cibles détruites. Les POW collectés ne renforcent pas l'arme dans ce scénario et le pilote est invulnérable : il mesure la riposte sous feu ciblé, pas un taux de victoire humain. Résultats : `game/tests/raid-pressure-results.json`.

Mesure 1.5 : GTX 1650, 1920×1080, VSync désactivée, mission 31 rechargée par profil, multi-tir et explosions toutes les 0,22 s. Trois secondes de chauffe puis treize secondes mesurées, jusqu'à sept installations visibles et cinquante projectiles ennemis simultanés. Les PV sont augmentés seulement dans ce benchmark pour conserver toutes les défenses actives. Aucun autre moteur graphique ni export pendant la mesure.

| Profil | Moyenne | p95 | p99 | Maximum | GPU moyen |
|---|---:|---:|---:|---:|---:|
| Performance | 2,51 ms | 3,81 ms | 4,65 ms | 7,11 ms | 1,60 ms |
| Équilibré | 3,10 ms | 4,74 ms | 5,97 ms | 12,78 ms | 2,43 ms |
| Qualité | 3,11 ms | 4,54 ms | 5,21 ms | 8,05 ms | 2,62 ms |

Toutes les images mesurées restent sous le budget de 16,67 ms à 60 FPS. Construction initiale : 283–313 ms, hors combat. Ce passage ne garantit pas les performances de toutes les machines ou les compilations à froid. Résultats : `game/tests/ground-performance.json`. Captures réelles : `renders/assault-approche-aerienne.png` et `renders/assault-dca.png`.

**Distribution antérieure : Windows 1.5**, `dist/PacificStrike/PacificStrike.exe` et `dist/PacificStrike-Windows-x64.zip`. SHA256 de l'exécutable : `7EE5A0A0E576D5C0FD5575C841429AF3613214059F3A72303A592853148DC006`. Lancement : `Jouer-Final.cmd`. Essai direct : **Arcade / Score Attack → 03 / Opération Coupe-Circuit**.

## Raids défendus exclusivement par la DCA — version 1.4 (historique)

Les huit missions terrestres ne programment plus aucune vague de chasseurs, formation rouge, bombardier, navire ou boss. Un verrou dans les fabriques d'avions et le directeur interdit aussi les apparitions directes et les renforts. Les missions maritimes gardent leurs adversaires aériens.

Le terrain accueille 18 à 27 installations, par groupes de trois : deux positions armées et un radar, dépôt ou hangar. Cela donne 12 à 18 défenses actives par mission, contre 5 à 10 auparavant. L'objectif demande 8 à 15 destructions selon le secteur. Les deux radars et les réactions en chaîne des dépôts restent des leviers tactiques ; le brouillage interrompt une salve engagée et la reprise est étagée entre batteries.

Les batteries tirent deux salves de deux projectiles convergents, puis trois salves à partir du secteur 3 (indices 0 à 7). Les bunkers ouvrent un éventail de trois tirs, puis cinq au secteur 5. La visée est verrouillée au début du préavis de 0,84 à 0,72 seconde. Cadence et vitesse augmentent progressivement avec le secteur et respectent toujours le réglage de difficulté. Aucun départ hors champ, derrière le joueur, durant sa mort ou avant la reprise des commandes. La saturation du pool n'accumule pas de tirs différés.

Les projectiles ennemis utilisent désormais une carte de 0,90 au lieu de 0,68 unité, avec cœur blanc chaud, corps orange, liseré rouge et contour sombre opaque. Leurs balayages de collision sont conservés. Les POW proviennent des destructions au sol après trois puis neuf cibles, avec un maximum de deux récompenses ; un POW actif ou sa collecte ne sont jamais écrasés.

Capture réelle : `renders/assault-dca.png`. Validation 1.4 : **2 616 contrôles de raids**, **101 contrôles de salves DCA**, **118 contrôles de caméra basse**, **750 contrôles de campagne** et **106 contrôles Toppissime**, tous réussis. Les tests couvrent les huit raids sans avion, les tirs physiques, les annulations de salves, le brouillage, les POW différés, la caméra, le respawn, les objectifs et les 32 victoires de campagne.

Mesure 1.4 sur GTX 1650, 1920×1080, VSync désactivée : mission 31 rechargée pour chaque profil, DCA seule, multi-tir et explosions toutes les 0,22 s. Trois secondes de chauffe puis treize secondes mesurées, sans autre processus de rendu. Jusqu'à six installations visibles et onze projectiles ennemis simultanés.

| Profil | Moyenne | p95 | p99 | Maximum | GPU moyen |
|---|---:|---:|---:|---:|---:|
| Performance | 2,43 ms | 3,66 ms | 4,46 ms | 8,72 ms | 1,61 ms |
| Équilibré | 3,00 ms | 4,45 ms | 5,33 ms | 9,36 ms | 2,46 ms |
| Qualité | 3,00 ms | 4,37 ms | 4,86 ms | 9,97 ms | 2,66 ms |

Toutes les images de ce passage sont sous 10 ms, pour un budget de 16,67 ms à 60 FPS. La construction initiale de la scène prend 295–326 ms, hors combat. Cette mesure couvre ce scénario et cette machine, pas les compilations à froid ou toutes les tâches système ; elle ne se compare pas directement aux anciens scénarios incluant des vagues aériennes. Résultats détaillés : `game/tests/ground-performance.json`.

**Distribution antérieure : Windows 1.4**, `dist/PacificStrike/PacificStrike.exe` et `dist/PacificStrike-Windows-x64.zip`. SHA256 de l'exécutable : `314C7ACD67F94CDF151A2C868FAE59769084838C900520F278FE426DB4C6FF36`. Les **2 616 contrôles de raids et 101 contrôles de salves DCA** passent également contre les ressources du paquet Windows, sans erreur ni avertissement. Lancement : `Jouer-Final.cmd`. Pour essayer directement : **Arcade / Score Attack → 03 / Opération Coupe-Circuit**.

## Retrait des anneaux d'eau — version 1.3.1

Les cercles d'écume déclenchés lors des explosions et de la chute de débris dans l'eau ont été supprimés, ainsi que leur pool de douze meshes et leur branche de shader. Les débris se libèrent toujours à l'arrivée dans l'eau. Les explosions, incendies, traînées d'ailes, sillages de navires et écume côtière restent inchangés.

## Refonte visuelle des raids — version 1.3

L'approche anticipe désormais la côte : l'avion descend avec une assiette progressive, et la caméra passe réellement sous la couche de nuages avant l'entrée sur terre. Les nuages conservent leur altitude et leur opacité ; ils se trouvent derrière la caméra basse. L'altitude du point de vue passe de 35 à −3,2, celle des avions à −5,8, et la taille orthographique de 25 à 21 (grossissement de 19 %). Le plateau est à −8. La sortie du terrain déclenche la remontée et rend la vue normale avant l'atterrissage.

Les visuels des chasseurs, du bombardier, des tirs, du laser, des impacts, des explosions aériennes, du POW et des capacités suivent cette altitude. Les manœuvres des ennemis restent sous le point de vue. Les collisions conservent leur plan logique Y=0 ; la projection strictement verticale préserve l'alignement exact avec les modèles et le HUD. Les requêtes de bord d'écran utilisent une profondeur positive même quand la caméra est sous Y=0. Le respawn reste à l'altitude du raid.

Deux nouvelles textures originales ImageGen composent le sol : une carte tropicale dessinée sur toute la longueur du terrain et une couche de détails de pelouse/sol corallien. Jungle, pistes de terre, rochers et clairières remplacent l'ancien aplat. Des palmiers à folioles, des fougères et des rochers géométriques complètent la carte. La côte partage le shader de l'océan, avec eau peu profonde turquoise, écume morcelée et sable corallien. L'exposition du matériau et son spéculaire ont été réglés dans le rendu Compatibility pour conserver le contraste et éviter les hautes lumières brûlées. Les couleurs varient toujours selon le biome.

Les cinq installations ont été reconstruites dans Blender : batterie à deux canons avec sacs de sable, bunker à tourelle, radar ajouré, réservoirs avec tuyauterie et échelles, hangar avec tour, camion et approvisionnements. Elles utilisent un atlas ImageGen partagé et des UV dédiées. Chaque installation a deux meshes opaques, de 1 516 à 4 308 triangles, avec rotation réelle des tourelles/radars et shader de dégâts. La planche `renders/ground-forces-studio.png` est un rendu Cycles des modèles réellement utilisés ; `renders/assault-*.png` sont des captures Godot.

Sources reproductibles : `blender/ground-forces/`. Prompts et provenance : `game/assets/ground-forces/CREDITS.md`, `game/assets/environment/raid-v2/CREDITS.md`. Les ressources sont originales ; aucune dépendance réseau en jeu.

Validation 1.3 : les 130 contrôles de caméra basse couvrent les trois avions, les nuages réellement derrière la caméra, le zoom et les bords, les collisions de tirs/laser, les adversaires, le POW, les capacités, le respawn et la récupération. Les 1 849 contrôles de raids, 893 contrôles de campagne et 106 contrôles Toppissime ont également réussi.

Mesure finale 1.3 sur GTX 1650, 1920×1080, VSync désactivée : une scène rechargée par profil, vagues toutes les 0,9 s, multi-tir et explosions toutes les 0,22 s, 3 s de chauffe puis 13 s mesurées. Jusqu'à 35 contacts et 30 projectiles ennemis. Aucun autre processus de rendu ou d'export pendant la mesure.

| Profil | Moyenne | p95 | p99 | Maximum | GPU moyen |
|---|---:|---:|---:|---:|---:|
| Performance | 3.24 | 5.24 | 6.47 | 8.53 | 1.68 |
| Équilibré | 3.62 | 5.62 | 6.90 | 9.97 | 2.52 |
| Qualité | 3.60 | 5.51 | 6.48 | 8.61 | 2.77 |

Les valeurs sont en millisecondes. Toutes les images de ce passage sont sous 10 ms, pour un budget de 16,67 ms à 60 FPS. La construction initiale prend 284–313 ms, hors combat. Le terrain comporte 26 760 triangles de surface et 244 instances de décor ; les triangles des modèles de végétation et des installations s'y ajoutent. La mesure couvre ce scénario et cette machine, pas les compilations à froid ou toutes les tâches système. Résultats détaillés : `game/tests/ground-performance.json`.


**Distribution antérieure : Windows 1.3.1**, `dist/PacificStrike/PacificStrike.exe` et `dist/PacificStrike-Windows-x64.zip`. SHA256 : `7A9A00F2F800617715E34AEA703668AFF9C9BDEBF71CA30F044FDEC1EE8AFB00`. Les 106 contrôles Toppissime ont réussi directement contre ce paquet, sans erreur ni avertissement. Les contrôles de caméra et des huit raids restent documentés pour la version 1.3. Lancement : `Jouer-Final.cmd`.

## Raids terrestres — version 1.2

Les missions **3, 7, 11, 15, 19, 23, 27 et 31** sont désormais des assauts côtiers : mer au départ, descente douce, base militaire en relief, extraction puis récupération sur le porte-avions. Le terrain et toutes les installations partagent la distance réellement parcourue par le décor, y compris les épaves. La séquence attend que la terre soit hors de l'approche avant de présenter le porte-avions. Aucun navire n'est programmé dans ces raids ; les missions maritimes conservent leurs îles variées et leurs chenaux.

Cinq cibles en géométrie 3D fusionnée : **réservoirs, radars tournants, batteries orientables, bunkers et hangars**. Il y en a de 12 à 20 par raid, avec un objectif obligatoire de 6 à 9 destructions. Les deux radars interrompent le guidage de la DCA pendant 6 secondes et constituent l'objectif secondaire. Les réserves de carburant transmettent 9 dégâts aux bâtiments à moins de 5,5 unités. Les batteries annoncent leur tir pendant 0,8 seconde ; elles visent ensuite la position mémorisée du joueur, et respectent la progression de difficulté existante. Une vague aérienne sur trois est retirée pendant la section terrestre pour garder les menaces lisibles.

Les mitrailleuses, le laser, la bombe et la capacité active touchent les cibles au sol. Une mort ne réinitialise ni leur destruction ni le quota. Un quota manqué déclenche un retour au pont puis un bilan **Mission inaccomplie**, distinct d'un Game Over. Les dégâts, récompenses et chaînes de score ne sont attribués qu'une fois par cible. Épaves, fumée et flammes se libèrent après quatre secondes.

Les terrains ont une plage et des reliefs périphériques, des routes et pistes patinées, une texture de sol filtrée avec mipmaps et des palettes adaptées aux huit biomes. Les nuages gardent leur opacité constante et leurs ombres se projettent sur la terre. Le joueur descend légèrement avec une assiette progressive ; le relèvement du terrain et une accélération du décor de 18 % accentuent la proximité sans réduire la surface de jeu ni déplacer le plan logique des collisions.

Construction du terrain avant le combat, plafond de 29 000 triangles, au plus 323 instances de végétation/rochers réparties dans quatre MultiMesh. La majorité du sol est opaque ; la transparence reste limitée au littoral. Le mode Performance réduit la végétation et retire les ombres dynamiques. La texture a été produite avec **ImageGen intégré**, sans upscale : [texture native](../game/assets/environment/assault-ground-detail.png) et [prompt exact/provenance](../game/assets/environment/ASSAULT-CREDITS.md). Captures réelles dans `renders/assault-*.png`.

Accès immédiat pour essai : **Arcade / Score Attack → 03 / Opération Coupe-Circuit**. La progression de campagne reste isolée.

Validation version 1.2 : **1 849 contrôles dédiés** aux huit raids et à un objectif manqué ; **893 contrôles** de campagne sur les 32 missions ; **106 contrôles** des fonctions Toppissime. Les variations de nombre par rapport à 1.1 viennent du remplacement des événements et objectifs navals des huit raids. Les tests couvrent les balayages physiques réels du tir et du laser, les bombes, le brouillage, les réactions en chaîne, le respawn, le défilement des épaves/explosions et l'atterrissage en mer. Les 1 849 contrôles passent également contre les ressources de l'exécutable Windows exporté, sans erreur ni avertissement. Scripts et résultats : `game/tests/test_ground_assault.gd`, `ground-assault-results.json`, `ground-performance.json`.

Benchmark terrestre final : GTX 1650, 1920×1080, VSync désactivée, même raid rechargé pour chaque profil, vagues toutes les 0,9 s, multi-tir et explosions toutes les 0,22 s. Trois secondes de chauffe puis treize secondes de mesure par profil, jusqu'à 36 contacts et 38 projectiles ennemis. Pas d'autre test ni export lancé pendant la mesure.

| Profil | Moyenne | p95 | p99 | Maximum | GPU moyen |
|---|---:|---:|---:|---:|---:|
| Performance | 2,94 ms | 4,41 ms | 5,20 ms | 7,17 ms | 1,93 ms |
| Équilibré | 3,60 ms | 5,39 ms | 6,72 ms | 10,45 ms | 2,90 ms |
| Qualité | 3,72 ms | 5,25 ms | 5,96 ms | 8,02 ms | 3,21 ms |

Le budget 60 FPS vaut 16,67 ms ; tous les frames de ce passage mesuré restent en dessous. Construction initiale de la scène : 281 à 316 ms, hors combat et hors ces statistiques. Les compilations à froid, changements de résolution, machines différentes et tâches système ne sont pas couverts par cette mesure. Les détails de cadence et de tir peuvent varier légèrement d'un passage à l'autre.

**Distribution antérieure : Windows 1.2**, `dist/PacificStrike/PacificStrike.exe` et `dist/PacificStrike-Windows-x64.zip`. SHA256 de l'exécutable : `7EE4CFDB40E17494E60544807F187E7F5DAA0EC81C97C72149AD4E48C983B13D`. Lancer avec `Jouer-Final.cmd`, ou décompresser le ZIP et ouvrir l'exécutable dans son dossier.

## Production

Le nouvel atlas a été créé avec ImageGen intégré. Prompt exact et provenance : `game/assets/environment/MILITARY-CREDITS.md`. Source de la musique et de l'indicatif : `audio/build_toppissime_music.py` ; NumPy dans le Python fourni avec Blender suffit pour reproduire les WAV. Aucun nouveau sample tiers ni dépendance réseau n'est nécessaire au jeu.

Le moteur reste Godot 4.7.2 Compatibility. Les reflets sont préfiltrés ; il n'y a ni ray tracing ni simulation volumétrique des nuages. Les boss sont chargés dès le menu et les effets ont des capacités fixes. Performance coupe ombres dynamiques, débris et MSAA ; Équilibré utilise MSAA 2× ; Qualité utilise MSAA 4×. Le gameplay reste identique.

## Validation antérieure — version 1.1

- Tests dédiés : capacités, score, modes isolés, sauvegarde, commandes, budgets d'effets, collisions du convoi et récompense de survie.
- Dernière exécution dédiée : 114 contrôles réussis. Les trois ciels de réflexion sont conservés dans un cache borné ; l'enchaînement rapide des missions ne produit plus d'avertissement de fuite de texture à la fermeture.
- Régression : simulation des 32 missions, 946 contrôles ; difficulté, 150 contrôles ; cycle de campagne, 60 contrôles ; îles et navigation, 38 642 contrôles.
- Captures réelles : `renders/toppissime-*.png` ; l'outil de capture neutralise les dégâts du joueur pour l'inspection.
- Benchmark animé : `game/tests/benchmark_toppissime.gd`, résultat `game/tests/toppissime-performance.json`. GTX 1650, 1920×1080, VSync désactivée, trois profils, apparition de vagues toutes les 0,9 s, boss, tirs et explosions. Trois secondes de chauffe puis treize secondes mesurées par profil. Les valeurs p95/p99 et maxima décrivent ce scénario et ne garantissent pas l'absence de ralentissement sur toutes les machines.

L'appellation « jeu de l'année » reste une ambition artistique : les critères vérifiables ici sont les fonctionnalités, la stabilité, la lisibilité et les mesures. Les classements sont locaux ; aucun service en ligne ni multijoueur n'a été ajouté.

Mesures du test animé, GTX 1650 / 1080p :

| Profil | Frame moyenne | p95 | p99 | Maximum |
|---|---:|---:|---:|---:|
| Performance | 2,89 ms | 4,33 ms | 5,15 ms | 6,97 ms |
| Équilibré | 3,42 ms | 5,00 ms | 6,26 ms | 8,95 ms |
| Qualité | 3,11 ms | 4,60 ms | 5,37 ms | 10,07 ms |

Ces profils ont été mesurés successivement dans une bataille évolutive (jusqu'à 35 contacts et 48 projectiles ennemis), pas sur des images identiques. La moyenne Qualité légèrement inférieure à Équilibré n'implique donc pas que MSAA 4× soit plus rapide. Le budget de 60 FPS est de 16,67 ms. Les chargements de scènes et la chauffe initiale sont exclus des mesures.

La version 1.1 avait également passé ses 114 contrôles dédiés contre son paquet embarqué via le moteur console (`--main-pack`), avec un profil temporaire distinct supprimé après le test, et ses 946 contrôles de campagne après correction du cache de ciel. L'export courant est la version 1.6.1 décrite plus haut.

## Références consultées

- Housemarque, scoring et maîtrise : https://blog.fr.playstation.com/2017/07/06/nex-machina-les-10-astuces-de-housemarque-pour-survivre-dans-son-jeu-de-tir/
- Godot, coûts GPU/transparences : https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html
- Godot, environnement et reflets : https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html
- Godot, InputMap : https://docs.godotengine.org/en/stable/classes/class_inputmap.html
- Godot, géométrie instanciée : https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
