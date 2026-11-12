class_name GameState
extends RefCounted
## Company-wide state persisted between sessions: the shared cash balance,
## overall statistics and one FactoryState per factory. Pure data - no logic
## beyond (de)serialisation, so the save format stays easy to version and extend.

const DEFAULT_FACTORY_NAME := "My Cylinder Factory"
const LEGACY_FACTORY_NAME := "Coppertop Cylinder Works"   # name shown before factories could be named
const MAX_NAME_LENGTH := 24

var factory_name: String = DEFAULT_FACTORY_NAME
var cash: float = 0.0
var lifetime_earned: float = 0.0
var total_clicks: int = 0
var play_seconds: float = 0.0
var unlocked_products: Array = []         # ids of unlocked materials/ranges/variants
var factories: Dictionary = {}            # factory id -> FactoryState
var current_factory: String = ""          # the factory the player is looking at
var tutorial_step: int = 0
var last_saved_unix: float = 0.0
var settings: Dictionary = {"sfx_volume": 0.8, "music_volume": 0.4, "fullscreen": false}


## Keeps only characters the pixel font can draw, trims, and enforces the
## length limit. A blank result falls back to the default name.
static func clean_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 32 and code <= 126:
			out += raw[i]
	out = out.strip_edges().substr(0, MAX_NAME_LENGTH).strip_edges()
	return out if not out.is_empty() else DEFAULT_FACTORY_NAME


func to_dict() -> Dictionary:
	return {
		"factory_name": factory_name,
		"cash": cash,
		"lifetime_earned": lifetime_earned,
		"total_clicks": total_clicks,
		"play_seconds": play_seconds,
		"unlocked_products": unlocked_products.duplicate(),
		"factories": _factories_dict(),
		"current_factory": current_factory,
		"tutorial_step": tutorial_step,
		"last_saved_unix": last_saved_unix,
		"settings": settings.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	factory_name = clean_name(str(d.get("factory_name", DEFAULT_FACTORY_NAME)))
	cash = NumFmt.clamp_value(float(d.get("cash", 0.0)))
	lifetime_earned = NumFmt.clamp_value(float(d.get("lifetime_earned", 0.0)))
	total_clicks = int(d.get("total_clicks", 0))
	play_seconds = float(d.get("play_seconds", 0.0))
	var unlocked: Variant = d.get("unlocked_products", [])
	unlocked_products = unlocked.duplicate() if typeof(unlocked) == TYPE_ARRAY else []
	factories = {}
	var saved_factories: Variant = d.get("factories", {})
	if typeof(saved_factories) == TYPE_DICTIONARY:
		for id: String in saved_factories:
			if typeof(saved_factories[id]) == TYPE_DICTIONARY:
				var fs := FactoryState.new()
				fs.from_dict(saved_factories[id])
				factories[id] = fs
	current_factory = str(d.get("current_factory", ""))
	tutorial_step = int(d.get("tutorial_step", 0))
	last_saved_unix = float(d.get("last_saved_unix", 0.0))
	var s: Variant = d.get("settings", {})
	if typeof(s) == TYPE_DICTIONARY:
		for k: String in s:
			settings[k] = s[k]


func _factories_dict() -> Dictionary:
	var out := {}
	for id: String in factories:
		out[id] = (factories[id] as FactoryState).to_dict()
	return out
