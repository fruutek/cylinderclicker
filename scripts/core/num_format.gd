class_name NumFmt
extends RefCounted
## Central number formatting. All currency and production values are 64-bit
## floats (safe up to ~1.8e308); every on-screen number goes through here, so
## swapping in a bigger number type later only touches this file and the
## arithmetic in GameSession.

const SUFFIXES: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
const MAX_VALUE := 1.0e300


static func clamp_value(v: float) -> float:
	if is_nan(v):
		return 0.0
	return clampf(v, -MAX_VALUE, MAX_VALUE)


static func _group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## 950 -> "950", 12345 -> "12,345", 1234567 -> "1.23M", 1e40 -> "1.00e40"
static func number(v: float, small_decimals: int = 0) -> String:
	v = clamp_value(v)
	var a := absf(v)
	if a < 1000.0 and small_decimals > 0:
		var s := String.num(v, small_decimals)
		if s.contains("."):
			s = s.rstrip("0").rstrip(".")
		return s
	if a < 1.0e6:
		return _group(int(floorf(v + 0.0001)))
	var tier := int(floorf(log(a) / log(1000.0) + 1e-9))
	if tier < SUFFIXES.size():
		var scaled := v / pow(1000.0, tier)
		return "%.2f%s" % [floorf(scaled * 100.0) / 100.0, SUFFIXES[tier]]
	var e := int(floorf(log(a) / log(10.0) + 1e-9))
	return "%.2fe%d" % [v / pow(10.0, e), e]


static func money(v: float) -> String:
	v = clamp_value(v)
	if absf(v) < 100.0 and absf(v - roundf(v)) > 0.004:
		return "£%.2f" % v
	return "£" + number(v)


static func duration(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]
