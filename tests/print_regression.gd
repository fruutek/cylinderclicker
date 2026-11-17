extends SceneTree
## Prints the golden regression numbers (see tests/regression_scenario.gd).
## Run:  godot --headless --path . -s tests/print_regression.gd


func _init() -> void:
	var data := GameData.new()
	data.load_all()
	var r: Dictionary = load("res://tests/regression_scenario.gd").play(data)
	print("GOLDEN ", JSON.stringify(r, "", true, true).replace("\n", ""))
	quit()
