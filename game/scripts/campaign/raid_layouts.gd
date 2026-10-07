extends RefCounted
## Pure authored raid catalogue: no scene creation, input mutation or live RNG.
## One coordinate contract for targets, service roads, mobile routes and airstrips.
## Normalized z = +1 is the incoming coast (seen first); -1 is the exit coast.
## x/z multiply the reachable half-width and the coastal half-length minus 16 m.
## All gameplay positions and route waypoints stay at Y=0. Visual altitude belongs
## to GroundAssault / GroundTarget, exactly as in the current game.

const VERSION := 1
const JAM_SECONDS := 6.0
const COAST_MARGIN := 16.0
const CLEARANCE := 0.25
const MIN_SAFE_HALF_WIDTH := 7.0
const COMPACT_BELOW_HALF_WIDTH := 13.0
const MIN_TARGET_HALF_LENGTH := [42.0, 48.0, 55.0, 60.0, 67.0, 74.0, 81.0, 90.0]
# These are geometry reservations, not alternate combat colliders. Runtime
# collider and full-weapon proofs live in the ground-encounter tests.
const FOOTPRINT := {
	"battery": Vector2(2.8, 2.8), "bunker": Vector2(3.2, 2.5),
	"fuel": Vector2(3.3, 2.8), "radar": Vector2(2.6, 2.6),
	"runway": Vector2(4.0, 5.2)
}

