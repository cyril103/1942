# Équipement, score et reprises — sources 1.7.0

Captures du jeu avec Godot 4.7.2 / OpenGL Compatibility, GTX 1650.
Les fixtures utilisent des profils isolés. Ce sont des preuves de rendu et
de géométrie ; aucune session humaine ou viabilité de campagne n'est revendiquée.

- [Hangar initial, 720p](loadout-hangar-start-720.png) : rôles et premiers achats.
- [Hangar équipé, 1080p](loadout-hangar-equipped-1080.png) : trois statistiques calculées avec les modules.
- [Visée, 1080p](loadout-workshop-group0-1080.png) : débit contre couverture.
- [Cellule, 720p](loadout-workshop-group1-720.png) : résistance contre mobilité.
- [Capacité, 1080p](loadout-workshop-group4-1080.png) : durée contre frappe.
- [Guide de score, 720p](score-retry-guide-720.png) : règles partagées avant le vol.
- [Or et rang A, 1080p](score-retry-gold-A-1080.png) : les deux évaluations restent distinctes.
- [Argent et rang S, 720p](score-retry-silver-S-720.png) : quota principal manqué malgré la maîtrise du pilotage.
- [Option de reprise courte, 720p](score-retry-comfort-720.png) : activée pour cette capture ; désactivée par défaut dans le jeu.

Les résultats reproductibles et leurs scopes sont dans
[loadout-ui-results.json](../../game/tests/loadout-ui-results.json),
[score-retry-ui-results.json](../../game/tests/score-retry-ui-results.json),
[loadout-profile-results.json](../../game/tests/loadout-profile-results.json) et
[loadout-combat-results.json](../../game/tests/loadout-combat-results.json).
Les assertions répètent des cas par configuration et par image ; elles
ne représentent pas autant de parties indépendantes.

Les images d'équipement ont été recapturées après correction du focus de
l'appareil affecté. Les images de score/confort montrent des contrôles dont
la géométrie est inchangée par ce dernier correctif de focus.
