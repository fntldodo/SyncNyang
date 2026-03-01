extends RefCounted

## ChartLoader — loads chart JSON files from res://data/charts/.
## Supports types: tap, scratch, moving.

static func load_chart(track_id: String, diff: String) -> Dictionary:
	var path: String = "res://data/charts/%s/%s.json" % [track_id, diff]
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ChartLoader: cannot open %s" % path)
		return _empty_chart()
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ChartLoader: parse error in %s: %s" % [path, json.get_error_message()])
		return _empty_chart()
	var data: Dictionary = json.data
	if not data.has("notes") or not data.has("approach_time"):
		push_error("ChartLoader: missing fields in %s" % path)
		return _empty_chart()
	var notes: Array = data.get("notes", [])
	for nd in notes:
		# Ensure defaults
		if not nd.has("type"):
			nd["type"] = "tap"
		if not nd.has("lane"):
			nd["lane"] = 1
		# Moving note: default len
		if str(nd.get("type", "")) == "moving" and not nd.has("len"):
			nd["len"] = 1.2
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("t", 0.0) < b.get("t", 0.0)
	)
	return {
		"meta": data.get("meta", {}),
		"lanes": int(data.get("lanes", 3)),
		"approach_time": float(data.get("approach_time", 1.2)),
		"notes": notes,
	}

static func _empty_chart() -> Dictionary:
	return {"meta": {}, "lanes": 3, "approach_time": 1.2, "notes": []}
