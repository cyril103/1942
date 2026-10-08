CAPTURES COMPARABLES — LISIBILITÉ 1.8 / 1.9

Chaque sous-dossier contient 36 PNG et captures.json (schéma 2).
Les huit situations de contacts/panneaux/mobilité et les dix situations de
fond/explosion existent en sortie 1280x720 et 1920x1080. Le viewport de jeu
reste 1920x972 ; il ne s'agit pas d'une comparaison de résolutions internes.

Les scènes sont posées et figées pour la comparaison. Pas de mesure de FPS,
de session humaine ni de validation de la fluidité à partir de ces images.
La provenance distingue code chargé par ResourceLoader, observations runtime
et diagnostic de texte local ; un hash de texte local n'identifie pas à lui
seul le code du pack exécuté.

comparison.json : 36 paires, 72 PNG vérifiés par hash, poses concordantes,
12 différences attendues de kind pour l'intention de mouvement de la DCA.
Comparateur reproductible : game/tests/compare_readability_captures.py.
Politique, inspection des 36 images après et limites :
docs/validation/lisibilite-1.9.txt.

Packs immuables utilisés (SHA256 EXE) :
1.8 : 83399D4C520D6B71FAFC86C529C9B39FBC8A2C092296FCAA9DDA7F291A410B14
1.9 : 28D3229336C09AB7872F2DEC359287E3B5607E6FF470806277227E687BD2B311

Les chemins absolus des manifests décrivent le poste de génération. Les
fichiers sont archivés ici avec leurs noms et octets d'origine.
