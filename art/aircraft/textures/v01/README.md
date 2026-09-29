# Avion joueur — textures sources v01

Deux textures PNG créées avec l'outil image_gen intégré à partir de la planche validée dans la conversation. Résolution native : 1254 × 1254 pixels chacune, sans agrandissement artificiel.

## Fichiers

- aircraft-atlas-color-source.png : atlas visuel préliminaire. Ailes olive et grises, flancs, empennages, capot jaune, hélices et éléments secondaires. Les formes générées ne constituent pas le dépliage UV d'un maillage existant.
- aircraft-paint-trim-color-source.png : quatre bandes de peinture, de haut en bas : olive, gris, jaune, anthracite. Source de couleur pour raccords et petites pièces. Répétition horizontale non vérifiée.
- generation-prompts.txt : prompts complets pour reproduire la direction artistique.

## État de production

Ce pack est une base artistique pour le futur modèle, pas un jeu de maps PBR final certifié AAA. Aucun modèle ni UV n'existe à ce stade. L'atlas présente des reflets et ombres résiduels, notamment sur le fuselage et les pièces circulaires. Les retirer avant d'en faire une albedo finale éclairée par le moteur. Les détails et proportions des îlots devront être ajustés au modèle ; ne pas contraindre une bonne géométrie à ces contours générés.

Importer les deux sources couleur en sRGB. Verrière à construire comme matériau séparé, sans réflexion peinte. Les insignes de l'atlas sont déjà intégrés à la couleur.

## Réglages PBR de départ (à calibrer en scène)

| Surface | Metallic | Roughness | Remarque |
| --- | --- | --- | --- |
| Peinture olive / grise | 0.0 | 0.48–0.62 | La peinture sur métal reste diélectrique |
| Peinture jaune | 0.0 | 0.42–0.55 | Éviter l'effet plastique brillant |
| Hélices peintes | 0.0 | 0.40–0.55 | Pointes jaunes |
| Métal réellement dénudé | 1.0 | 0.28–0.45 | Masque local seulement |
| Verrière | 0.0 | 0.08–0.16 | IOR de départ 1.45, transmission selon moteur |

Ces valeurs sont des propositions de matériau, pas des cartes livrées. Ne pas convertir simplement la luminosité de la couleur en metallic, normal ou roughness : peinture, insignes et éclairage résiduel produiraient des reliefs et réflexions erronés.

## Finalisation avec le futur modèle

1. Modéliser la silhouette de référence ; séparer verrière et hélice.
2. Déplier les UV, réserver assez de texels aux surfaces supérieures et prévoir les gouttières pour les mipmaps.
3. Reprojeter et retoucher ces sources sur les UV réels, supprimer les reflets peints et corriger les raccords.
4. Produire les normales à partir de reliefs contrôlés ou d'un bake ; créer les masques roughness / metallic correspondant exactement aux UV.
5. Exporter les textures finales en 1024 ou 2048 selon la taille réelle à l'écran, avec padding et mipmaps. Une source de 1254 px ne devient pas du vrai détail 4K par agrandissement.
6. Vérifier sous plusieurs éclairages, puis à la distance de caméra du jeu : pas de scintillement des rivets, étoile et nez jaune lisibles, raccords invisibles.
