extends Node

## SaveData — persistent local save to user://save.json.
## Autoloaded singleton.

const SAVE_PATH := "user://save.json"

var coins: int = 0
var inventory: Dictionary = {}  # { item_id: count }
var equipped: Dictionary = {
	"fur_color": "none",
	"outfit": "none",
	"accessory": "none",
	"pedicure": "none",
}

## Transient: last run summary from GameController (not saved to file)
var last_run_summary: Dictionary = {}

func _ready() -> void:
	load_data()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		save_data()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SaveData: JSON parse error")
		return
	var data: Dictionary = json.data
	coins = int(data.get("coins", 0))
	var inv_raw: Dictionary = data.get("inventory", {})
	inventory.clear()
	for key in inv_raw:
		inventory[key] = int(inv_raw[key])
	var eq_raw: Dictionary = data.get("equipped", {})
	for cat in equipped:
		if eq_raw.has(cat):
			equipped[cat] = str(eq_raw[cat])

func save_data() -> void:
	var data: Dictionary = {
		"coins": coins,
		"inventory": inventory,
		"equipped": equipped,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("SaveData: cannot write save file")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func add_coins(amount: int) -> void:
	coins += amount
	save_data()

func add_item(item_id: String, count: int = 1) -> void:
	if inventory.has(item_id):
		inventory[item_id] += count
	else:
		inventory[item_id] = count
	save_data()

func get_item_count(item_id: String) -> int:
	return inventory.get(item_id, 0)

func equip(cat: String, item_id: String) -> void:
	equipped[cat] = item_id
	save_data()

func get_equipped(cat: String) -> String:
	return equipped.get(cat, "none")

func get_inventory_items_for_category(cat: String, items_db: RefCounted) -> Array:
	var result: Array = []
	for item_id in inventory:
		if inventory[item_id] <= 0:
			continue
		var item: Dictionary = items_db.get_item_by_id(item_id)
		if item.is_empty():
			continue
		if item.get("cat", "") == cat:
			result.append(item)
	return result
