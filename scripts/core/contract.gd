class_name Contract
extends RefCounted
## One customer order: an offer on the board, then (once accepted) a contract
## being built, ready for collection, or being loaded onto a lorry.
## Pure data plus (de)serialisation - the rules live in ContractBook.

enum Status { OFFER, ACTIVE, READY, DISPATCHING }
const STATUS_NAMES: Array[String] = ["offer", "active", "ready", "dispatching"]

var id := ""
var serial := 0
var tier := "trade"
var premium := false
var customer := ""
var archetype := ""
var archetype_label := ""
var factory := ""             # id of the factory that builds it
var product_name := ""
var quantity := 0
var unit_ref := 0.0           # the factory's profit per cylinder when the offer was made
var margin := 0.0             # price vs selling normally (1.20 = +20%). The price follows your list price, so the premium never goes stale. 0 = fixed price (value)
var value := 0.0              # the quoted payout when the offer was made (a fixed price when margin is 0)
var bonus := 0.0              # the extra for finishing within bonus_by, quoted when the offer was made
var bonus_pct := 0.0          # ...as a fraction of the payout (the bonus follows the price too)
var bonus_by := 0.0           # seconds after acceptance (0 = no bonus)
var deadline := 0.0           # seconds after acceptance (0 = none)
var est_full := 0.0           # seconds to build at 100% of the factory's planning rate
var rep := 0                  # reputation for delivering it (before rank scaling)
var penalty := 0              # reputation lost if it fails
var pallets := 1              # pallets shown on the dispatch pad
var expires_in := 0.0         # offers only: seconds left on the board

# --- warehouse orders (Expansion 4). In stock mode an order is filled from the factory's stock: `delivered`
#     is every cylinder that exists for it = shipped + held; the planner builds what is still owed.
var sku := ""                 # which product ("" = the factory's one product, direct-sales mode)
var source := "board"         # "board" (accepted from the Contract Board) or "call" (a customer telephoned)
var customer_id := ""         # the persistent customer behind a telephone order
var mode := "full"            # call orders: "full" (all in stock), "partial" (ship now, backorder the rest), "delayed" (wait, ship in one go)
var shipped := 0.0            # cylinders already on their way (paid for)
var held := 0.0               # reserved in the warehouse for this order, not yet gone (includes `loading`)
var loading := 0.0            # on the lorry that is loading now
var paid_total := 0.0         # money received so far (never paid twice)
var patience := 0.0           # call orders: seconds past the promise the customer will wait
var promised := 0.0           # call orders: the delivery time promised on the phone (seconds after acceptance)
var late := false             # past the promise
var shipments := 0            # lorries sent
var built := false            # every cylinder it needs now exists (shipped or reserved)
var asked := 0                # call orders: what the customer first asked for (quantity may be less if they took what was available)

var status: Status = Status.OFFER
var allocation := 0           # % of the factory's output going to this contract
var delivered := 0.0          # cylinders built for it so far (fractional: shipments are split exactly by share)
var elapsed := 0.0            # seconds since acceptance (while the factory ran)
var time_left := 0.0          # seconds to the deadline (only if deadline > 0)
var bonus_earned := false
var dispatch_total := 0.0
var dispatch_left := 0.0


func remaining() -> float:
	return maxf(float(quantity) - delivered, 0.0)


## Cylinders still to be sent (not yet shipped).
func outstanding() -> float:
	return maxf(float(quantity) - shipped, 0.0)


func is_call() -> bool:
	return source == "call"


func fraction() -> float:
	return clampf(delivered / float(maxi(quantity, 1)), 0.0, 1.0)


func has_deadline() -> bool:
	return deadline > 0.0


func is_open() -> bool:
	return status == Status.ACTIVE