# Authored rows: stable short ID, existing variant, normalized x, normalized z,
# optional radar-group ID. No repeating five-column row generator is used.
# Roads are world-width corridors; strips have a world half-width and normalized
# half-length. Targets must clear these corridors including their footprint.
# Mobile batteries deliberately occupy a road, never an airstrip or a building.
const LAYOUTS := [
	{
		"id": "coral", "sector": 0, "mission": 3, "biome": "coral",
		"title": "Clairières du lagon", "quota": 12,
		"signature": "Première ligne active, puis deux fenêtres de brouillage global.",
		"learning": "Un radar interrompt temporairement toute la DCA. Les canons de la plage tirent avant le premier radar.",
		"targets": [
			["b01", "battery", -.70, .94, "lagoon"],
			["b02", "battery", -.30, .91, "lagoon"],
			["b03", "battery", .31, .87, "lagoon"],
			["b04", "battery", .71, .91, "lagoon"],
			["b05", "battery", -.62, .72, "lagoon"],
			["b06", "battery", .58, .68, "lagoon"],
			["b07", "battery", -.29, .51, "lagoon"],
			["b08", "battery", .69, .48, "lagoon"],
			["b09", "battery", -.73, .29, "lagoon"],
			["b10", "battery", .32, .25, "lagoon"],
			["b11", "battery", -.30, .03, "lagoon"],
			["b12", "battery", .72, -.02, "lagoon"],
			["b13", "battery", -.69, -.21, "lagoon"],
			["b14", "battery", .30, -.25, "lagoon"],
			["b15", "battery", -.29, -.53, "lagoon"],
			["b16", "battery", -.70, -.72, "lagoon"],
			["b17", "battery", .31, -.86, "lagoon"],
			["b18", "battery", .72, -.89, "lagoon"],
			["k01", "bunker", -.73, .52, "lagoon"],
			["k02", "bunker", .31, .49, "lagoon"],
			["k03", "bunker", -.72, .04, "lagoon"],
			["k04", "bunker", .68, -.26, "lagoon"],
			["k05", "bunker", -.70, -.49, "lagoon"],
			["k06", "bunker", .72, -.71, "lagoon"],
			["f01", "fuel", .32, .34],
			["f02", "fuel", .33, -.04],
			["f03", "fuel", -.32, -.74],
			["r01", "radar", -.29, .62, "lagoon"],
			["r02", "radar", .31, -.65, "lagoon"],
			["h01", "runway", .43, -.48]
		],
		"rapid_ids": ["b02", "b06", "b11", "b14", "b17"],
		"priority_ids": [], "priority_tags": {},
		"secondary": {"label": "Neutraliser les deux stations radar", "ids": ["r01", "r02"], "minimum": 2},
		"radars": {"lagoon": {"label": "Réseau du lagon", "global": true}},
		"routes": {
			"coral-spine": {"usage": "service", "width": 1.0, "points": [Vector2(0, .98), Vector2(0, -.98)]},
			"coral-west-access": {"usage": "service", "width": .8, "points": [Vector2(0, .40), Vector2(-.59, .40)]},
			"coral-airfield-access": {"usage": "service", "width": .8, "points": [Vector2(0, -.36), Vector2(.76, -.36)]}
		},
		"runways": [{"id": "coral-strip", "center": Vector2(.78, -.51), "half_width": 1.25, "half_length": .105}],
		"mobile_routes": {}
	},
	{
		"id": "convoy", "sector": 1, "mission": 7, "biome": "convoy",
		"title": "Dépôts de la route côtière", "quota": 14,
		"signature": "Deux dépôts rapprochés par complexe ; choisir carburant ou canon.",
		"learning": "Les explosions de dépôts blessent les installations voisines. Aucun bateau ne traverse ce terrain.",
		"targets": [
			["b01", "battery", -.72, .93, "logistics"],
			["b02", "battery", .40, .91, "logistics"],
			["b03", "battery", .77, .75, "logistics"],
			["b04", "battery", -.30, .73, "logistics"],
			["b05", "battery", -.65, .51, "logistics"],
			["b06", "battery", .32, .53, "logistics"],
			["b07", "battery", .72, .34, "logistics"],
			["b08", "battery", -.70, .29, "logistics"],
			["b09", "battery", .32, .12, "logistics"],
			["b10", "battery", -.32, .06, "logistics"],
			["b11", "battery", .73, -.315, "logistics"],
			["b12", "battery", -.71, -.14, "logistics"],
			["b13", "battery", .63, -.44, "logistics"],
			["b14", "battery", -.34, -.42, "logistics"],
			["b15", "battery", -.73, -.61, "logistics"],
			["b16", "battery", .32, -.71, "logistics"],
			["b17", "battery", -.33, -.86, "logistics"],
			["b18", "battery", .73, -.89, "logistics"],
			["k01", "bunker", -.30, .94, "logistics"],
			["k02", "bunker", -.76, .73, "logistics"],
			["k03", "bunker", .74, .55, "logistics"],
			["k04", "bunker", -.32, .29, "logistics"],
			["k05", "bunker", .72, .13, "logistics"],
			["k06", "bunker", -.32, -.16, "logistics"],
			["k07", "bunker", -.74, -.38, "logistics"],
			["k08", "bunker", .73, -.67, "logistics"],
			["f01", "fuel", -.34, .51],
			["f02", "fuel", -.48, .44],
			["f03", "fuel", .33, -.44],
			["f04", "fuel", .47, -.37],
			["r01", "radar", .32, .32, "logistics"],
			["h01", "runway", .42, -.14]
		],
		"rapid_ids": ["b02", "b05", "b09", "b13", "b15", "b18"],
		"priority_ids": [], "priority_tags": {},
		"secondary": {"label": "Détruire trois dépôts de carburant", "ids": ["f01", "f02", "f03", "f04"], "minimum": 3},
		"radars": {"logistics": {"label": "Réseau logistique", "global": false}},
		"routes": {
			"convoy-service-road": {"usage": "service", "width": 1.15, "points": [Vector2(.03, .98), Vector2(-.03, .62), Vector2(.03, .19), Vector2(-.03, -.26), Vector2(.03, -.98)]},
			"convoy-north-depot": {"usage": "service", "width": .75, "points": [Vector2(-.03, .62), Vector2(-.58, .62)]},
			"convoy-south-depot": {"usage": "service", "width": .75, "points": [Vector2(-.03, -.26), Vector2(.69, -.26)]}
		},
		"runways": [{"id": "convoy-strip", "center": Vector2(.78, -.10), "half_width": 1.2, "half_length": .09}],
		"mobile_routes": {}
	},
	{
		"id": "storm", "sector": 2, "mission": 11, "biome": "storm",
		"title": "Trois réseaux sous la mousson", "quota": 14,
		"signature": "Trois complexes indépendants, dont deux radars prioritaires.",
		"learning": "Le brouillage reste local : les autres réseaux continuent de tirer.",
		"targets": [
			["b01", "battery", -.78, .93, "west"],
			["b02", "battery", -.32, .87, "west"],
			["b03", "battery", -.72, .70, "west"],
			["b04", "battery", -.30, .61, "west"],
			["b05", "battery", -.77, .46, "west"],
			["b06", "battery", -.30, .37, "west"],
			["b07", "battery", .32, .68, "east"],
			["b08", "battery", .77, .60, "east"],
			["b09", "battery", .32, .43, "east"],
			["b10", "battery", .76, .35, "east"],
			["b11", "battery", .32, .16, "east"],
			["b12", "battery", .77, .09, "east"],
			["b13", "battery", -.76, -.24, "south"],
			["b14", "battery", -.31, -.35, "south"],
			["b15", "battery", .31, -.47, "south"],
			["b16", "battery", .77, -.65, "south"],
			["b17", "battery", -.75, -.82, "south"],
			["b18", "battery", .32, -.89, "south"],
			["k01", "bunker", -.75, .84, "west"],
			["k02", "bunker", -.32, .46, "west"],
			["k03", "bunker", -.74, .28, "west"],
			["k04", "bunker", .76, .77, "east"],
			["k05", "bunker", .32, .32, "east"],
			["k06", "bunker", .77, -.02, "east"],
			["k07", "bunker", -.31, -.23, "south"],
			["k08", "bunker", .77, -.43, "south"],
			["k09", "bunker", -.74, -.66, "south"],
			["k10", "bunker", .74, -.88, "south"],
			["f01", "fuel", -.32, .75],
			["f02", "fuel", .32, -.69],
			["r01", "radar", -.32, .94, "west"],
			["r02", "radar", .32, .83, "east"],
			["r03", "radar", -.31, -.51, "south"],
			["h01", "runway", -.43, -.05]
		],
		"rapid_ids": ["b02", "b04", "b07", "b10", "b13", "b15", "b18"],
		"priority_ids": ["r01", "r02"], "priority_tags": {"r01": "western_radar", "r02": "eastern_radar"},
		"secondary": {"label": "Neutraliser les trois réseaux radar", "ids": ["r01", "r02", "r03"], "minimum": 3},
		"radars": {
			"west": {"label": "Réseau Ouest", "global": false},
			"east": {"label": "Réseau Est", "global": false},
			"south": {"label": "Réseau arrière", "global": false}
		},
		"routes": {
			"storm-drainage-road": {"usage": "service", "width": .95, "points": [Vector2(0, .98), Vector2(0, -.98)]},
			"storm-west-access": {"usage": "service", "width": .7, "points": [Vector2(0, .55), Vector2(-.60, .55)]},
			"storm-east-access": {"usage": "service", "width": .7, "points": [Vector2(0, .53), Vector2(.60, .53)]},
			"storm-south-access": {"usage": "service", "width": .7, "points": [Vector2(0, -.58), Vector2(-.59, -.58)]}
		},
		"runways": [{"id": "storm-strip", "center": Vector2(-.78, -.07), "half_width": 1.2, "half_length": .085}],
		"mobile_routes": {}
	},
	{
		"id": "jade", "sector": 3, "mission": 15, "biome": "jade",
		"title": "Les deux aérodromes de Jade", "quota": 16,
		"signature": "Trois hangars prioritaires autour de deux pistes décalées.",
		"learning": "Traversez pendant la récupération des rafales ; trois hangars sont requis, le quatrième rapporte le secondaire.",
		"targets": [
			["b01", "battery", -.31, .94, "airfield"],
			["b02", "battery", .69, .92, "airfield"],
			["b03", "battery", -.76, .83, "airfield"],
			["b04", "battery", .28, .81, "airfield"],
			["b05", "battery", -.32, .69, "airfield"],
			["b06", "battery", .70, .67, "airfield"],
			["b07", "battery", -.31, .51, "airfield"],
			["b08", "battery", .29, .48, "airfield"],
			["b09", "battery", -.31, .27, "airfield"],
			["b10", "battery", .76, .28, "airfield"],
			["b11", "battery", -.72, .06, "airfield"],
			["b12", "battery", .30, .05, "airfield"],
			["b13", "battery", -.32, -.12, "airfield"],
			["b14", "battery", .30, -.18, "airfield"],
			["b15", "battery", -.73, -.26, "airfield"],
			["b16", "battery", -.31, -.40, "airfield"],
			["b17", "battery", .29, -.42, "airfield"],
			["b18", "battery", -.72, -.53, "airfield"],
			["b19", "battery", -.29, -.63, "airfield"],
			["b20", "battery", .30, -.70, "airfield"],
			["b21", "battery", -.72, -.88, "airfield"],
			["b22", "battery", .75, -.88, "airfield"],
			["k01", "bunker", .72, .81, "airfield"],
			["k02", "bunker", .30, .65, "airfield"],
			["k03", "bunker", .73, .48, "airfield"],
			["k04", "bunker", .30, .26, "airfield"],
			["k05", "bunker", -.72, -.12, "airfield"],
			["k06", "bunker", -.72, -.70, "airfield"],
			["k07", "bunker", -.30, -.88, "airfield"],
			["f01", "fuel", -.31, .08],
			["f02", "fuel", .29, -.85],
			["r01", "radar", .30, .94, "airfield"],
			["h01", "runway", -.37, .39],
			["h02", "runway", -.37, .60],
			["h03", "runway", .38, -.31],
			["h04", "runway", .38, -.57]
		],
		"rapid_ids": ["b01", "b04", "b07", "b10", "b13", "b17", "b20"],
		"priority_ids": ["h01", "h02", "h03"], "priority_tags": {"h01": "western_hangar", "h02": "western_hangar", "h03": "eastern_hangar"},
		"secondary": {"label": "Détruire les quatre hangars des deux aérodromes", "ids": ["h01", "h02", "h03", "h04"], "minimum": 4},
		"radars": {"airfield": {"label": "Réseau des aérodromes", "global": false}},
		"routes": {
			"jade-central-service": {"usage": "service", "width": 1.0, "points": [Vector2(0, .98), Vector2(0, -.98)]},
			"jade-west-taxiway": {"usage": "taxiway", "width": .75, "points": [Vector2(0, .31), Vector2(-.77, .31)]},
			"jade-east-taxiway": {"usage": "taxiway", "width": .75, "points": [Vector2(0, -.49), Vector2(.77, -.49)]}
		},
		"runways": [
			{"id": "jade-west-strip", "center": Vector2(-.77, .48), "half_width": 1.25, "half_length": .20},
			{"id": "jade-east-strip", "center": Vector2(.77, -.40), "half_width": 1.25, "half_length": .22}
		],
		"mobile_routes": {}
	},
	{
		"id": "volcanic", "sector": 4, "mission": 19, "biome": "volcanic",
		"title": "La route des batteries mobiles", "quota": 18,
		"signature": "Deux véhicules successifs isolés, puis quatre mobiles dans des groupes fixes.",
		"learning": "La DCA mobile annonce son déplacement, s'arrête puis prépare sa rafale. Les deux premiers véhicules sont prioritaires.",
		"targets": [
			["m01", "battery", -.17, .94, "cinder"],
			["m02", "battery", .14, .70, "cinder"],
			["m03", "battery", -.28, .34, "cinder"],
			["m04", "battery", .27, -.06, "cinder"],
			["m05", "battery", -.28, -.44, "cinder"],
			["m06", "battery", .27, -.77, "cinder"],
			["b01", "battery", -.74, .47, "cinder"],
			["b02", "battery", .73, .45, "cinder"],
			["b03", "battery", -.32, .47, "cinder"],
			["b04", "battery", .31, .36, "cinder"],
			["b05", "battery", -.76, .32, "cinder"],
			["b06", "battery", .73, .26, "cinder"],
			["b07", "battery", -.33, .16, "cinder"],
			["b08", "battery", .32, .14, "cinder"],
			["b09", "battery", -.73, -.08, "cinder"],
			["b10", "battery", .74, -.14, "cinder"],
			["b11", "battery", -.31, -.23, "cinder"],
			["b12", "battery", .32, -.29, "cinder"],
			["b13", "battery", -.75, -.43, "cinder"],
			["b14", "battery", .74, -.52, "cinder"],
			["b15", "battery", -.31, -.65, "cinder"],
			["b16", "battery", -.74, -.88, "cinder"],
			["k01", "bunker", -.72, .40, "cinder"],
			["k02", "bunker", .74, .38, "cinder"],
			["k03", "bunker", .31, .31, "cinder"],
			["k04", "bunker", -.73, .13, "cinder"],
			["k05", "bunker", -.33, -.09, "cinder"],
			["k06", "bunker", .75, -.33, "cinder"],
			["k07", "bunker", -.74, -.66, "cinder"],
			["k08", "bunker", .74, -.90, "cinder"],
			["f01", "fuel", .32, -.51],
			["f02", "fuel", -.32, -.88],
			["r01", "radar", .32, .55, "cinder"],
			["h01", "runway", .42, -.67]
		],
		"rapid_ids": ["b01", "b04", "b07", "b10", "b13", "b16", "m03", "m05"],
		"priority_ids": ["m01", "m02"], "priority_tags": {"m01": "tutorial_mobile", "m02": "tutorial_mobile"},
		"secondary": {"label": "Détruire les quatre batteries mobiles des complexes", "ids": ["m03", "m04", "m05", "m06"], "minimum": 4},
		"radars": {"cinder": {"label": "Réseau des cendres", "global": false}},
		"routes": {
			"volcanic-service-road": {"usage": "service", "width": 1.05, "points": [Vector2(0, .98), Vector2(0, -.98)]},
			# 4.5 m also contains the full 2.8 m square at circular road caps:
			# half diagonal sqrt(1.4^2 + 1.4^2), plus 0.25 m clearance.
			"volcanic-intro-west": {"usage": "mobile", "width": 4.5, "points": [Vector2(-.17, .94), Vector2(.015, .94)]},
			"volcanic-intro-east": {"usage": "mobile", "width": 4.5, "points": [Vector2(.14, .70), Vector2(-.045, .70)]},
			"volcanic-mobile-north-west": {"usage": "mobile", "width": 4.5, "points": [Vector2(-.28, .34), Vector2(-.105, .34)]},
			"volcanic-mobile-north-east": {"usage": "mobile", "width": 4.5, "points": [Vector2(.27, -.06), Vector2(.105, -.06)]},
			"volcanic-mobile-south-west": {"usage": "mobile", "width": 4.5, "points": [Vector2(-.28, -.44), Vector2(-.105, -.44)]},
			"volcanic-mobile-south-east": {"usage": "mobile", "width": 4.5, "points": [Vector2(.27, -.77), Vector2(.105, -.77)]},
			"volcanic-strip-access": {"usage": "service", "width": .7, "points": [Vector2(0, -.57), Vector2(.77, -.57)]}
		},
		"runways": [{"id": "volcanic-strip", "center": Vector2(.78, -.68), "half_width": 1.2, "half_length": .075}],
		"mobile_routes": {
			"m01": "volcanic-intro-west", "m02": "volcanic-intro-east",
			"m03": "volcanic-mobile-north-west", "m04": "volcanic-mobile-north-east",
			"m05": "volcanic-mobile-south-west", "m06": "volcanic-mobile-south-east"
		}
	},
	{
		"id": "dusk", "sector": 5, "mission": 23, "biome": "dusk",
		"title": "Les deux bastions du crépuscule", "quota": 20,
		"signature": "Bastions Est et Ouest simultanés ; choisir son ordre entre les visées verrouillées.",
		"learning": "L'amorce verrouille la visée. Changez de côté après l'annonce ; les deux bastions sont requis.",
		"targets": [
			["b01", "battery", -.74, .94, "west"],
			["b02", "battery", .32, .86, "east"],
			["b03", "battery", -.33, .73, "west"],
			["b04", "battery", .73, .68, "east"],
			["b05", "battery", -.74, .51, "west"],
			["b06", "battery", .31, .48, "east"],
			["b07", "battery", -.32, .30, "west"],
			["b08", "battery", .31, .26, "east"],
			["b09", "battery", -.74, -.08, "west"],
			["b10", "battery", .73, -.11, "east"],
			["b11", "battery", -.32, -.25, "west"],
			["b12", "battery", .31, -.38, "east"],
			["b13", "battery", -.74, -.54, "west"],
			["b14", "battery", .73, -.64, "east"],
			["b15", "battery", -.32, -.85, "west"],
			["b16", "battery", .74, -.91, "east"],
			["k01", "bunker", -.32, .94, "west"],
			["k02", "bunker", .73, .86, "east"],
			["k03", "bunker", -.74, .72, "west"],
			["k04", "bunker", .31, .66, "east"],
			["k05", "bunker", -.74, .16, "west"],
			["k06", "bunker", .74, .12, "east"],
			["k07", "bunker", -.32, -.07, "west"],
			["k08", "bunker", -.73, -.29, "west"],
			["k09", "bunker", .74, -.42, "east"],
			["k10", "bunker", .31, -.86, "east"],
			["f01", "fuel", -.33, -.54],
			["f02", "fuel", .31, -.62],
			["r01", "radar", -.33, .49, "west"],
			["r02", "radar", .74, .47, "east"],
			["h01", "runway", -.41, -.71],
			["h02", "runway", .41, -.16]
		],
		"rapid_ids": ["b01", "b03", "b06", "b07", "b10", "b11", "b14", "b16"],
		"priority_ids": ["k05", "k06"], "priority_tags": {"k05": "western_bastion", "k06": "eastern_bastion"},
		"secondary": {"label": "Neutraliser les radars des deux bastions", "ids": ["r01", "r02"], "minimum": 2},
		"radars": {"west": {"label": "Bastion Ouest", "global": false}, "east": {"label": "Bastion Est", "global": false}},
		"routes": {
			"dusk-diagonal-service": {"usage": "service", "width": .95, "points": [Vector2(.055, .98), Vector2(-.045, .59), Vector2(.045, .34), Vector2(-.045, -.02), Vector2(.045, -.47), Vector2(-.055, -.98)]},
			"dusk-bastion-link": {"usage": "service", "width": .7, "points": [Vector2(0, .04), Vector2(-.58, .04)]},
			"dusk-east-access": {"usage": "service", "width": .7, "points": [Vector2(0, .36), Vector2(.70, .36)]},
			"dusk-west-access": {"usage": "service", "width": .7, "points": [Vector2(0, -.78), Vector2(-.77, -.78)]}
		},
		"runways": [
			{"id": "dusk-west-strip", "center": Vector2(-.78, -.70), "half_width": 1.2, "half_length": .055},
			{"id": "dusk-east-strip", "center": Vector2(.78, -.20), "half_width": 1.2, "half_length": .05}
		],
		"mobile_routes": {}
	},
	{
		"id": "arctic", "sector": 6, "mission": 27, "biome": "arctic",
		"title": "Deux complexes du front boréal", "quota": 22,
		"signature": "Chaque complexe offre une ouverture radar et une ouverture carburant.",
		"learning": "Choisissez l'ouverture qui convient à votre arme, puis rejoignez l'autre complexe. Les deux dépôts forment le secondaire.",
		"targets": [
			["b01", "battery", -.73, .94, "west"],
			["b02", "battery", -.31, .88, "west"],
			["b03", "battery", -.75, .74, "west"],
			["b04", "battery", -.31, .68, "west"],
			["b05", "battery", -.73, .51, "west"],
			["b06", "battery", -.31, .44, "west"],
			["b07", "battery", -.73, .29, "west"],
			["b08", "battery", -.31, .20, "west"],
			["b09", "battery", -.73, .04, "west"],
			["b10", "battery", -.31, -.06, "west"],
			["b11", "battery", .73, .37, "east"],
			["b12", "battery", .31, .29, "east"],
			["b13", "battery", .73, .14, "east"],
			["b14", "battery", .31, .04, "east"],
			["b15", "battery", .73, -.09, "east"],
			["b16", "battery", .31, -.19, "east"],
			["b17", "battery", .31, -.41, "east"],
			["b18", "battery", .31, -.65, "east"],
			["b19", "battery", .73, -.88, "east"],
			["b20", "battery", .31, -.91, "east"],
			["k01", "bunker", -.31, .96, "west"],
			["k02", "bunker", -.73, .84, "west"],
			["k03", "bunker", -.31, .79, "west"],
			["k04", "bunker", -.73, .62, "west"],
			["k05", "bunker", -.73, .16, "west"],
			["k06", "bunker", -.31, .09, "west"],
			["k07", "bunker", .73, .48, "east"],
			["k08", "bunker", .31, .40, "east"],
			["k09", "bunker", .73, .26, "east"],
			["k10", "bunker", .31, -.07, "east"],
			["k11", "bunker", .73, -.74, "east"],
			["k12", "bunker", .31, -.78, "east"],
			["f01", "fuel", -.47, .48],
			["f02", "fuel", .48, .10],
			["r01", "radar", -.31, .57, "west"],
			["r02", "radar", .31, .52, "east"],
			["h01", "runway", -.41, -.33],
			["h02", "runway", .41, -.53]
		],
		"rapid_ids": ["b02", "b04", "b07", "b10", "b11", "b14", "b17", "b20"],
		"priority_ids": [], "priority_tags": {},
		"secondary": {"label": "Détruire les deux dépôts boréaux", "ids": ["f01", "f02"], "minimum": 2},
		"radars": {"west": {"label": "Complexe Ouest", "global": false}, "east": {"label": "Complexe Est", "global": false}},
		"routes": {
			"arctic-ice-road": {"usage": "service", "width": 1.1, "points": [Vector2(0, .98), Vector2(0, -.98)]},
			"arctic-west-link": {"usage": "service", "width": .7, "points": [Vector2(0, .35), Vector2(-.61, .35)]},
			"arctic-east-link": {"usage": "service", "width": .7, "points": [Vector2(0, -.30), Vector2(.77, -.30)]},
			"arctic-west-strip-access": {"usage": "service", "width": .7, "points": [Vector2(0, -.43), Vector2(-.78, -.43)]}
		},
		"runways": [
			{"id": "arctic-west-strip", "center": Vector2(-.78, -.33), "half_width": 1.2, "half_length": .075},
			{"id": "arctic-east-strip", "center": Vector2(.78, -.49), "half_width": 1.2, "half_length": .13}
		],
		"mobile_routes": {}
	},
	{
		"id": "final", "sector": 7, "mission": 31, "biome": "final",
		"title": "L'arsenal et son commandement", "quota": 26,
		"signature": "Trois ceintures ouvertes ; attaque directe du commandement ou préparation radar/carburant.",
		"learning": "Le bunker de commandement est requis. Vous pouvez l'attaquer directement ou neutraliser d'abord son réseau radar.",
		"targets": [
			["b01", "battery", -.74, .94, "outer"],
			["b02", "battery", -.32, .88, "outer"],
			["b03", "battery", .31, .84, "outer"],
			["b04", "battery", .74, .89, "outer"],
			["b05", "battery", -.73, .70, "outer"],
			["b06", "battery", .73, .68, "outer"],
			["b07", "battery", -.31, .59, "middle"],
			["b08", "battery", .31, .52, "middle"],
			["b09", "battery", -.73, .47, "middle"],
			["b10", "battery", .73, .45, "middle"],
			["b11", "battery", -.31, .33, "middle"],
			["b12", "battery", .31, .29, "middle"],
			["b13", "battery", -.73, .23, "inner"],
			["b14", "battery", .73, .22, "inner"],
			["b15", "battery", -.32, .07, "inner"],
			["b16", "battery", .33, .01, "inner"],
			["b17", "battery", -.73, -.19, "inner"],
			["b18", "battery", .73, -.22, "inner"],
			["b19", "battery", -.31, -.37, "inner"],
			["b20", "battery", .31, -.41, "inner"],
			["b21", "battery", -.31, -.69, "inner"],
			["b22", "battery", .73, -.91, "inner"],
			["k01", "bunker", -.31, .95, "outer"],
			["k02", "bunker", .31, .71, "outer"],
			["k03", "bunker", -.73, .59, "outer"],
			["k04", "bunker", .73, .55, "middle"],
			["k05", "bunker", -.31, .43, "middle"],
			["k06", "bunker", -.73, .34, "middle"],
			["k07", "bunker", .31, .15, "inner"],
			["command", "bunker", 0.0, -.16, "inner"],
			["k09", "bunker", -.73, -.45, "inner"],
			["k10", "bunker", .31, -.64, "inner"],
			["k11", "bunker", -.31, -.88, "inner"],
			["f01", "fuel", -.46, .76],
			["f02", "fuel", .47, .35],
			["f03", "fuel", -.48, -.13],
			["r01", "radar", .31, .95, "outer"],
			["r02", "radar", -.31, .20, "middle"],
			["r03", "radar", .38, -.17, "inner"],
			["h01", "runway", -.41, -.58]
		],
		"rapid_ids": ["b02", "b03", "b06", "b07", "b10", "b12", "b15", "b17", "b20", "b22"],
		"priority_ids": ["command"], "priority_tags": {"command": "command_bunker"},
		"secondary": {"label": "Neutraliser les trois radars de l'arsenal", "ids": ["r01", "r02", "r03"], "minimum": 3},
		"radars": {
			"outer": {"label": "Ceinture extérieure", "global": false},
			"middle": {"label": "Ceinture intermédiaire", "global": false},
			"inner": {"label": "Commandement", "global": false}
		},
		"routes": {
			"final-direct-approach": {"usage": "service", "width": 1.05, "points": [Vector2(0, .98), Vector2(0, -.11)]},
			"final-command-bypass": {"usage": "service", "width": .85, "points": [Vector2(0, -.11), Vector2(.20, -.11), Vector2(.20, -.23), Vector2(0, -.23), Vector2(0, -.98)]},
			"final-outer-west-access": {"usage": "service", "width": .7, "points": [Vector2(0, .80), Vector2(-.63, .80)]},
			"final-middle-east-access": {"usage": "service", "width": .7, "points": [Vector2(0, .39), Vector2(.62, .39)]},
			"final-strip-access": {"usage": "service", "width": .7, "points": [Vector2(0, -.77), Vector2(-.78, -.77)]}
		},
		"runways": [{"id": "final-strip", "center": Vector2(-.78, -.61), "half_width": 1.2, "half_length": .105}],
		"mobile_routes": {}
	}
]


