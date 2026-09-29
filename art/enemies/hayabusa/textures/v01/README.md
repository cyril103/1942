# Textures du Hayabusa

- `hayabusa-paint-basecolor.png` : source imagegen, camouflage olive/aluminium,
  aluminium nu, capot sombre et jaune. Prompt complet : `paint.prompt.txt`.
- `hayabusa_basecolor.png` : couleur sans éclairage, marquages compris.
- `hayabusa_roughness.png` : rugosité, niveaux de gris.
- `hayabusa_metallic.png` : métal, niveaux de gris.
- `hayabusa_normal.png` : normale tangentielle OpenGL (+Y), microrelief de matériau.

Les quatre cartes finales mesurent 2048 × 2048 et correspondent aux UV du fichier
`blender/hayabusa/hayabusa.glb`, pas aux silhouettes de la planche conceptuelle.
Basecolor utilise sRGB ; roughness, metallic et normal utilisent Non-Color.
La version Blender PBR et le GLB embarquent leurs textures.

Les bandes de la source générée ne sont pas parfaitement égales : leur position
réelle est prise en compte par le script d'affectation des UV. La peinture est
ensuite transférée vers l'atlas final par cuisson dans Blender.
