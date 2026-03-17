extends Control

## FeverUI — Manages rainbow overlay, labels, and specialized Fever inputs.
## Decoupled from GameUI to reduce line count and complexity.

signal door_opened_bonus()

var overlay: ColorRect = null
var label: Label = null
var game_ui: Control = null

var FeverCanScript := preload("res://scripts/fever_can.gd")

var _fever_can: Control = null
var _scratch_area: Panel = null
var _fever_tween: Tween = null

# Scratch Input State
var _active_pointer_id: int = -1
var _last_scratch_pos: Vector2 = Vector2.ZERO
var _scratch_accum: float = 0.0
const SCRATCH_STEP_PX := 24.0

func _ready() -> void:
	game_ui = get_parent()
	
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create Overlay
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color(1.0, 0.8, 0.9, 0.0)
	overlay.visible = false
	add_child(overlay)
	
	# Create Fever Label
	label = Label.new()
	label.text = "🔥 FEVER TIME 🔥"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-250, 160)
	label.size = Vector2(500, 100)
	label.add_theme_font_size_override("font_size", 80)
	label.modulate = Color(1.0, 0.85, 0.2, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.pivot_offset = Vector2(250, 50)
	add_child(label)
	
	# Create Localized Scratch Input Area
	_scratch_area = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0, 0, 0.0) # Invisible but captures input (Red removed)
	_scratch_area.add_theme_stylebox_override("panel", sb)
	_scratch_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_scratch_area.z_index = 20
	_scratch_area.gui_input.connect(_on_scratch_input)
	_scratch_area.visible = false
	add_child(_scratch_area)


func start_fever(controller: Node) -> void:
	if overlay:
		overlay.visible = true
		_start_rainbow_cycle()
	
	if label:
		label.scale = Vector2(0.3, 0.3)
		label.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_property(label, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT)
		tw.tween_property(label, "scale", Vector2(0.9, 0.9), 0.1)
		tw.tween_property(label, "scale", Vector2(1.0, 1.0), 0.08)
		tw.tween_interval(1.2)
		tw.tween_property(label, "modulate:a", 0.0, 0.3)

	_spawn_fever_can(controller)
	if _scratch_area: _scratch_area.visible = true

func end_fever() -> void:
	if overlay: 
		overlay.visible = false
		overlay.color.a = 0.0
	if label: label.modulate.a = 0.0
	
	if _scratch_area: 
		_scratch_area.visible = false
		_scratch_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scratch_area.hide()
	
	_active_pointer_id = -1
	_scratch_accum = 0.0
	
	if _fever_tween and _fever_tween.is_valid():
		_fever_tween.kill()
		_fever_tween = null
	
	if _fever_can and is_instance_valid(_fever_can):
		_fever_can.slide_away()
		_fever_can = null
	
	print("[FEVER_UI] Fever ended, scratch area disabled and hidden.")

func _start_rainbow_cycle() -> void:
	if _fever_tween and _fever_tween.is_valid():
		_fever_tween.kill()
		
	_fever_tween = create_tween().set_loops()
	var colors: Array[Color] = [
		Color(1.0, 0.5, 0.5, 0.18),
		Color(1.0, 0.75, 0.3, 0.18),
		Color(1.0, 1.0, 0.4, 0.18),
		Color(0.4, 1.0, 0.5, 0.18),
		Color(0.4, 0.7, 1.0, 0.18),
		Color(0.7, 0.4, 1.0, 0.18),
		Color(1.0, 0.5, 0.75, 0.18),
	]
	for col in colors:
		_fever_tween.tween_property(overlay, "color", col, 0.35)

func _spawn_fever_can(_controller: Node) -> void:
	if not _fever_can or not is_instance_valid(_fever_can):
		_fever_can = FeverCanScript.new()
		add_child(_fever_can)
		_fever_can.can_opened.connect(_on_can_opened)
		
		# Connect to controller to hide scratch area when door bonus is awarded
		if _controller and _controller.has_signal("fever_door_opened"):
			if not _controller.fever_door_opened.is_connected(_on_fever_door_opened):
				_controller.fever_door_opened.connect(_on_fever_door_opened)
	
	var vs := get_viewport().get_visible_rect().size
	var can_w := vs.x * 0.75
	var can_h := vs.y * 0.40
	_fever_can.size = Vector2(can_w, can_h)
	_fever_can.position = Vector2((vs.x - can_w) * 0.5, -can_h - 100)
	
	if _fever_can.has_method("reset"): _fever_can.reset()
	
	# Drop it in from the top
	var target_y := vs.y * 0.35 # Slightly lower center
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_fever_can, "position:y", target_y, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_scratch_area, "position:y", target_y, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	_scratch_area.size = _fever_can.size
	_scratch_area.position = _fever_can.position

func _on_scratch_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		pass # TMI
	else:
		print("[FEVER_INPUT] event=", event.get_class(), " pos=", event.position if "position" in event else "N/A")
		
	var controller := get_node_or_null("../GameController")
	if not controller or not controller.is_fever: return
	
	if event is InputEventScreenTouch:
		if event.pressed:
			_active_pointer_id = event.index
			_last_scratch_pos = event.position
			_scratch_accum = 0.0
			# First-touch recognition: +1 hit immediately
			var count: int = controller.handle_fever_scratch()
			handle_scratch(event.position, count)
		elif event.index == _active_pointer_id:
			_active_pointer_id = -1
			_scratch_accum = 0.0 # Reset on release
	elif event is InputEventScreenDrag:
		if event.index == _active_pointer_id:
			var delta: float = (event.position - _last_scratch_pos).length()
			_scratch_accum += delta
			_last_scratch_pos = event.position
			
			if _scratch_accum >= SCRATCH_STEP_PX:
				var hits: int = int(_scratch_accum / SCRATCH_STEP_PX)
				_scratch_accum -= float(hits) * SCRATCH_STEP_PX
				for i in range(hits):
					var count: int = controller.handle_fever_scratch()
					handle_scratch(event.position, count)
	elif event is InputEventMouseButton:
		if event.pressed:
			_active_pointer_id = 0
			_last_scratch_pos = event.position
			_scratch_accum = 0.0
			var count: int = controller.handle_fever_scratch()
			handle_scratch(event.position, count)
		else:
			_active_pointer_id = -1
			_scratch_accum = 0.0
	elif event is InputEventMouseMotion and _active_pointer_id == 0:
		var delta: float = (event.position - _last_scratch_pos).length()
		_scratch_accum += delta
		_last_scratch_pos = event.position
		if _scratch_accum >= SCRATCH_STEP_PX:
			var count_m: int = controller.handle_fever_scratch()
			handle_scratch(event.position, count_m)

func _on_can_opened() -> void:
	door_opened_bonus.emit()

func handle_scratch(pos: Vector2, count: int) -> void:
	if _fever_can and is_instance_valid(_fever_can):
		_fever_can.add_scratch(pos)
		_fever_can.set_count(count)
func _on_fever_door_opened(_bonus: int) -> void:
	if _scratch_area:
		_scratch_area.visible = false
		_scratch_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("[FEVER_UI] Door opened, hiding scratch area early.")