# Compact authored placements preserve IDs, counts, networks and temporal budget.
# All rows, road vertices and strip centers are explicit, not a scaled five-row
# generator. Selected only while constructing a raid with half_x < 13 m.
# Four separated bands keep complete foundations reachable down to half_x=7 m;
# narrow depots/mobile complexes include their own authored depth adjustments.
const COMPACT_LAYOUTS := [
	{
		"targets": {
			"b01": Vector2(-0.95, 0.94),
			"b02": Vector2(-0.4, 0.91),
			"b03": Vector2(0.4, 0.87),
			"b04": Vector2(0.95, 0.91),
			"b05": Vector2(-0.95, 0.72),
			"b06": Vector2(0.95, 0.68),
			"b07": Vector2(-0.4, 0.51),
			"b08": Vector2(0.95, 0.48),
			"b09": Vector2(-0.95, 0.29),
			"b10": Vector2(0.4, 0.25),
			"b11": Vector2(-0.4, 0.03),
			"b12": Vector2(0.95, -0.02),
			"b13": Vector2(-0.95, -0.21),
			"b14": Vector2(0.4, -0.25),
			"b15": Vector2(-0.4, -0.53),
			"b16": Vector2(-0.95, -0.72),
			"b17": Vector2(0.4, -0.86),
			"b18": Vector2(0.95, -0.89),
			"k01": Vector2(-0.95, 0.52),
			"k02": Vector2(0.4, 0.49),
			"k03": Vector2(-0.95, 0.04),
			"k04": Vector2(0.95, -0.26),
			"k05": Vector2(-0.95, -0.49),
			"k06": Vector2(0.95, -0.71),
			"f01": Vector2(0.4, 0.34),
			"f02": Vector2(0.4, -0.04),
			"f03": Vector2(-0.4, -0.74),
			"r01": Vector2(-0.4, 0.62),
			"r02": Vector2(0.4, -0.65),
			"h01": Vector2(0.4, -0.48)
		},
		"routes": {
			"coral-spine": [Vector2(0.0, 0.98), Vector2(0.0, -0.98)],
			"coral-west-access": [Vector2(0.0, 0.4), Vector2(-0.95, 0.4)],
			"coral-airfield-access": [Vector2(0.0, -0.36), Vector2(0.95, -0.36)]
		},
		"runways": {
			"coral-strip": Vector2(0.95, -0.51)
		}
	},
	{
		"targets": {
			"b01": Vector2(-0.95, 0.93),
			"b02": Vector2(0.4, 0.91),
			"b03": Vector2(0.95, 0.75),
			"b04": Vector2(-0.4, 0.73),
			"b05": Vector2(-0.95, 0.51),
			"b06": Vector2(0.4, 0.53),
			"b07": Vector2(0.95, 0.34),
			"b08": Vector2(-0.95, 0.29),
			"b09": Vector2(0.4, 0.12),
			"b10": Vector2(-0.4, 0.06),
			"b11": Vector2(0.95, -0.315),
			"b12": Vector2(-0.95, -0.14),
			"b13": Vector2(0.95, -0.44),
			"b14": Vector2(-0.4, -0.42),
			"b15": Vector2(-0.95, -0.61),
			"b16": Vector2(0.4, -0.71),
			"b17": Vector2(-0.4, -0.86),
			"b18": Vector2(0.95, -0.89),
			"k01": Vector2(-0.4, 0.94),
			"k02": Vector2(-0.95, 0.73),
			"k03": Vector2(0.95, 0.55),
			"k04": Vector2(-0.4, 0.29),
			"k05": Vector2(0.95, 0.13),
			"k06": Vector2(-0.4, -0.16),
			"k07": Vector2(-0.95, -0.38),
			"k08": Vector2(0.95, -0.67),
			"f01": Vector2(-0.4, 0.51),
			"f02": Vector2(-0.95, 0.44),
			"f03": Vector2(0.4, -0.44),
			"f04": Vector2(0.95, -0.52),
			"r01": Vector2(0.4, 0.32),
			"h01": Vector2(0.4, -0.14)
		},
		"routes": {
			"convoy-service-road": [Vector2(0.03, 0.98), Vector2(-0.03, 0.62), Vector2(0.03, 0.19), Vector2(-0.03, -0.26), Vector2(0.03, -0.98)],
			"convoy-north-depot": [Vector2(-0.03, 0.62), Vector2(-0.95, 0.62)],
			"convoy-south-depot": [Vector2(-0.03, -0.26), Vector2(0.95, -0.26)]
		},
		"runways": {
			"convoy-strip": Vector2(0.95, -0.1)
		}
	},
	{
		"targets": {
			"b01": Vector2(-0.95, 0.93),
			"b02": Vector2(-0.4, 0.87),
			"b03": Vector2(-0.95, 0.7),
			"b04": Vector2(-0.4, 0.61),
			"b05": Vector2(-0.95, 0.46),
			"b06": Vector2(-0.4, 0.37),
			"b07": Vector2(0.4, 0.68),
			"b08": Vector2(0.95, 0.6),
			"b09": Vector2(0.4, 0.43),
			"b10": Vector2(0.95, 0.35),
			"b11": Vector2(0.4, 0.16),
			"b12": Vector2(0.95, 0.09),
			"b13": Vector2(-0.95, -0.24),
			"b14": Vector2(-0.4, -0.35),
			"b15": Vector2(0.4, -0.47),
			"b16": Vector2(0.95, -0.65),
			"b17": Vector2(-0.95, -0.82),
			"b18": Vector2(0.4, -0.89),
			"k01": Vector2(-0.95, 0.84),
			"k02": Vector2(-0.4, 0.46),
			"k03": Vector2(-0.95, 0.28),
			"k04": Vector2(0.95, 0.77),
			"k05": Vector2(0.4, 0.32),
			"k06": Vector2(0.95, -0.02),
			"k07": Vector2(-0.4, -0.23),
			"k08": Vector2(0.95, -0.43),
			"k09": Vector2(-0.95, -0.66),
			"k10": Vector2(0.95, -0.88),
			"f01": Vector2(-0.4, 0.75),
			"f02": Vector2(0.4, -0.69),
			"r01": Vector2(-0.4, 0.94),
			"r02": Vector2(0.4, 0.83),
			"r03": Vector2(-0.4, -0.51),
			"h01": Vector2(-0.4, -0.05)
		},
		"routes": {
			"storm-drainage-road": [Vector2(0.0, 0.98), Vector2(0.0, -0.98)],
			"storm-west-access": [Vector2(0.0, 0.55), Vector2(-0.95, 0.55)],
			"storm-east-access": [Vector2(0.0, 0.53), Vector2(0.95, 0.53)],
			"storm-south-access": [Vector2(0.0, -0.58), Vector2(-0.95, -0.58)]
		},
		"runways": {
			"storm-strip": Vector2(-0.95, -0.07)
		}
	},
	{
		"targets": {
			"b01": Vector2(-0.4, 0.94),
			"b02": Vector2(0.95, 0.92),
			"b03": Vector2(-0.95, 0.83),
			"b04": Vector2(0.4, 0.81),
			"b05": Vector2(-0.4, 0.69),
			"b06": Vector2(0.95, 0.67),
			"b07": Vector2(-0.4, 0.51),
			"b08": Vector2(0.4, 0.48),
			"b09": Vector2(-0.4, 0.27),
			"b10": Vector2(0.95, 0.28),
			"b11": Vector2(-0.95, 0.06),
			"b12": Vector2(0.4, 0.05),
			"b13": Vector2(-0.4, -0.12),
			"b14": Vector2(0.4, -0.18),
			"b15": Vector2(-0.95, -0.26),
			"b16": Vector2(-0.4, -0.4),
			"b17": Vector2(0.4, -0.42),
			"b18": Vector2(-0.95, -0.53),
			"b19": Vector2(-0.4, -0.63),
			"b20": Vector2(0.4, -0.7),
			"b21": Vector2(-0.95, -0.88),
			"b22": Vector2(0.95, -0.88),
			"k01": Vector2(0.95, 0.81),
			"k02": Vector2(0.4, 0.65),
			"k03": Vector2(0.95, 0.48),
			"k04": Vector2(0.4, 0.26),
			"k05": Vector2(-0.95, -0.12),
			"k06": Vector2(-0.95, -0.7),
			"k07": Vector2(-0.4, -0.88),
			"f01": Vector2(-0.4, 0.08),
			"f02": Vector2(0.4, -0.85),
			"r01": Vector2(0.4, 0.94),
			"h01": Vector2(-0.4, 0.39),
			"h02": Vector2(-0.4, 0.6),
			"h03": Vector2(0.4, -0.31),
			"h04": Vector2(0.4, -0.57)
		},
		"routes": {
			"jade-central-service": [Vector2(0.0, 0.98), Vector2(0.0, -0.98)],
			"jade-west-taxiway": [Vector2(0.0, 0.31), Vector2(-0.95, 0.31)],
			"jade-east-taxiway": [Vector2(0.0, -0.49), Vector2(0.95, -0.49)]
		},
		"runways": {
			"jade-west-strip": Vector2(-0.95, 0.48),
			"jade-east-strip": Vector2(0.95, -0.4)
		}
	},
	{
		"targets": {
			"m01": Vector2(-0.17, 0.94),
			"m02": Vector2(0.14, 0.7),
			"m03": Vector2(-0.28, 0.34),
			"m04": Vector2(0.27, -0.06),
			"m05": Vector2(-0.28, -0.44),
			"m06": Vector2(0.27, -0.77),
			"b01": Vector2(-0.95, 0.47),
			"b02": Vector2(0.95, 0.45),
			"b03": Vector2(-0.4, 0.47),
			"b04": Vector2(0.4, 0.405),
			"b05": Vector2(-0.95, 0.32),
			"b06": Vector2(0.95, 0.26),
			"b07": Vector2(-0.4, 0.16),
			"b08": Vector2(0.4, 0.14),
			"b09": Vector2(-0.95, -0.08),
			"b10": Vector2(0.95, -0.14),
			"b11": Vector2(-0.4, -0.23),
			"b12": Vector2(0.4, -0.29),
			"b13": Vector2(-0.95, -0.43),
			"b14": Vector2(0.95, -0.52),
			"b15": Vector2(-0.4, -0.65),
			"b16": Vector2(-0.95, -0.88),
			"k01": Vector2(-0.95, 0.4),
			"k02": Vector2(0.95, 0.38),
			"k03": Vector2(0.4, 0.265),
			"k04": Vector2(-0.95, 0.13),
			"k05": Vector2(-0.4, -0.125),
			"k06": Vector2(0.95, -0.33),
			"k07": Vector2(-0.95, -0.66),
			"k08": Vector2(0.95, -0.9),
			"f01": Vector2(0.4, -0.51),
			"f02": Vector2(-0.4, -0.88),
			"r01": Vector2(0.4, 0.55),
			"h01": Vector2(0.4, -0.67)
		},
		"routes": {
			"volcanic-service-road": [Vector2(0.0, 0.98), Vector2(0.0, -0.98)],
			"volcanic-intro-west": [Vector2(-0.17, 0.94), Vector2(0.015, 0.94)],
			"volcanic-intro-east": [Vector2(0.14, 0.7), Vector2(-0.045, 0.7)],
			"volcanic-mobile-north-west": [Vector2(-0.28, 0.34), Vector2(-0.105, 0.34)],
			"volcanic-mobile-north-east": [Vector2(0.27, -0.06), Vector2(0.105, -0.06)],
			"volcanic-mobile-south-west": [Vector2(-0.28, -0.44), Vector2(-0.105, -0.44)],
			"volcanic-mobile-south-east": [Vector2(0.27, -0.77), Vector2(0.105, -0.77)],
			"volcanic-strip-access": [Vector2(0.0, -0.57), Vector2(0.95, -0.57)]
		},
		"runways": {
			"volcanic-strip": Vector2(0.95, -0.68)
		}
	},
	{
		"targets": {
			"b01": Vector2(-0.95, 0.94),
			"b02": Vector2(0.4, 0.86),
			"b03": Vector2(-0.4, 0.73),
			"b04": Vector2(0.95, 0.68),
			"b05": Vector2(-0.95, 0.51),
			"b06": Vector2(0.4, 0.48),
			"b07": Vector2(-0.4, 0.3),
			"b08": Vector2(0.4, 0.26),
			"b09": Vector2(-0.95, -0.08),
			"b10": Vector2(0.95, -0.11),
			"b11": Vector2(-0.4, -0.25),
			"b12": Vector2(0.4, -0.38),
			"b13": Vector2(-0.95, -0.54),
			"b14": Vector2(0.95, -0.64),
			"b15": Vector2(-0.4, -0.85),
			"b16": Vector2(0.95, -0.91),
			"k01": Vector2(-0.4, 0.94),
			"k02": Vector2(0.95, 0.86),
			"k03": Vector2(-0.95, 0.72),
			"k04": Vector2(0.4, 0.66),
			"k05": Vector2(-0.95, 0.16),
			"k06": Vector2(0.95, 0.12),
			"k07": Vector2(-0.4, -0.07),
			"k08": Vector2(-0.95, -0.29),
			"k09": Vector2(0.95, -0.42),
			"k10": Vector2(0.4, -0.86),
			"f01": Vector2(-0.4, -0.54),
			"f02": Vector2(0.4, -0.62),
			"r01": Vector2(-0.4, 0.49),
			"r02": Vector2(0.95, 0.47),
			"h01": Vector2(-0.44, -0.71),
			"h02": Vector2(0.4, -0.16)
		},
		"routes": {
			"dusk-diagonal-service": [Vector2(0.055, 0.98), Vector2(-0.045, 0.59), Vector2(0.045, 0.34), Vector2(-0.045, -0.02), Vector2(0.045, -0.47), Vector2(-0.055, -0.98)],
			"dusk-bastion-link": [Vector2(0.0, 0.04), Vector2(-0.95, 0.04)],
			"dusk-east-access": [Vector2(0.0, 0.36), Vector2(0.95, 0.36)],
			"dusk-west-access": [Vector2(0.0, -0.78), Vector2(-0.95, -0.78)]
		},
		"runways": {
			"dusk-west-strip": Vector2(-0.95, -0.7),
			"dusk-east-strip": Vector2(0.95, -0.2)
		}
	},
	{
		"targets": {
			"b01": Vector2(-0.95, 0.94),
			"b02": Vector2(-0.4, 0.88),
			"b03": Vector2(-0.95, 0.74),
			"b04": Vector2(-0.4, 0.68),
			"b05": Vector2(-0.95, 0.51),
			"b06": Vector2(-0.4, 0.44),
			"b07": Vector2(-0.95, 0.29),
			"b08": Vector2(-0.4, 0.2),
			"b09": Vector2(-0.95, 0.04),
			"b10": Vector2(-0.4, -0.06),
			"b11": Vector2(0.95, 0.37),
			"b12": Vector2(0.4, 0.29),
			"b13": Vector2(0.95, 0.14),
			"b14": Vector2(0.4, 0.04),
			"b15": Vector2(0.95, -0.09),
			"b16": Vector2(0.4, -0.19),
			"b17": Vector2(0.4, -0.41),
			"b18": Vector2(0.4, -0.65),
			"b19": Vector2(0.95, -0.88),
			"b20": Vector2(0.4, -0.91),
			"k01": Vector2(-0.4, 0.96),
			"k02": Vector2(-0.95, 0.84),
			"k03": Vector2(-0.4, 0.79),
			"k04": Vector2(-0.95, 0.62),
			"k05": Vector2(-0.95, 0.16),
			"k06": Vector2(-0.4, 0.09),
			"k07": Vector2(0.95, 0.48),
			"k08": Vector2(0.4, 0.4),
			"k09": Vector2(0.95, 0.26),
			"k10": Vector2(0.4, -0.07),
			"k11": Vector2(0.95, -0.74),
			"k12": Vector2(0.4, -0.78),
			"f01": Vector2(-0.4, 0.48),
			"f02": Vector2(0.95, 0.1),
			"r01": Vector2(-0.4, 0.57),
			"r02": Vector2(0.4, 0.52),
			"h01": Vector2(-0.4, -0.33),
			"h02": Vector2(0.4, -0.53)
		},
		"routes": {
			# At 7 m, a straight centerline is exactly tangent to both 4 m
			# hangar reservations. Authored offsets keep positive clearance,
			# first to the right of h01, then to the left of h02.
			"arctic-ice-road": [Vector2(0.0, 0.98), Vector2(0.0, -0.25), Vector2(0.02, -0.28), Vector2(0.02, -0.38), Vector2(0.0, -0.40), Vector2(-0.02, -0.47), Vector2(-0.02, -0.59), Vector2(0.0, -0.66), Vector2(0.0, -0.98)],
			"arctic-west-link": [Vector2(0.0, 0.35), Vector2(-0.95, 0.35)],
			"arctic-east-link": [Vector2(0.0, -0.3), Vector2(0.95, -0.3)],
			"arctic-west-strip-access": [Vector2(0.0, -0.43), Vector2(-0.95, -0.43)]
		},
		"runways": {
			"arctic-west-strip": Vector2(-0.95, -0.33),
			"arctic-east-strip": Vector2(0.95, -0.49)
		}
	},
	{
		"targets": {
			"b01": Vector2(-0.95, 0.94),
			"b02": Vector2(-0.4, 0.88),
			"b03": Vector2(0.4, 0.84),
			"b04": Vector2(0.95, 0.89),
			"b05": Vector2(-0.95, 0.7),
			"b06": Vector2(0.95, 0.68),
			"b07": Vector2(-0.4, 0.59),
			"b08": Vector2(0.4, 0.52),
			"b09": Vector2(-0.95, 0.47),
			"b10": Vector2(0.95, 0.45),
			"b11": Vector2(-0.4, 0.33),
			"b12": Vector2(0.4, 0.29),
			"b13": Vector2(-0.95, 0.23),
			"b14": Vector2(0.95, 0.22),
			"b15": Vector2(-0.4, 0.07),
			"b16": Vector2(0.4, 0.01),
			"b17": Vector2(-0.95, -0.19),
			"b18": Vector2(0.95, -0.22),
			"b19": Vector2(-0.4, -0.37),
			"b20": Vector2(0.4, -0.41),
			"b21": Vector2(-0.4, -0.69),
			"b22": Vector2(0.95, -0.91),
			"k01": Vector2(-0.4, 0.95),
			"k02": Vector2(0.4, 0.71),
			"k03": Vector2(-0.95, 0.59),
			"k04": Vector2(0.95, 0.55),
			"k05": Vector2(-0.4, 0.43),
			"k06": Vector2(-0.95, 0.34),
			"k07": Vector2(0.4, 0.15),
			"command": Vector2(0.0, -0.16),
			"k09": Vector2(-0.95, -0.45),
			"k10": Vector2(0.4, -0.64),
			"k11": Vector2(-0.4, -0.88),
			"f01": Vector2(-0.4, 0.76),
			"f02": Vector2(0.95, 0.35),
			"f03": Vector2(-0.95, -0.13),
			"r01": Vector2(0.4, 0.95),
			"r02": Vector2(-0.4, 0.2),
			"r03": Vector2(0.46, -0.17),
			"h01": Vector2(-0.4, -0.58)
		},
		"routes": {
			"final-direct-approach": [Vector2(0.0, 0.98), Vector2(0.0, -0.11)],
			"final-command-bypass": [Vector2(0.0, -0.11), Vector2(-0.4, -0.11), Vector2(-0.4, -0.23), Vector2(0.0, -0.23), Vector2(0.0, -0.98)],
			"final-outer-west-access": [Vector2(0.0, 0.8), Vector2(-0.95, 0.8)],
			"final-middle-east-access": [Vector2(0.0, 0.39), Vector2(0.95, 0.39)],
			"final-strip-access": [Vector2(0.0, -0.77), Vector2(-0.95, -0.77)]
		},
		"runways": {
			"final-strip": Vector2(-0.95, -0.61)
		}
	}
]

