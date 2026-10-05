# Révision dynamique — 5 octobre 2026

Cette révision répond au retour de jeu sur la difficulté, la musique, la place occupée par le cockpit, la durée des explosions, le score et les bonus.

## Changements jouables

- HUD compact de 64 pixels en haut et 44 en bas à 1080p. Aire de jeu de 1920 × 972 au lieu de 810 × 1080 : toute la largeur et 90 % de la surface.
- 19 à 35 rencontres écrites par mission au lieu d'environ sept. Vagues de huit chasseurs, entrées latérales décalées, trajectoires plus réparties sur la largeur. Limite de 32 chasseurs actifs et pools fixes de 192 projectiles ennemis et 18 explosions.
- Chasseurs ordinaires à trois points de vie, projectiles ennemis plus rapides, coque de base réduite, cadence et vitesse joueur renforcées après le second retour de jeu. Les boss balaient une aire plus large, disposent de davantage de résistance et reçoivent des renforts toutes les 6,4 à 8,5 secondes.
- Cinq morceaux d'action de Juhani Junkala / SubspaceAudio (CC0), avec thèmes de menu, secteurs alternés, boss et victoire. Source et notice incluses dans les crédits et le ZIP Windows.
- Explosion visuelle de 1,35 seconde au lieu de 3,5 ; audio de 1,9 au lieu de 3,4. Flash bref lors des impacts sur les chasseurs. Laser animé avec noyau lumineux, halo et impact, sans allocations par tir.
- Score cumulé de la partie, vies et arme conservés au passage de mission et au rechargement de la sauvegarde. Le bilan indique séparément les points de mission. Une tentative abandonnée ou perdue reprend le dernier état validé, sans compter ses points deux fois.
- Décollage à chaque mission. Après une victoire : sept secondes d'approche, alignement, descente, arrondi et freinage sur le porte-avions avant le bilan. Tir et dégâts neutralisés pendant l'appontage.
- Bonus exclusifs à icônes : multi-tir cyan, laser violet et vie verte. Prendre une vie ajoute immédiatement une vie (maximum neuf) et remet le tir standard ; cette vie acquise n'est pas retirée au changement de bonus suivant.

## Validation

- `test_campaign.gd` : 940 contrôles, 32 chronologies et huit boss, zéro échec.
- `test_dynamic_campaign.gd` : 60 contrôles, notamment migration de l'ancienne sauvegarde, score/vies/arme, largeur du terrain, limites du joueur, exclusivité des trois bonus, dégâts réels du laser, arrêt audio, appontage puis score de la mission suivante.
- Régressions : formations rouges 1 928 contrôles, décor 2 921 contrôles / 30 minutes simulées, décollage 4 240 contrôles ; attaques latérales et explosions passent également.
- Capture GPU revue : `renders/dynamic-combat-wide.png`, `dynamic-laser-life.png`, `dynamic-landing-approach.png`, `dynamic-landing-deck.png`.
- Séquence de performance sur GTX 1650 : environ 60,2 images/s en moyenne avec le terrain élargi, une formation latérale et des navires. Le temps CPU au 95e percentile est de 16,7 ms avec ombres dans cette séquence courte.
- Paquet Windows chargé par le moteur instrumenté : 10 contrôles supplémentaires passent, dont la sauvegarde, le départ réel, les dégâts des projectiles et le mix musical. Crête audio 22 162 / 32 767, sans saturation dans la séquence mesurée.

Le parcours des 32 missions est simulé pour la couverture des chronologies. Il ne remplace pas une partie humaine complète pour juger la difficulté et le ressenti musical. Les contrôles audio/collisions sur le paquet distribué produisent `game/tests/campaign-runtime-results.json`.

## Recherche et provenance

- Rythme des stages : https://flukz.org/devlog/level-pacing-shmup/
- Vagues et densité : https://flukz.org/devlog/procedural-wave-generation-shmup/
- Musique et licence, page de l'artiste : https://opengameart.org/content/5-chiptunes-action

