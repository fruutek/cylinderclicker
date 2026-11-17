class_name ContractRules
extends RefCounted
## The data-driven side of contracts (data/contracts.json): ranks, tiers,
## customers and tuning numbers. Pure lookups, no state.

var board: Dictionary = {}
var ranks: Array = []
var tiers: Dictionary = {}
var archetypes: Array = []
var places: Array = []
var surnames: Array = []
var enabled := false


func _init(raw: Dictionary = {}) -> void:
	board = raw.get("board", {})
	ranks = raw.get("ranks", [])
	tiers = raw.get("tiers", {})
	archetypes = raw.get("archetypes", [])
	var names: Dictionary = raw.get("names", {})
	places = names.get("places", [])
	surnames = names.get("surnames", [])
	enabled = not ranks.is_empty() and not tiers.is_empty() and not archetypes.is_empty() and not places.is_empty() and not surnames.is_empty()


func num(key: String, fallback: float = 0.0) -> float:
	return float(board.get(key, fallback))


func tier(id: String) -> Dictionary:
	return tiers.get(id, {})


func tier_ids() -> Array:
	return tiers.keys()


## Index of the rank a reputation total has reached.
func rank_index(points: int) -> int:
	var idx := 0
	for i in ranks.size():
		if points >= int(ranks[i]["at"]):
			idx = i
	return idx


func rank(index: int) -> Dictionary:
	return ranks[clampi(index, 0, ranks.size() - 1)]


func rank_name(index: int) -> String:
	return str(rank(index)["name"])


## Reputation needed for the next rank, or -1 at the top.
func next_rank_at(index: int) -> int:
	if index + 1 >= ranks.size():
		return -1
	return int(ranks[index + 1]["at"])


## Share of a contract's reputation paid at this rank (small orders stop
## counting once the company has outgrown them).
func rep_factor(tier_id: String, rank_idx: int) -> float:
	var arr: Array = tier(tier_id).get("rep_by_rank", [1.0])
	return float(arr[clampi(rank_idx, 0, arr.size() - 1)])


func archetype_by_id(id: String) -> Dictionary:
	for a: Dictionary in archetypes:
		if a["id"] == id:
			return a
	return {}
