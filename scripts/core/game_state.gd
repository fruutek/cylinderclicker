class_name GameState
extends RefCounted
## Everything that is persisted between sessions. Pure data - no logic beyond
## (de)serialisation, so the save format stays easy to version and extend.

const DEFAULT_FACTORY_NAME := "My Cylinder Factory"
const LEGACY_FACTORY_NAME := "Coppertop Cylinder Works"   # name shown before factories could be named
const MAX_NAME_LENGTH := 24

var factory_name: String = DEFAULT_FACTORY_NAME
var cash: float = 0.0
var lifetime_earned: float = 0.0
var cylinders_made: float = 0.0
var total_clicks: int = 0
var play_seconds: float = 0.0
var upgrade_levels: Dictionary = {}       # upgrade id -> level
var unlocked_products: Array = []         # ids of unlocked materials/ranges/variants
var current_product: Dictionary = {}      # {material, range, variants[]}
var tutorial_step: int = 0
var best_rate_per_min: float = 0.0
var last_saved_unix: float = 0.0
var settings: Dictionary = {"sfx_volume": 0.8, "music_volume": 0.4, "fullscreen": false}


func level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


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
		"cylinders_made": cylinders_made,
		"total_clicks": total_clicks,
		"play_seconds": play_seconds,
		"upgrade_levels": upgrade_levels.duplicate(),
		"unlocked_products": unlocked_products.duplicate(),
		"current_product": current_product.duplicate(true),
		"tutorial_step": tutorial_step,
		"best_rate_per_min": best_rate_per_min,
		"last_saved_unix": last_saved_unix,
		"settings": settings.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	factory_name = clean_name(str(d.get("factory_name", DEFAULT_FACTORY_NAME)))
	cash = NumFmt.clamp_value(float(d.get("cash", 0.0)))
	lifetime_earned = NumFmt.clamp_value(float(d.get("lifetime_earned", 0.0)))
	cylinders_made = NumFmt.clamp_value(float(d.get("cylinders_made", 0.0)))
	total_clicks = int(d.get("total_clicks", 0))
	play_seconds = float(d.get("play_seconds", 0.0))
	upgrade_levels = {}
	var levels: Variant = d.get("upgrade_levels", {})
	if typeof(levels) == TYPE_DICTIONARY:
		for k: String in levels:
			upgrade_levels[k] = maxi(0, int(levels[k]))
	var unlocked: Variant = d.get("unlocked_products", [])
	unlocked_products = unlocked.duplicate() if typeof(unlocked) == TYPE_ARRAY else []
	var product: Variant = d.get("current_product", {})
	current_product = product.duplicate(true) if typeof(product) == TYPE_DICTIONARY else {}
	tutorial_step = int(d.get("tutorial_step", 0))
	best_rate_per_min = float(d.get("best_rate_per_min", 0.0))
	last_saved_unix = float(d.get("last_saved_unix", 0.0))
	var s: Variant = d.get("settings", {})
	if typeof(s) == TYPE_DICTIONARY:
		for k: String in s:
			settings[k] = s[k]
