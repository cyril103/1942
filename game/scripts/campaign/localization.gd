extends RefCounted
## French source strings are stable message keys. Translate before interpolation.
## Catalogues contain presentation only: never localize save keys or gameplay IDs.
const SUPPORTED := ["fr", "en"]
const CATALOG_PATHS := [
	"res://data/localization/menus.en.json",
	"res://data/localization/content.en.json",
	"res://data/localization/gameplay.en.json",
	"res://data/localization/experience.en.json",
	"res://data/localization/command.en.json",
	"res://data/localization/gamepad.en.json",
]
static var locale: String = "fr"
static var _english: Dictionary = {}
static var _loaded: bool = false
static var catalogue_errors: Array[String] = []

static func normalize(code: Variant) -> String:
	if code is not String: return "fr"
	var language: String = code.to_lower().replace("-", "_").get_slice("_", 0)
	return language if language in SUPPORTED else "fr"

static func set_locale(code: String) -> void:
	locale = normalize(code)
	TranslationServer.set_locale(locale)
	if locale == "en": _load_catalogues()

static func text(source: String) -> String:
	if locale == "fr" or source.is_empty(): return source
	_load_catalogues()
	return str(_english.get(source, source))

static func has_translation(source: String) -> bool:
	_load_catalogues()
	return _english.has(source)

static func entries() -> Dictionary:
	_load_catalogues()
	return _english.duplicate()

static func _load_catalogues() -> void:
	if _loaded: return
	_loaded = true
	for path in CATALOG_PATHS:
		var parser := JSON.new()
		if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path)) != OK or parser.data is not Dictionary:
			catalogue_errors.append("Invalid or missing localization catalogue: " + path)
			continue
		for source in parser.data:
			var translated: Variant = parser.data[source]
			if translated is not String or translated.is_empty():
				catalogue_errors.append("Empty or invalid translation: " + str(source))
				continue
			if _english.has(source) and _english[source] != translated:
				catalogue_errors.append("Conflicting translation: " + str(source))
				continue
			_english[source] = translated
	for problem in catalogue_errors: push_error(problem)
