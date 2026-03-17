extends Control

## GameUI — [HOTFIX] PNG Lane Rescue & Layer Stratification.
## Objectives: Force visibility of line1/2/3.PNG and ensure box.PNG remains stable.
## DESIGN: 3-way split, no procedural panels, max brightness for textures.

const Judgement := preload("res://scripts/judgement.gd")
const SafeArea := preload("res://scripts/safe_area.gd")
const LaneGeometry := preload("res://scripts/lane_geometry.gd")
const FeverUI := preload("res://scripts/fever_ui.gd")
const CalibrationUI := preload("res://scripts/calibration_ui.gd")

## Nodes
@onready var back_btn: Button = $"TopBar/BackBtn"
@onready var next_btn: Button = $"TopBar/NextBtn"
@onready var hit_line: ColorRect = $HitLine
@onready var target_zone: Control = $TargetZone
@onready var judge_label: Label = $JudgeLabel
@onready var game_controller: Node = $GameController
@onready var tap_area: Panel = $TapArea
@onready var notes_layer: Control = $NotesLayer
@onready var cursor_indicator: ColorRect = $CursorIndicator
@onready var score_label: Label = $"TopBar/HudCard/HudVBox/ScoreLabel"
@onready var combo_label: Label = $"TopBar/HudCard/HudVBox/ComboLabel"

## PNG Layer Nodes
var lane_layer: Control = null
var hit_layer: Control = null
var _lane_tex: Array[TextureRect] = []
var _hit_tex: Array[TextureRect] = []

## Visual Constants
const COLOR_JUDGE_NEON := Color(1.0, 1.0, 1.0, 1.0) # White for max contrast now
const COLOR_COMBO_NEON := Color(1.0, 0.9, 0.4, 1.0) # Gold
const HIT_ZONE_HEIGHT := 80.0
const NUM_LANES := 3

## Specialized UI Modules
var fever_ui: Node = null
var calib_ui: Node = null

## Gauge Nodes
var _gauge_bg: ColorRect = null
var _gauge_fill: ColorRect = null
const GAUGE_BAR_W := 700.0
const GAUGE_BAR_H := 16.0

## State
var _held_lane: int = 1
var _holding: bool = false
var _run_cancelled: bool = false
var _ring_nodes: Array = []
var _judge_labels: Array[Label] = []
var _judge_pool_idx: int = 0

func _ready() -> void:
	Input.set_use_accumulated_input(false)
	
	back_btn.pressed.connect(_on_back)
	next_btn.pressed.connect(_on_next)
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	game_controller.judgement_emitted.connect(_on_judgement)
	game_controller.run_finished.connect(_on_run_finished)
	game_controller.gauge_changed.connect(_on_gauge_changed)
	game_controller.fever_started.connect(_on_fever_started)
	game_controller.fever_ended.connect(_on_fever_ended)
	game_controller.score_changed.connect(_on_score_changed)
	
	# Initial style setup (High-Density Pool: 8 Labels)
	judge_label.hide()
	for i in range(8):
		var nl = judge_label.duplicate()
		add_child(nl)
		nl.add_theme_color_override("font_color", Color.WHITE)
		nl.add_theme_constant_override("outline_size", 16)
		nl.add_theme_color_override("font_outline_color", Color.BLACK)
		nl.z_index = 100
		nl.hide()
		_judge_labels.append(nl)
	
	combo_label.add_theme_color_override("font_color", Color.WHITE)
	combo_label.add_theme_constant_override("outline_size", 16)
	combo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	_initialize_modules()
	
	await get_tree().process_frame
	await get_tree().process_frame
	_late_init()

func _late_init() -> void:
	if not is_inside_tree(): return
	
	# HOTFIX: Transparent TapArea
	tap_area.self_modulate = Color(1, 1, 1, 0.0)
	tap_area.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	
	_apply_safe_area()
	_setup_controller()
	_create_visual_layers()
	_reposition_visuals()
	_start_chart(SceneRouter.selected_difficulty)

