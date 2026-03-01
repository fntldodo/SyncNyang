extends RefCounted

## ItemsDB — loads and queries items.json.

var _items: Array = []
var _rarity_weights: Dictionary = {}
var _loaded: bool = false

func _init() -> void:
	_load_db()

func _load_db() -> void:
	var file := FileAccess.open("res://data/items/items.json", FileAccess.READ)
	if not file:
		push_error("ItemsDB: cannot open items.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ItemsDB: JSON parse error: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	_items = data.get("items", [])
	_rarity_weights = data.get("rarity_weights", {})
	_loaded = true

func is_loaded() -> bool:
	return _loaded

func get_all_items() -> Array:
	return _items

func get_item_by_id(item_id: String) -> Dictionary:
	for item in _items:
		if item.get("id", "") == item_id:
			return item
	return {}

func get_items_by_category(cat: String) -> Array:
	var result: Array = []
	for item in _items:
		if item.get("cat", "") == cat:
			result.append(item)
	return result

func get_items_by_rarity(rarity: String) -> Array:
	var result: Array = []
	for item in _items:
		if item.get("rarity", "") == rarity:
			result.append(item)
	return result

func get_rarity_weights(rank: String) -> Dictionary:
	return _rarity_weights.get(rank, {"common": 100, "rare": 0, "epic": 0})
