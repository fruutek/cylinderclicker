class_name StatBlock
extends RefCounted
## Turns purchased upgrade levels into final stat values.
## final = (base + sum(add)) * (1 + sum(add_pct)) * product(mul)


static func compute(data: GameData, state: GameState) -> Dictionary:
	var add := {}
	var pct := {}
	var mul := {}
	for u: Dictionary in data.upgrades:
		var lvl := state.level(u["id"])
		if lvl <= 0:
			continue
		for e: Dictionary in u.get("effects", []):
			var stat: String = e["stat"]
			var value := float(e["value"])
			match e.get("op", "add"):
				"add":
					add[stat] = float(add.get(stat, 0.0)) + value * lvl
				"add_pct":
					pct[stat] = float(pct.get(stat, 0.0)) + value * lvl
				"mul":
					mul[stat] = float(mul.get(stat, 1.0)) * pow(value, lvl)
				_:
					push_warning("StatBlock: unknown op in upgrade %s" % u["id"])
	var out := {}
	var names := {}
	for k: String in data.base_stats:
		names[k] = true
	for d: Dictionary in [add, pct, mul]:
		for k: String in d:
			names[k] = true
	for k: String in names:
		var base := float(data.base_stats.get(k, 0.0))
		out[k] = (base + float(add.get(k, 0.0))) * (1.0 + float(pct.get(k, 0.0))) * float(mul.get(k, 1.0))
	return out