static func _apply_compact_layout(result: Dictionary) -> void:
	var authored: Dictionary = COMPACT_LAYOUTS[int(result.sector)]
	for target in result.targets:
		var short_id := str(target.id).get_slice("/", 1)
		target.normalized = authored.targets[short_id]
	for route_id in result.routes:
		result.routes[route_id].points = authored.routes[route_id].duplicate()
	for strip in result.runways:
		strip.center = authored.runways[strip.id]

static func _full_ids(prefix: String, short_ids: Array) -> Array[String]:
	var result: Array[String] = []
	for id in short_ids:
		result.append(prefix + "/" + str(id))
	return result

static func layout_for_sector(sector: int) -> Dictionary:
	## Returns fresh dictionaries/arrays; callers cannot mutate this catalogue.
	## Out-of-range sectors are rejected rather than silently selecting a biome.
	if sector < 0 or sector >= LAYOUTS.size():
		return {}
	var authored: Dictionary = LAYOUTS[sector].duplicate(true)
	var result := authored.duplicate(true)
	var prefix := str(authored.id)
	var targets: Array[Dictionary] = []
	var groups: Dictionary = authored.radars.duplicate(true)
	for group_id in groups:
		groups[group_id].target_ids = []
		groups[group_id].radar_ids = []
		groups[group_id].jam_seconds = JAM_SECONDS
	for row in authored.targets:
		var short_id := str(row[0])
		var id := prefix + "/" + short_id
		var variant := str(row[1])
		var group_id := str(row[4]) if row.size() > 4 else ""
		var route_id := str(authored.mobile_routes.get(short_id, ""))
		var target := {
			"id": id, "variant": variant,
			"normalized": Vector2(float(row[2]), float(row[3])),
			"radar_group": group_id, "priority": short_id in authored.priority_ids,
			"priority_tag": str(authored.priority_tags.get(short_id, "")),
			"rapid_fire": short_id in authored.rapid_ids,
			"mobile": not route_id.is_empty(), "mobile_route_id": route_id,
			"defense_stagger": float(targets.size() % 7) * .04,
			"health_bonus": mini(4, sector / 2), "footprint": FOOTPRINT[variant]
		}
		targets.append(target)
		if groups.has(group_id):
			if variant in ["battery", "bunker"]:
				groups[group_id].target_ids.append(id)
			elif variant == "radar":
				groups[group_id].radar_ids.append(id)
	result.targets = targets
	result.ground_count = targets.size()
	result.priority_ids = _full_ids(prefix, authored.priority_ids)
	result.radar_groups = groups
	var secondary_ids := _full_ids(prefix, authored.secondary.ids)
	result.secondary_spec = {
		"kind": "ground_layout", "label": str(authored.secondary.label),
		"target_ids": secondary_ids, "minimum": int(authored.secondary.minimum)
	}
	result.secondary_kind = "ground_layout"
	result.secondary_ids = secondary_ids.duplicate()
	result.secondary_target = int(authored.secondary.minimum)
	var radar_count := targets.filter(func(t): return t.variant == "radar").size()
	result.secondary_radar_target = mini(2, radar_count)
	result.minimum_target_half_length = MIN_TARGET_HALF_LENGTH[sector]
	result.version = VERSION
	return result

