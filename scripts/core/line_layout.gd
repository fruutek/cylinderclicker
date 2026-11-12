class_name LineLayout
extends RefCounted
## Geometry of one production line: where stations sit on the factory floor
## and the conveyor polylines that join them. The simulation only needs the
## belt lengths; the view uses the same object to place sprites.

var station_positions: Array[Vector2] = []
var belts: Array = []               # Array of PackedVector2Array, belt i leaves station i
var belt_lengths: Array[float] = []
var dispatch_pos := Vector2.ZERO
var stock_pos := Vector2.ZERO


func _init(data: FactoryDef) -> void:
	var layout: Dictionary = data.layout
	var half := float(layout.get("station_half_width", 14))
	dispatch_pos = _vec(layout.get("dispatch_pos", [0, 0]))
	stock_pos = _vec(layout.get("stock_pos", [0, 0]))
	for s: Dictionary in data.stations:
		station_positions.append(_vec(s["pos"]))
	for i in data.stations.size():
		var pts: Array[Vector2] = [station_positions[i]]
		for p: Array in data.stations[i].get("path_after", []):
			pts.append(_vec(p))
		var last := i == data.stations.size() - 1
		pts.append(dispatch_pos if last else station_positions[i + 1])
		# Trim the ends so belts start/finish at the station edges.
		pts[0] = pts[0].move_toward(pts[1], half)
		if not last:
			pts[pts.size() - 1] = pts[pts.size() - 1].move_toward(pts[pts.size() - 2], half)
		belts.append(PackedVector2Array(pts))
		var length := 0.0
		for j in range(1, pts.size()):
			length += pts[j - 1].distance_to(pts[j])
		belt_lengths.append(length)


static func _vec(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Position `dist` pixels along belt `index`.
func point_on_belt(index: int, dist: float) -> Vector2:
	var pts: PackedVector2Array = belts[index]
	var remaining := maxf(dist, 0.0)
	for j in range(1, pts.size()):
		var seg := pts[j - 1].distance_to(pts[j])
		if remaining <= seg or j == pts.size() - 1:
			return pts[j - 1].move_toward(pts[j], minf(remaining, seg))
		remaining -= seg
	return pts[pts.size() - 1]