func _initialize_modules() -> void:
	fever_ui = FeverUI.new()
	add_child(fever_ui)
	fever_ui.z_index = 25 # Highest layer as requested
	fever_ui.door_opened_bonus.connect(game_controller.award_door_bonus)
	
	if OS.has_feature("editor"):
		calib_ui = CalibrationUI.new()
		add_child(calib_ui)
		calib_ui.setup(game_controller)

func _setup_controller() -> void:
	if not is_inside_tree() or not get_viewport(): return
	var vs := get_viewport().get_visible_rect().size
	# Coordinate Stability
	game_controller.lane_centers_top = LaneGeometry.get_lane_centers(vs, 0.0)
	game_controller.lane_centers_bottom = LaneGeometry.get_lane_centers(vs, 1.0)
	game_controller.hitline_y = hit_line.global_position.y - global_position.y
	game_controller.notes_layer = notes_layer
	game_controller.hit_zone_half_h = HIT_ZONE_HEIGHT * 0.5
	game_controller.spawn_y = 120.0

func _create_visual_layers() -> void:
	# 1. Cleanup Old Layers if any
	if lane_layer: lane_layer.queue_free(); lane_layer = null
	if hit_layer: hit_layer.queue_free(); hit_layer = null
	
	# 2. Create Fresh Layer Nodes
	lane_layer = Control.new()
	lane_layer.name = "LaneLayer"
	lane_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	lane_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lane_layer)
	
	hit_layer = Control.new()
	hit_layer.name = "HitLayer"
	hit_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hit_layer)
	
	# 3. Layer Stratification (High-Visibility Positive Values)
	lane_layer.z_index = 10
	hit_layer.z_index = 11
	notes_layer.z_index = 15
	hit_line.z_index = 16
	$TopBar.z_index = 20
	judge_label.z_index = 100 # Ensure it's above everything
	
	# 4. Build Textures
	_build_lane_pngs()
	_build_hit_pngs()
	
	# 5. Feedback
	_create_ring_indicators()
	_create_gauge_bar()

func _build_lane_pngs() -> void:
	_lane_tex.clear()
	for i in range(NUM_LANES):
		var tr := TextureRect.new()
		tr.texture = load("res://assets/line%d.PNG" % (i + 1))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# VISIBILITY ARGS (Restored for visibility)
		tr.self_modulate = Color(2.0, 2.0, 2.0, 1.0) # Brightness boost needed
		tr.texture_filter = TEXTURE_FILTER_NEAREST
		tr.visible = true
		
		lane_layer.add_child(tr)
		_lane_tex.append(tr)
		print("[PNG_LANE] i=%d tex=%s status=OK" % [i, tr.texture])

func _build_hit_pngs() -> void:
	_hit_tex.clear()
	for i in range(NUM_LANES):
		var htr := TextureRect.new()
		htr.texture = load("res://assets/box.PNG")
		htr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		htr.stretch_mode = TextureRect.STRETCH_SCALE
		htr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		htr.self_modulate = Color(1.0, 1.0, 1.0, 0.45) # Reliable Alpha
		htr.visible = true
		hit_layer.add_child(htr)
		_hit_tex.append(htr)

func _reposition_visuals() -> void:
	if not is_inside_tree() or not get_viewport(): return
	var vs := get_viewport().get_visible_rect().size
	var hitline_y: float = hit_line.global_position.y - global_position.y
	var lane_w := vs.x / 3.0
	var top_y := 80.0
	
	if hitline_y < 100:
		get_tree().create_timer(0.2).timeout.connect(_reposition_visuals)
		return

	# Reposition Lanes (Simple 3rd Split)
	for i in range(_lane_tex.size()):
		var tr = _lane_tex[i]
		var l_x = i * lane_w
		var l_w = lane_w * 0.98
		var l_h = (hitline_y - top_y) + HIT_ZONE_HEIGHT * 0.5
		tr.position = Vector2(l_x + (lane_w * 0.01), top_y)
		tr.size = Vector2(l_w, max(l_h, 400.0))
		print("[LANE_TEX] i=%d size=%s pos=%s" % [i, tr.size, tr.position])

	# Reposition HitBoxes
	for i in range(_hit_tex.size()):
		var htr = _hit_tex[i]
		var h_w = lane_w * 0.94
		htr.size = Vector2(h_w, HIT_ZONE_HEIGHT)
		htr.position = Vector2((i * lane_w) + (lane_w * 0.03), hitline_y - HIT_ZONE_HEIGHT * 0.5)
		htr.pivot_offset = htr.size * 0.5

	# Others
	if _gauge_bg:
		var bar_x := (vs.x - GAUGE_BAR_W) * 0.5
		var bar_y := hitline_y - 150.0
		_gauge_bg.position = Vector2(bar_x, bar_y)
		_gauge_fill.position = Vector2(bar_x + 2, bar_y + 2)

	for i in range(_ring_nodes.size()):
		var ring: ColorRect = _ring_nodes[i]
		ring.position = Vector2((i + 0.5) * lane_w - 30, hitline_y - 10)
		ring.z_index = 70