static func instantiate_layout(mission: Dictionary, width: float, length: float, safe_x: float) -> Dictionary:
	## Pure conversion into the local GroundAssault coordinate system.
	## `safe_x` is GroundAssault's measured low-camera horizontal allowance, not
	## the cruise camera width. The additional plateau cap reserves full models.
	var result := layout_for_sector(int(mission.get("sector", -1)))
	if result.is_empty():
		return {}
	var warnings: Array[String] = []
	if not is_finite(width) or not is_finite(length) or not is_finite(safe_x):
		result.valid = false
		result.warnings = ["Non-finite battlefield dimensions"]
		return result
	var half_x := maxf(0.0, minf(safe_x, width * .33 - 2.3))
	var half_z := maxf(0.0, length * .5 - COAST_MARGIN)
	result.width_variant = "compact" if half_x < COMPACT_BELOW_HALF_WIDTH else "wide"
	if result.width_variant == "compact":
		_apply_compact_layout(result)
	result.bounds = {"half_x": half_x, "half_z": half_z, "width": width, "length": length, "coast_margin": COAST_MARGIN}
	if half_x < MIN_SAFE_HALF_WIDTH:
		warnings.append("Reachable half-width %.3f is below the authored minimum %.3f" % [half_x, MIN_SAFE_HALF_WIDTH])
	if half_z < float(result.minimum_target_half_length):
		warnings.append("Coastal target half-length %.3f is below this sector's authored minimum %.3f" % [half_z, float(result.minimum_target_half_length)])
	var target_by_id := {}
	for target in result.targets:
		var at: Vector2 = target.normalized
		target.position = Vector3(at.x * half_x, 0.0, at.y * half_z)
		target.footprint_rect = Rect2(Vector2(target.position.x, target.position.z) - target.footprint * .5, target.footprint)
		target_by_id[target.id] = target
	for route_id in result.routes:
		var route: Dictionary = result.routes[route_id]
		var world_points: Array[Vector3] = []
		for point in route.points:
			world_points.append(Vector3(point.x * half_x, 0.0, point.y * half_z))
		route.id = route_id
		route.world_points = world_points
	for strip in result.runways:
		var center: Vector2 = strip.center
		strip.position = Vector3(center.x * half_x, 0.0, center.y * half_z)
		strip.world_half_extents = Vector2(float(strip.half_width), float(strip.half_length) * half_z)
		strip.rect = Rect2(Vector2(strip.position.x, strip.position.z) - strip.world_half_extents, strip.world_half_extents * 2.0)
	result.target_by_id = target_by_id
	result.warnings = warnings
	# This flag covers dimension guards only. Real collider/weapon/render proofs
	# are still pending and must not be inferred from a nonempty catalogue.
	result.geometry_validated_in_game = false
	result.bounds_valid = warnings.is_empty()
	result.valid = warnings.is_empty()
	return result