Les nouvelles icônes sont des SVG originaux ; le shader et le son du laser sont créés pour le projet. Les notices des samples d'explosion et du moteur restent conservées.


## Deuxième réglage — réactivité et lisibilité des armes

- Vitesses des trois appareils : 12 / 14 / 10,4 unités/s (au lieu de 9 / 11 / 7,8). Mode précis Maj conservé.
- Intervalles de tir : 0,105 / 0,09 / 0,12 s (au lieu de 0,15 / 0,125 / 0,17). Le premier avion gagne 43 % de cadence et 33 % de vitesse sans amélioration.
- Chasseurs de campagne : un projectile par coup, trois au lieu de six par rafale, avec un espacement légèrement accru. Vagues conservées. Navires et boss tirent un peu moins fréquemment ; motifs et télégraphes préservés.
- Projectiles ennemis agrandis de 55 %, noyau crème, couronne rouge/orange et contour sombre pour rester visibles au-dessus des îles. Taille du collider joueur inchangée.
- Traceurs joueur agrandis (largeur +75 %, longueur +24 %) et cyan/blanc pour différencier immédiatement les camps.
- Laser : halo de 2,1 unités, largeur offensive de 0,96, neuf rayons échantillonnés. Seule la première cible touchée reçoit les dégâts, une fois par tick. Filaments hélicoïdaux, turbulence, paquets d'énergie, couronnes à la source et au contact. Deux effets persistants réutilisés, aucune création de nœud pendant le tir.
- `test_weapon_readability.gd` : neuf contrôles passent (vitesse réelle, cadence réelle, densité ennemie, collision latérale laser, obstruction, arrêt des effets, changement de pouvoir et vidange du pool après tir rapide).
- `test_dynamic_campaign.gd` : 60 contrôles passent après modification.
- Captures GPU actualisées et shaders compilés sans erreur sur le backend Compatibility.
- `test_laser_performance.gd` : 60,2 images/s sur la courte séquence GTX 1650, temps CPU p95 17,37 ms avec ombres. Cette mesure ne couvre pas toutes les situations de jeu.
- Nouveau paquet Windows : 10 contrôles runtime passent ; crête du mix à 24 625 / 32 767 malgré la cadence accrue. ZIP vérifié (11 fichiers, contrôle CRC sans erreur). SHA256 de l executable : `C46A09DD18496BF04A442A277E772405049B6FC2CE7F33F3C0BEFD073EE781BD`.


## Troisième réglage — vies, blindage et fin de partie

- Retour 1,5 s après destruction tant qu'il reste une vie, dans la même instance de mission : score et progression conservés, blindage rempli, quatre secondes de protection. Clignotement à 4 Hz et anneau de protection décroissant ; les commandes restent actives. Les projectiles ennemis sont nettoyés au retour.
- Jauge BLINDAGE segmentée dans le HUD compact, teinte ambre au dernier point et témoin retardé des dégâts. Compte à rebours de renfort séparé du Game Over.
- À zéro vie, aucune réapparition : 2,4 secondes pour laisser l'explosion et l'annonce visibles, puis bilan GAME OVER avec score total, record, vies perdues et choix explicites. Le HUD de vol est masqué dans le bilan. Réessayer reprend le dernier état de début de mission, comme annoncé à l'écran.
- Validation : 17 contrôles du cycle complet passent sur GPU et sur le paquet Windows (dégâts, trois vies, même mission/score, clignotement, immunité puis expiration, Game Over, retry). Campagne : 940 contrôles passent. Régression dynamique : 60 contrôles passent.
- Captures revues : `renders/lives-protected.png` et `renders/lives-game-over.png`.
- SHA256 Windows : `89A97AFC1FC92E9BCF9AA1CE23188CAFDAEE4B55EC11C475D52C71FD034DC7C1`.