func _on_viewport_resized() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_safe_area()
	_setup_controller()
	_reposition_visuals()

func _process(_delta: float) -> void:
	game_controller.cursor_lane = _held_lane
	game_controller.cursor_holding = _holding
	game_controller.process_update()
	_update_visual_status()

func _update_visual_status() -> void:
	for i in range(_ring_nodes.size()):
		var ring: ColorRect = _ring_nodes[i]
		ring.color = Color(1.0, 0.85, 0.5, 0.5) if (_holding and _held_lane == i) else Color(0.7, 0.7, 0.7, 0.15)
	$TopBar.modulate.a = 1.0

func _on_judgement(grade: int, _delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var grade_color := Judgement.get_color(grade)
	
	# Rotate through pool
	var lbl = _judge_labels[_judge_pool_idx]
	_judge_pool_idx = (_judge_pool_idx + 1) % _judge_labels.size()
	
	# Reset state
	lbl.text = Judgement.GRADE_NAMES[grade]
	lbl.modulate = grade_color * 3.0 # Maximum Glow for check
	lbl.modulate.a = 1.0
	lbl.scale = Vector2(0.5, 0.5)
	
	# Positioning: Center + Small random jitter to prevent perfect stacking
	var jitter := Vector2(randf_range(-40, 40), randf_range(-20, 20))
	lbl.position = Vector2(vs.x * 0.5 - 300, vs.y * 0.35 - 60) + jitter
	lbl.pivot_offset = Vector2(300, 30)
	lbl.show()
	
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	# Faster animation for high-density visibility
	tw.tween_property(lbl, "scale", Vector2(1.4, 1.4), 0.05)
	tw.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.1).set_delay(0.05)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.2).set_delay(0.25)
	
	_flash_hit_box(_held_lane)

func _on_score_changed(score: int, _combo: int) -> void:
	if score_label: score_label.text = str(score)
	if combo_label:
		combo_label.text = "%d COMBO" % _combo if _combo >= 2 else ""
		combo_label.modulate.a = 1.0 if _combo >= 2 else 0.0

func _on_gauge_changed(value: float) -> void:
	if _gauge_fill:
		var ratio := clampf(value / float(game_controller.GAUGE_MAX), 0.0, 1.0)
		_gauge_fill.size.x = (GAUGE_BAR_W - 4) * ratio

func _on_fever_started() -> void: fever_ui.start_fever(game_controller)
func _on_fever_ended() -> void: fever_ui.end_fever(); _reposition_visuals()
func _on_run_finished() -> void: SceneRouter.flow_to_result()
func _on_back() -> void: _run_cancelled = true; game_controller.stop_run(); SceneRouter.back()
func _on_next() -> void: _run_cancelled = true; SaveData.last_run_summary = game_controller.get_run_summary(); game_controller.stop_run(); SceneRouter.flow_to_result()

func _create_gauge_bar() -> void:
	if not _gauge_bg:
		_gauge_bg = ColorRect.new(); _gauge_bg.size = Vector2(GAUGE_BAR_W, GAUGE_BAR_H); _gauge_bg.color = Color(0.1, 0.08, 0.16, 0.5); add_child(_gauge_bg)
	if not _gauge_fill:
		_gauge_fill = ColorRect.new(); _gauge_fill.size = Vector2(0, GAUGE_BAR_H - 4); _gauge_fill.color = Color(0.95, 0.55, 0.65, 0.8); add_child(_gauge_fill)
	_gauge_bg.z_index = 8; _gauge_fill.z_index = 9

