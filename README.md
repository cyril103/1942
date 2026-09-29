# 1942 — prototype de shmup

Prototype Godot 4.7.2 : avion joueur et ennemis en 3D low poly, décor océanique
en 2D, départ d'un porte-avions, loopings, combats et effets sonores.

## Lancer

Ouvrir `game/project.godot` avec Godot 4.7.2, puis lancer la scène principale.
Sur cette machine, `Jouer.cmd` et `Jouer.ps1` lancent directement le jeu.

- Flèches : déplacement ; Espace : tirs.
- R : recommencer ; Échap : quitter.
- Quatre ennemis par vague, toutes les 20 secondes, pour tester le combat.

## Contenu

- `game/` : projet jouable, assets, shaders et tests.
- `art/` : références, textures et prompts de génération.
- `blender/` : modèles modifiables, studio et scripts de construction/export.
- `audio/` : scripts de préparation, sources utilisées et captures du mix.
- `renders/` : planches studio et captures de validation.

Instructions détaillées dans `game/README.md` et les README Blender.
Les crédits des samples sont conservés dans `game/assets/audio/`.
Les outils portables, environnements Python et caches ne sont pas versionnés.

Les tests Godot se lancent avec `--headless --path game --script res://tests/test_combat.gd`
(ou un autre script `test_*.gd`). La préparation audio utilise Python avec NumPy,
SciPy et SoundFile. Les chemins des outils dans les lanceurs correspondent à
l'installation locale et peuvent devoir être adaptés sur une autre machine.
