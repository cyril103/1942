# Validation de la campagne — 5 octobre 2026

Branche : `codex/jeu-final`. Godot 4.7.2, Windows x64, rendu Compatibility/OpenGL, GPU NVIDIA GTX 1650.

## Résultats

- Campagne : **380 contrôles, zéro échec**. Parcours des 32 chronologies, totalité des événements, trois phases des huit boss, acteurs bornés, victoire/défaite/reprise, pause/options, achats, sauvegarde atomique et récupération du backup.
- Intégration sur le paquet exporté : **10 contrôles, zéro échec**. Chargement des données et crédits, sauvegarde dans un fichier utilisateur de test, POW conservé, décollage complet, tirs continus, destruction d'un navire par de vrais projectiles, dégâts réels au boss, impact ennemi sur la coque.
- Mix audio enregistré pendant ce test : crête **18 131 / 32 767** (environ −5,1 dBFS), RMS 0,066. Moteur, musique et tirs audibles sans écrêtage dans cette séquence ; ce n'est pas une mesure de toutes les combinaisons possibles de sons.
- Vol : **9 615 contrôles**, zéro échec ; décollage : **4 240**, zéro échec.
- Décor : **2 921 contrôles**, zéro échec, 30 minutes simulées, 230 recyclages et nombre de nœuds constant.
- Régressions : combat **5 691**, bombardier **1 611**, formation rouge/POW **1 928**, zéro échec. Tirs continus sur 300 secondes, pool borné.
- Séquence GPU avec formation latérale, navires et tirs : environ **60 images/s en moyenne**, avec et sans ombres. Mesure courte sur cette machine ; elle ne constitue pas une garantie sur tous les niveaux ou matériels.

Les résultats structurés sont dans `game/tests/*results.json`. Les scripts de tests sont exclus de la distribution. Les captures `renders/campaign-*.png` proviennent du moteur réel. La passe visuelle couvre accueil, carte, hangar, briefing, options, pause, fin de campagne et six rencontres de boss/ambiances.

Livraison : `dist/PacificStrike-Windows-x64.zip`, contenant l'exécutable autonome, le manuel et les licences. SHA-256 de `PacificStrike.exe` : `083511878475EED3771297E1B02F7D3BDA89221479A6D4F2BE0E63B05AB20140`.

## Défauts trouvés et corrigés

- Fond d'accueil masquant le viewport de jeu : ordre des enfants corrigé.
- Carte des missions : marges des boutons réduites pour éviter leur chevauchement.
- Navires traversant le terrain : passages centraux dégagés dans les missions navales.
- Deux tirs centrés passant autour des petits navires : collision élargie de 0,85 à 1,2 unité et vérifiée avec les vrais projectiles.
- Texte long du bilan débordant à droite : dimensions appliquées après les paramètres de retour à la ligne et de police.
- Compte à rebours à zéro pendant les boss : indicateur « CONTACT MAJEUR » sans faux décompte de sortie.
- Tests graphiques suspendus lorsque la fenêtre perd le focus : l'autopause reste active en jeu mais est désactivée dans les tests instrumentés.

## Portée et limites

Le parcours des 32 niveaux est automatisé avec dégâts simulés. Les collisions sont testées séparément avec la physique réelle, puis des séquences GPU sont inspectées. **Aucune partie humaine intégrale des 32 missions n'est revendiquée.** L'équilibrage des difficultés et des améliorations pourra évoluer avec les parties du joueur.

Le jeu est solo. Les trois choix de hangar sont trois configurations du même avion, pas trois modèles différents. Les 32 niveaux ont des chronologies, noms et objectifs distincts ; ils partagent huit ambiances et les familles d'ennemis existantes, complétées par les navires et boss.

Les tests headless peuvent émettre des messages du moteur Dummy sur les matériaux ; les lancements sous restrictions d'accès peuvent aussi signaler un cache ou magasin de certificats inaccessible. Le test du paquet avec accès normal au dossier utilisateur n'émet pas d'erreur. Les tests graphiques confirment le rendu des matériaux.

La finition est celle d'un jeu indépendant réalisé dans ce projet ; « AAA » n'est pas une certification de qualité ni une validation de production que ces contrôles permettraient d'affirmer.