# Objective consumer contract (mechanics are implemented elsewhere):
# - main = kills >= quota AND every priority_ids entry has a destruction record;
# - a priority is already one of those kills, never an additional kill count;
# - secondary = count(unique destroyed IDs in secondary_ids) >= secondary_target;
# - emit complete_objective("ground_layout") once per matching secondary ID;
# - destroying a radar jams only radar_groups[group].target_ids for 6 seconds;
#   Coral marks the one group global=true for the introductory demonstration;
# - global/local jam has no health, collider, movement or target immunity effect;
# - base HEALTH remains GroundTarget.HEALTH + health_bonus <= 4;
# - mobile routes use local raid world_points, Y=0, no change to altitude gates.
#
# Geometry / weapon acceptance required before treating this pass as validated:
# 1. Instantiate the eight prepared missions at 720p/1080p and 4:3 if supported;
#    assert finite data, exact compositions, stable IDs, bounds and plateau Y.
# 2. Compare FOOTPRINT to real collider boxes, test target/target reservations,
#    road-segment / inflated building rectangles and strips / building rectangles.
#    A mobile battery may overlap its own road, never another fixed building.
# 3. Trace every mobile segment with its swept full footprint, including an
#    entire back-and-forth cycle; test containment and no hidden teleport.
# 4. Verify shared road/strip geometry is actually consumed by terrain, not just
#    present in this catalogue; inspect all eight rendered coastal transitions.
# 5. Destroy priorities and quotas with actual weapons, movement, colliders and
#    exposure windows. Especially compare both bastion orders in M23 and direct
#    command / radar-first / fuel-first in M31; retain quota 26 pending evidence.
# No claim of reachable quotas, graphical quality or performance is made here.
