class_name ContractGenerator
extends RefCounted
## Makes customer orders. A pure function of (seed, serial, market snapshot):
## the same inputs always give the same contract, which is what makes the
## board reproducible and testable. Nothing here knows about copper or
## stainless - quantities come from each factory's planning rate and prices
## from its current profit per cylinder.
##
## ctx = {
##   "rank": int, "premium_allowed": bool, "exclude": [customer names already around],
##   "factories": [{"id", "product_name", "profit", "rate"}]   # rate = planning cylinders/second
## }


const MAX_QUANTITY := 1.0e15

## A well-spread 64-bit hash of (seed, serial), used to seed the generator.
static func mix(seed_value: int, serial: int) -> int:
	var x := seed_value + serial * -7046029254386353131
	x = (x ^ (x >> 30)) * -4658895280553007687
	x = (x ^ (x >> 27)) * -7723592293110705685
	return x ^ (x >> 31)


## Rounds a quantity to a tidy number (12, 35, 150, 2,500 ...).
static func nice_quantity(q: float) -> int:
	q = minf(q, MAX_QUANTITY)          # stays well inside integer range however big the factory gets
	if q < 10.0:
		return maxi(1, roundi(q))
	var magnitude := pow(10.0, floorf(log(q) / log(10.0) + 1e-9))
	var step := magnitude / 2.0
	return maxi(1, int(roundf(q / step) * step))


static func _round_up_seconds(s: float) -> float:
	var step := 30.0 if s < 600.0 else (60.0 if s < 3600.0 else 300.0)
	return ceilf(s / step) * step


static func _range(rng: RandomNumberGenerator, pair: Array) -> float:
	return float(pair[0]) + (float(pair[1]) - float(pair[0])) * rng.randf()


