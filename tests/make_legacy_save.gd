extends SceneTree
## Writes a save exactly as v0.5.1 (save version 4) would: direct-sales rules, no warehouse, contracts mid-way.
## Run:  godot --headless --path . -s tests/make_legacy_save.gd -- --out=/some/save.json

func _init() -> void:
	var out := "user://legacy_save.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var data := GameData.new()
	data.load_all()
	var c := GameSession.new(data)
	c.contracts.reset(77)
	c.state.factory_name = "Legacy Flow Ltd"
	c.state.cash = 25000.0
	c.state.lifetime_earned = 400000.0
	c.state.tutorial_step = 7
	var copper := c.factory("copper")
	for m: Dictionary in copper.data.machines:
		copper.state.upgrade_levels[m["id"]] = 9
	copper.state.upgrade_levels["finish"] = 3
	copper.state.earned = 400000.0
	copper.state.cylinders_made = 12000.0
	copper.state.cylinders_sold = 12000.0
	copper.refresh()
	c.contracts.unlocked = true
	c.contracts.offer_timer = 1.0e9
	for i in 3:
		var o := Contract.new()
		o.id = "L%d" % (i + 1)
		o.serial = i + 1
		o.tier = "trade"
		o.customer = ["Legacy Plumbing", "Old Faithful Supplies", "Heritage Heating"][i]
		o.archetype = "installer"
		o.factory = "copper"
		o.product_name = "Copper Cylinder"
		o.quantity = [60, 40, 90][i]
		o.unit_ref = 8.0
		o.margin = 1.2
		o.value = roundf(float(o.quantity) * copper.profit_per_cylinder() * 1.2)
		o.deadline = 0.0 if i != 2 else 3000.0
		o.est_full = 100.0
		o.rep = 5
		o.penalty = 3
		o.pallets = 2
		o.expires_in = 900.0
		c.contracts.offers.append(o)
		c.contracts.accept(o.id)
		c.contracts.set_allocation(o.id, 20)
	c.contracts.find("L1").delivered = 25.0
	c.contracts.find("L2").delivered = 40.0
	c.contracts._complete(c.contracts.find("L2"))
	c.contracts.find("L3").delivered = 10.0
	var d := c.save_data()
	for key in ["stock_mode", "stock_migrate", "sales"]:
		d.erase(key)
	for fs: Dictionary in d["factories"].values():
		for key in ["warehouse", "targets", "priority", "auto_production", "auto_targets", "wholesale_on", "wholesale_timer"]:
			fs.erase(key)
	d["last_saved_unix"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"game": "cylinder_clicker", "version": 4, "state": d}))
	f.close()
	print("wrote ", out)
	quit()
