extends Control

const ItemsDB := preload("res://scripts/items_db.gd")
const SafeArea := preload("res://scripts/safe_area.gd")

@onready var back_btn: Button = $"Panel/BackBtn"
@onready var coins_label: Label = $"Panel/CoinsLabel"
@onready var equipped_label: Label = $"Panel/EquippedLabel"
@onready var cat_row: HBoxContainer = $"Panel/CatRow"
@onready var items_container: VBoxContainer = $"Panel/ItemsScroll/ItemsList"

var _items_db: RefCounted = null
var _current_cat: String = "fur_color"

const CATEGORIES: Array = ["fur_color", "outfit", "accessory", "pedicure"]
const CAT_LABELS: Dictionary = {
	"fur_color": "FUR",
	"outfit": "OUTFIT",
	"accessory": "ACC",
	"pedicure": "PEDI",
}

func _ready() -> void:
	_items_db = ItemsDB.new()
	back_btn.pressed.connect(_on_back)

	# Create category buttons dynamically
	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text = CAT_LABELS.get(cat, cat)
		btn.pressed.connect(_on_cat_selected.bind(cat))
		cat_row.add_child(btn)

	_apply_safe_area()
	_refresh_ui()

func _apply_safe_area() -> void:
	var insets: Dictionary = SafeArea.get_insets()
	var panel: Control = $"Panel"
	panel.offset_top += insets["top"]
	panel.offset_bottom -= insets["bottom"]

func _on_back() -> void:
	SceneRouter.back()

func _on_cat_selected(cat: String) -> void:
	_current_cat = cat
	_refresh_ui()

func _refresh_ui() -> void:
	# Coins
	coins_label.text = "Coins: %d" % SaveData.coins

	# Equipped summary
	var eq_lines: String = ""
	for cat in CATEGORIES:
		var item_id: String = SaveData.get_equipped(cat)
		var display: String = "none"
		if item_id != "none":
			var item: Dictionary = _items_db.get_item_by_id(item_id)
			display = item.get("name", item_id)
		eq_lines += "%s: %s\n" % [CAT_LABELS.get(cat, cat), display]
	equipped_label.text = eq_lines.strip_edges()

	# Populate items list for current category
	for child in items_container.get_children():
		child.queue_free()

	# "None" reset button
	var reset_btn := Button.new()
	reset_btn.text = "[ RESET to none ]"
	reset_btn.pressed.connect(_on_equip_item.bind("none"))
	items_container.add_child(reset_btn)

	# Items from inventory
	var items: Array = SaveData.get_inventory_items_for_category(_current_cat, _items_db)
	if items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(no items in inventory)"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		items_container.add_child(empty_label)
	else:
		for item in items:
			var btn := Button.new()
			var count: int = SaveData.get_item_count(item.get("id", ""))
			var eq_mark: String = " ★" if SaveData.get_equipped(_current_cat) == item.get("id", "") else ""
			btn.text = "%s [%s] x%d%s" % [
				item.get("name", "???"),
				item.get("rarity", "?").to_upper(),
				count,
				eq_mark
			]
			btn.pressed.connect(_on_equip_item.bind(item.get("id", "")))
			items_container.add_child(btn)

func _on_equip_item(item_id: String) -> void:
	SaveData.equip(_current_cat, item_id)
	_refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.handle_global_back_action()
