# Validation de l'interface — revue du 7 octobre 2026

Captures réelles Godot 4.7.2 / OpenGL Compatibility / GTX 1650. Elles proviennent du diagnostic UI, qui crée des situations contrôlées ; aucune victoire humaine n'est déduite des écrans de résultats.

| Situation | Preuves |
|---|---|
| Avant correction : brouillage et briefing | [HUD audité](review-jammed.png), [briefing audité](review-briefing.png) |
| Brouillage après redimensionnement | [1280×720](issue-ui-jammed-1280x720.png), [1920×1080](issue-ui-jammed-1920x1080.png), [2560×1080](issue-ui-jammed-2560x1080.png) |
| Mission 03, texte le plus long des 32 briefings | [720p](issue-ui-briefing-03-720.png), [1080p](issue-ui-briefing-03-1080.png) |
| Touches longues après reconfiguration | [Briefing 720p](issue-ui-briefing-long-keys-720.png), [pause 1080p](issue-ui-pause-long-keys-1080.png) |
| Attribution de la musique | [Crédits](issue-ui-credits.png) |
| Résultats selon le mode | [Arcade](issue-ui-result-arcade-won.png), [entraînement](issue-ui-result-practice-won.png), [fin de campagne](issue-ui-result-final-campaign.png) |

La suite contrôle aussi défaite et victoire dans chaque mode. Reproduction : `Godot --path game --script res://tests/test_ui_readability.gd -- --capture-ui`. Les fichiers sont écrits par défaut dans `user://ui-review` ; `--output-dir=<dossier>` choisit une autre destination.

Les 1 110 assertions incluent 25 sauvegardes d'images et des répétitions par configuration. [Résultat et dimensions des contrôles](../../game/tests/ui-readability-results.json). L'inspection d'une manette physique reste à réaliser ; les tests couvrent les événements InputMap et les callbacks de reconfiguration.
