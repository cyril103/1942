# Captures des raids, candidat 1.8

Le script `game/tests/capture_raid_comparison.gd` rend les huit raids après 8, 20 et 37 secondes simulées à 60 Hz, avec la graine 1942 et le joueur à (-4, 0, 7). La première série utilise le paquet immuable 1.7.0 ; la seconde utilise les sources du candidat 1.8. Les compositions et les cibles ont changé, donc les états de combat ne sont pas identiques.

`capture-before.json` et `capture-after.json` décrivent les 48 captures de chaque série : huit missions, trois étapes et deux tailles de fenêtre/PNG. `comparison.json` vérifie les positions de caméra, sa taille, la position du joueur, l'altitude et les dimensions du terrain : aucune différence dans ces champs. Le viewport interne reste 1920 × 972 dans les deux tailles de PNG ; ces images ne démontrent pas deux résolutions internes natives.

Le dépôt conserve les huit vues de combat en 1280 × 720 avant et après, trois descentes représentatives et les captures UI. Les 96 originaux complets sont conservés localement dans `tools/review/raid-before-1.7.0` et `tools/review/raid-after-final-phase4`. Le script permet de les reproduire ; ces dossiers sont exclus de Git. La planche `contact-sheet.png` est un index réduit des 24 vues après en 1080p : missions 03/07/11/15/19/23/27/31 de haut en bas ; approche, descente, combat de gauche à droite. Le redimensionnement ne sert qu'à cet index, pas aux textures du jeu.

Les huit rendus de répétition 3 × 3 utilisent le vrai shader et l'éclairage du jeu ; quatre sont conservés dans `tiling/`, avec les métadonnées complètes dans `tiling-captures.json`. Inspection par l'agent : aucun joint carré net observé à cette échelle, motifs répétés encore visibles. Ce constat ne prouve pas une périodicité pixel exacte. Le champ `human_inspection: PENDING` reste exact : aucune validation humaine n'est inventée.

Les captures UI finales comprennent aussi `game-over-objective-complete-720.png` et `game-over-objective-complete-1080.png` : mort après accomplissement des priorités, avec état de résultat antérieur mis en cache. Les 946 contrôles du rapport `game/tests/raid-result-radio-results.json` couvrent ce cas et les autres causes de fin ; l'image montre les pixels GPU après synchronisation du rendu.

Reproduction, depuis la racine du dépôt (adapter le chemin Godot) :

```powershell
$raidGodot = 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe'
& $raidGodot --path game --windowed --script res://tests/capture_raid_comparison.gd -- --output-dir=C:/ChatGPT/1942/tools/review/raid-after-repeat --build-id=source-1.8.0
& $raidGodot --main-pack tools/review/baseline-1.7.0/PacificStrike.exe --windowed --script C:/ChatGPT/1942/game/tests/capture_raid_comparison.gd -- --output-dir=C:/ChatGPT/1942/tools/review/raid-before-repeat --build-id=1.7.0
& $raidGodot --path game --windowed --script res://tests/capture_raid_terrain_tiling.gd -- --output-dir=C:/ChatGPT/1942/tools/review/raid-tiling-repeat
& $raidGodot --path game --windowed --script res://tests/test_raid_ui.gd -- --capture-ui --output-dir=C:/ChatGPT/1942/tools/review/raid-ui-repeat
```

Lancer ces commandes une à la fois. L'exécutable release officiel désactive `--script` ; la comparaison embarquée utilise donc le binaire éditeur avec `--main-pack`. Ces captures ne sont ni des parties humaines ni des mesures de FPS. Résultats fonctionnels et limites : `docs/validation/raids-1.8.txt`.