static func _pick(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w: float in weights:
		total += w
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0 and float(weights[i]) > 0.0:
			return i
	for i in range(weights.size() - 1, -1, -1):
		if float(weights[i]) > 0.0:
			return i
	return -1


## Returns the new offer, or null if nothing can be offered (no factory able to
## build anything yet).
static func generate(rules: ContractRules, ctx: Dictionary, seed_value: int, serial: int) -> Contract:
	if not rules.enabled:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(seed_value, serial)
	var rank_idx: int = int(ctx.get("rank", 0))
	var rank_def := rules.rank(rank_idx)
	var factories: Array = ctx.get("factories", []).filter(func(f: Dictionary) -> bool:
		return float(f["rate"]) > 0.0 and float(f["profit"]) > 0.0)
	if factories.is_empty():
		return null

	# --- tier: from the rank's mix, restricted to what some factory can really build
	var tier_ids: Array = rules.tier_ids()
	var weights: Array = []
	for tid: String in tier_ids:
		var t := rules.tier(tid)
		var w := float(rank_def.get("mix", {}).get(tid, 0.0))
		if rank_idx < int(t.get("min_rank", 0)):
			w = 0.0
		var any := false
		for f: Dictionary in factories:
			if _potential(f) >= float(t.get("min_potential", 0.0)):
				any = true
		weights.append(w if any else 0.0)
	var ti := _pick(rng, weights)
	if ti < 0:
		return null
	var tier_id: String = tier_ids[ti]
	var tier := rules.tier(tier_id)

	# --- factory
	var candidates: Array = factories.filter(func(f: Dictionary) -> bool:
		return _potential(f) >= float(tier.get("min_potential", 0.0)))
	var factory: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]

	# --- customer type
	var archs: Array = []
	var arch_weights: Array = []
	for a: Dictionary in rules.archetypes:
		if (a["tiers"] as Array).has(tier_id):
			archs.append(a)
			arch_weights.append(float(a.get("weight", 1.0)))
	var arch: Dictionary = archs[_pick(rng, arch_weights)]

	var premium: bool = bool(ctx.get("premium_allowed", false)) and rng.randf() < float(rank_def.get("premium", 0.0))
	var rate := float(factory["rate"])
	var profit := float(factory["profit"])

	# --- how much, and what it pays
	var minutes := _range(rng, tier["minutes"]) * float(rank_def.get("size", 1.0)) * float(arch.get("size", 1.0))
	if premium:
		minutes *= rules.num("premium_size_mult", 1.0)
	var qty := maxi(nice_quantity(minutes * 60.0 * rate), int(tier.get("min_quantity", 1)))
	var margin := _range(rng, tier["margin"]) + _range(rng, arch["price"]) + float(rank_def.get("price", 0.0))
	if premium:
		margin += rules.num("premium_margin", 0.0)
	margin = clampf(margin, rules.num("min_margin", 0.9), rules.num("max_margin", 1.6))
	var value := maxf(floorf(float(qty) * profit * margin), 1.0)

	# --- deadline and bonus: always reachable, measured against the full-rate build time
	var est_full := float(qty) / rate
	var deadline := 0.0
	if rng.randf() < float(tier.get("deadline_chance", 0.0)):
		var slack := _range(rng, tier["slack"])
		if premium:
			slack *= rules.num("premium_slack_mult", 1.0)
		deadline = _round_up_seconds(maxf(float(tier.get("min_deadline", 0)), est_full * slack))
	var bonus := 0.0
	var bonus_by := 0.0
	var bonus_roll := rng.randf()
	var bonus_pct := _range(rng, tier["bonus"])
	if (deadline > 0.0 or bonus_roll < float(tier.get("bonus_chance", 0.0))) and bonus_pct > 0.005:
		bonus = floorf(value * bonus_pct)
		bonus_by = floorf(deadline * 0.6) if deadline > 0.0 else _round_up_seconds(est_full * 3.0)
		if bonus < 1.0:
			bonus = 0.0
			bonus_by = 0.0
	if bonus <= 0.0:
		bonus_pct = 0.0

	var rep := roundi(_range(rng, tier["rep"]) * float(arch.get("rep", 1.0)) * (rules.num("premium_rep_mult", 1.0) if premium else 1.0))
	rep = mini(rep, roundi(float((tier["rep"] as Array)[1]) * rules.num("max_rep_mult", 1.5)))      # no stacking of bonuses can out-earn the next tier

	var c := Contract.new()
	c.serial = serial
	c.id = "c%d" % serial
	c.tier = tier_id
	c.premium = premium
	c.archetype = str(arch["id"])
	c.archetype_label = str(arch.get("label", ""))
	c.customer = _customer_name(rng, rules, arch, ctx.get("exclude", []))
	c.factory = str(factory["id"])
	c.product_name = str(factory.get("product_name", ""))
	c.quantity = qty
	c.unit_ref = profit
	c.margin = margin
	c.value = value
	c.bonus = bonus
	c.bonus_pct = bonus_pct
	c.bonus_by = bonus_by
	c.deadline = deadline
	c.est_full = est_full
	c.rep = maxi(rep, 1)
	c.penalty = maxi(roundi(float(c.rep) * rules.num("penalty_fraction", 0.5)), 1)
	var pallet_range: Array = tier.get("pallets", [1, 2])
	c.pallets = rng.randi_range(int(pallet_range[0]), int(pallet_range[1]))
	c.expires_in = float(tier.get("lifetime", 900)) * rng.randf_range(0.8, 1.0)
	c.status = Contract.Status.OFFER
	return c


static func _potential(f: Dictionary) -> float:
	return float(f["rate"]) * 60.0 * float(f["profit"])


static func _customer_name(rng: RandomNumberGenerator, rules: ContractRules, arch: Dictionary, exclude: Array) -> String:
	var patterns: Array = arch["names"]
	var out := ""
	for attempt in 8:
		var pattern: String = patterns[rng.randi_range(0, patterns.size() - 1)]
		out = pattern.replace("{place}", str(rules.places[rng.randi_range(0, rules.places.size() - 1)])) \
			.replace("{surname}", str(rules.surnames[rng.randi_range(0, rules.surnames.size() - 1)]))
		if not exclude.has(out):
			break
	return out