func _create_ring_indicators() -> void:
	for n in _ring_nodes: n.queue_free()
	_ring_nodes.clear()
	for i in range(NUM_LANES):
		var ring := ColorRect.new(); ring.size = Vector2(60, 20); ring.color = Color(0.7, 0.7, 0.7, 0.15); add_child(ring); _ring_nodes.append(ring)

func _flash_hit_box(lane: int) -> void:
	if lane < 0 or lane >= _hit_tex.size(): return
	var htr: TextureRect = _hit_tex[lane]
	var tw := create_tween()
	tw.set_parallel(true)
	htr.scale = Vector2(1.15, 1.15)
	htr.self_modulate = Color(2.5, 2.5, 4.0, 1.0)
	tw.tween_property(htr, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(htr, "self_modulate", Color(1.0, 1.0, 1.0, 0.45), 0.12)

func _start_chart(diff: String) -> void:
	_run_cancelled = false
	var vs := get_viewport().get_visible_rect().size
	var lbl := Label.new(); lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lbl.add_theme_font_size_override("font_size", 140); lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2)); lbl.position = Vector2(vs.x * 0.5 - 200, vs.y * 0.4 - 100); lbl.size = Vector2(400, 200); lbl.pivot_offset = Vector2(200, 100); add_child(lbl); lbl.z_index = 100
	var seq: Array = ["3", "2", "1", "START!"]
	for i in range(seq.size()):
		get_tree().create_timer(i * 1.0).timeout.connect(func():
			if _run_cancelled or not is_instance_valid(lbl): return
			lbl.text = str(seq[i]); lbl.scale = Vector2(0.3, 0.3); lbl.modulate.a = 1.0; var tw := create_tween(); tw.tween_property(lbl, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT); tw.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.1); tw.tween_interval(0.5); tw.tween_property(lbl, "modulate:a", 0.0, 0.25)
		)
	get_tree().create_timer(seq.size() * 1.0).timeout.connect(func():
		if is_instance_valid(lbl): lbl.queue_free()
		if not _run_cancelled and is_inside_tree(): game_controller.start_run(diff)
	)

func _unhandled_input(event: InputEvent) -> void:
	if game_controller.is_fever and not game_controller.fever_time_unfrozen: return
	if not game_controller.is_running(): return
	
	if event is InputEventKey and not event.is_echo():
		var l: int = -1
		var kcode: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		match kcode:
			KEY_Q: l = 0
			KEY_W: l = 1
			KEY_E: l = 2
		if l != -1:
			if event.is_pressed():
				_held_lane = l; _holding = true
				game_controller.handle_tap(l); game_controller.handle_moving_press(l)
			else:
				if _held_lane == l: _holding = false
				game_controller.handle_moving_release(l)
			return
			
	var pos: Vector2 = Vector2.ZERO
	var is_pressed: bool = false
	if event is InputEventScreenTouch:
		pos = event.position; is_pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position; is_pressed = event.pressed
	elif event is InputEventScreenDrag:
		pos = event.position; is_pressed = true
		
	if pos != Vector2.ZERO:
		var vs := get_viewport().get_visible_rect().size
		var l := LaneGeometry.get_lane_at_pos(pos, vs)
		if is_pressed:
			if l != -1:
				_held_lane = l; _holding = true
				if event is InputEventScreenTouch or event is InputEventMouseButton:
					game_controller.handle_tap(l); game_controller.handle_moving_press(l)
		else:
			_holding = false
			if l != -1: game_controller.handle_moving_release(l)
			elif _held_lane != -1: game_controller.handle_moving_release(_held_lane)

func _apply_safe_area() -> void:
	var insets := SafeArea.get_insets()
	$TopBar.position = Vector2(12.0 + insets["left"], 12.0 + insets["top"])
	var vs := get_viewport().get_visible_rect().size
	hit_line.position.y = vs.y - insets["bottom"] - 250.0