## 0..1 progress of the dispatch sequence (only while DISPATCHING).
func dispatch_progress() -> float:
	if status != Status.DISPATCHING or dispatch_total <= 0.0:
		return 0.0
	return clampf(1.0 - dispatch_left / dispatch_total, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"id": id, "serial": serial, "tier": tier, "premium": premium, "customer": customer,
		"archetype": archetype, "archetype_label": archetype_label, "factory": factory,
		"product_name": product_name, "quantity": quantity, "unit_ref": unit_ref, "margin": margin, "value": value,
		"bonus": bonus, "bonus_pct": bonus_pct, "bonus_by": bonus_by, "deadline": deadline, "est_full": est_full,
		"rep": rep, "penalty": penalty, "pallets": pallets, "expires_in": expires_in,
		"status": STATUS_NAMES[status], "allocation": allocation, "delivered": delivered,
		"elapsed": elapsed, "time_left": time_left, "bonus_earned": bonus_earned,
		"dispatch_total": dispatch_total, "dispatch_left": dispatch_left,
		"sku": sku, "source": source, "customer_id": customer_id, "mode": mode, "shipped": shipped, "held": held,
		"loading": loading, "paid_total": paid_total, "patience": patience, "promised": promised, "late": late, "shipments": shipments, "asked": asked, "built": built,
	}


## Reads a saved contract. Returns null if it is unusable (so one damaged entry
## in a save never stops the rest from loading).
static func from_dict(d: Variant) -> Contract:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var c := Contract.new()
	c.id = str(d.get("id", ""))
	c.serial = int(d.get("serial", 0))
	c.tier = str(d.get("tier", "trade"))
	c.premium = bool(d.get("premium", false))
	c.customer = str(d.get("customer", ""))
	c.archetype = str(d.get("archetype", ""))
	c.archetype_label = str(d.get("archetype_label", ""))
	c.factory = str(d.get("factory", ""))
	c.product_name = str(d.get("product_name", ""))
	c.quantity = maxi(int(d.get("quantity", 0)), 0)
	c.unit_ref = maxf(float(d.get("unit_ref", 0.0)), 0.0)
	c.margin = maxf(float(d.get("margin", 0.0)), 0.0)
	c.value = maxf(float(d.get("value", 0.0)), 0.0)
	c.bonus = maxf(float(d.get("bonus", 0.0)), 0.0)
	c.bonus_pct = maxf(float(d.get("bonus_pct", 0.0)), 0.0)
	c.bonus_by = maxf(float(d.get("bonus_by", 0.0)), 0.0)
	c.deadline = maxf(float(d.get("deadline", 0.0)), 0.0)
	c.est_full = maxf(float(d.get("est_full", 0.0)), 0.0)
	c.rep = maxi(int(d.get("rep", 0)), 0)
	c.penalty = maxi(int(d.get("penalty", 0)), 0)
	c.pallets = clampi(int(d.get("pallets", 1)), 1, 4)
	c.expires_in = maxf(float(d.get("expires_in", 0.0)), 0.0)
	var s := STATUS_NAMES.find(str(d.get("status", "offer")))
	c.status = (maxi(s, 0)) as Status
	c.allocation = clampi(int(d.get("allocation", 0)), 0, 100)
	c.delivered = clampf(float(d.get("delivered", 0.0)), 0.0, float(c.quantity))
	c.elapsed = maxf(float(d.get("elapsed", 0.0)), 0.0)
	c.time_left = float(d.get("time_left", c.deadline))
	c.bonus_earned = bool(d.get("bonus_earned", false))
	c.dispatch_total = maxf(float(d.get("dispatch_total", 0.0)), 0.0)
	c.dispatch_left = maxf(float(d.get("dispatch_left", 0.0)), 0.0)
	c.sku = str(d.get("sku", ""))
	c.source = str(d.get("source", "board"))
	c.customer_id = str(d.get("customer_id", ""))
	c.mode = str(d.get("mode", "full"))
	c.shipped = clampf(float(d.get("shipped", 0.0)), 0.0, float(c.quantity))
	c.held = clampf(float(d.get("held", 0.0)), 0.0, float(c.quantity) - c.shipped)
	c.loading = clampf(float(d.get("loading", 0.0)), 0.0, c.held)
	c.paid_total = maxf(float(d.get("paid_total", 0.0)), 0.0)
	c.patience = maxf(float(d.get("patience", 0.0)), 0.0)
	c.promised = maxf(float(d.get("promised", 0.0)), 0.0)
	c.late = bool(d.get("late", false))
	c.shipments = maxi(int(d.get("shipments", 0)), 0)
	c.asked = maxi(int(d.get("asked", c.quantity)), 0)
	c.built = bool(d.get("built", false))
	if c.id == "" or c.customer == "" or c.factory == "" or c.quantity <= 0:
		return null
	return c
