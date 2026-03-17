extends HBoxContainer

## CalibrationUI — Handles input offset calibration independently.
## Decouples calibration buttons/logic from the core GameUI.

var label: Label = null
var minus_btn: Button = null
var plus_btn: Button = null
var game_controller: Node = null

func setup(controller: Node) -> void:
	game_controller = controller
	
	# Self Layout
	var vw := get_viewport().get_visible_rect().size.x
	position = Vector2(vw - 420, 8)
	size = Vector2(400, 50)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# -10 button
	minus_btn = Button.new()
	minus_btn.text = "-10ms"
	minus_btn.custom_minimum_size = Vector2(90, 44)
	minus_btn.pressed.connect(_on_minus)
	add_child(minus_btn)
	
	# Offset label
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(160, 44)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	
	# +10 button
	plus_btn = Button.new()
	plus_btn.text = "+10ms"
	plus_btn.custom_minimum_size = Vector2(90, 44)
	plus_btn.pressed.connect(_on_plus)
	add_child(plus_btn)
	
	_update_label()


func _on_minus() -> void:
	SaveData.input_offset_ms = clampf(SaveData.input_offset_ms - 10.0, -200.0, 200.0)
	if game_controller: game_controller.input_offset_ms = SaveData.input_offset_ms
	SaveData.save_data()
	_update_label()

func _on_plus() -> void:
	SaveData.input_offset_ms = clampf(SaveData.input_offset_ms + 10.0, -200.0, 200.0)
	if game_controller: game_controller.input_offset_ms = SaveData.input_offset_ms
	SaveData.save_data()
	_update_label()

func _update_label() -> void:
	if label:
		label.text = "OFFSET: %dms" % int(SaveData.input_offset_ms)
