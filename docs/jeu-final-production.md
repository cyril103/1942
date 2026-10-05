# Jeu final — plan de production

Branche : codex/jeu-final. Objectif utilisateur : jeu complet, 32 niveaux, finition soignée.

## Direction

Titre de travail : PACIFIC STRIKE — Campagne 1942. Shmup solo vertical 3:4, avions 3D low poly et terrain 2D, cockpit existant conservé. Inspiration : lisibilité et attaques spéciales de 1942: Joint Strike, campagne originale de 32 missions.

## Livraison prévue

- Huit secteurs de quatre missions, événements scénarisés, diversité des rencontres, huit affrontements de boss à phases.
- Missions de patrouille, interception et attaque navale ; la destruction du boss clôt un secteur.
- Tir maintenu, POW en éventail, attaque spéciale chargée par les destructions, bombe d'urgence, déplacement précis.
- Trois profils de pilotage, choix de difficulté, améliorations entre missions, score et médailles.
- Accueil, sélection de mission débloquée, briefing, pause, options audio/affichage/accessibilité, bilan, défaite/reprise, fin de campagne, crédits.
- Sauvegarde atomique versionnée, validation des données et reprise au début de la mission.
- Ambiances visuelles de secteurs, nouveaux modèles navals et boss, musique et mixage contrôlables.
- Tests des 32 chronologies, progression, collisions, boss et interfaces ; captures GPU ; build Windows autonome si templates disponibles.

## Validation

Ne pas qualifier la campagne de terminée avant validation du parcours complet, des transitions victoire/défaite, du chargement de sauvegarde et du rendu. Les tests accélérés ne remplacent pas une revue des captures et des séquences de jeu. Préserver les tests du prototype pour régression.

## Références consultées

- https://www.gamespot.com/reviews/1942-joint-strike-review/1900-6195100/
- https://www.wired.com/2008/08/review-1942-joi/
- https://worthplaying.com/article/2008/4/28/previews/50795-xbox-live-arcade-preview-1942-joint-strike/

## État

- [x] Branche créée, audit du prototype, recherche de référence.
- [x] Données des 32 missions et progression persistante.
- [x] Directeur de campagne, ennemis navals et boss.
- [x] Menus et HUD de campagne, armes et commandes.
- [x] Nouveaux assets, ambiance, musique.
- [x] Validation automatisée des 32 missions, tests physiques du paquet, revue GPU et distribution Windows. Portée et limites dans `jeu-final-validation.md`.
