extends Control

## Game UI — input wiring, lane detection, difficulty selector.
## TICKET 10: Churu gauge bar + Fever overlay.

const Judgement := preload("res://scripts/judgement.gd")

## TopBar
@onready var back_btn: Button = $"TopBar/BackBtn"
@onready var next_btn: Button = $"TopBar/NextBtn"

## Game elements
@onready var hit_line: ColorRect = $"HitLine"
@onready var judge_label: Label = $"JudgeLabel"
@onready var game_controller: Node = $"GameController"
@onready var tap_area: Panel = $"TapArea"
@onready var fx_layer: Node = $"FxLayer"
@onready var notes_layer: Control = $"NotesLayer"
@onready var cursor_indicator: ColorRect = $"CursorIndicator"

## Lane geometry
const NUM_LANES := 3
var _lane_centers: Array = []
var _lane_width: float = 0.0
var _scratch_threshold_y: float = 40.0

## State
var _note_spawn_y: float = 200.0
var _judge_tween: Tween = null
var _current_diff: String = "normal"
var _last_action: String = "tap"

## Touch tracking (tap/scratch)
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_active: bool = false

## Hold state (꾹꾹)
var _held_lane: int = 1
var _holding: bool = false

## Keyboard hold tracking via polling
var _prev_q_held: bool = false
var _prev_w_held: bool = false
var _prev_e_held: bool = false

## Debug keyboard
const DEBUG_KEYS := true
const COMBO_WINDOW_MS := 120.0
var _last_key: int = -1
var _last_key_time_ms: float = 0.0

## Ring indicators (per lane)
var _ring_nodes: Array = []

## Hit box indicators (per lane)
var _hitbox_nodes: Array = []
const HIT_ZONE_HEIGHT := 110.0

## Churu gauge UI (TICKET 10)
var _gauge_bg: ColorRect = null
var _gauge_fill: ColorRect = null
const GAUGE_BAR_W := 700.0
const GAUGE_BAR_H := 16.0

## Fever overlay (TICKET 10)
var _fever_overlay: ColorRect = null
var _fever_label: Label = null
var _fever_tween: Tween = null

## Score/Combo labels (TICKET 10-3 / TICKET 12: from scene HudCard)
@onready var _score_label: Label = $"TopBar/HudCard/HudVBox/ScoreLabel"
@onready var _combo_label: Label = $"TopBar/HudCard/HudVBox/ComboLabel"

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	next_btn.pressed.connect(_on_next)
	game_controller.judgement_emitted.connect(_on_judgement)
	game_controller.run_finished.connect(_on_run_finished)
	game_controller.gauge_changed.connect(_on_gauge_changed)
	game_controller.fever_started.connect(_on_fever_started)
	game_controller.fever_ended.connect(_on_fever_ended)
	game_controller.score_changed.connect(_on_score_changed)
	tap_area.gui_input.connect(_on_tap_area_input)
	judge_label.modulate.a = 0.0

	_compute_lane_geometry()
	_setup_controller()
	_create_ring_indicators()
	_create_hit_boxes()
	_create_gauge_bar()
	_create_fever_overlay()
	_update_cursor_visual()
	_current_diff = SceneRouter.selected_difficulty
	_start_chart(_current_diff)

func _process(_delta: float) -> void:
	# Poll keyboard hold state + detect press/release transitions
	if DEBUG_KEYS and OS.has_feature("editor"):
		_poll_keyboard_hold()
	# Sync cursor state to controller
	game_controller.cursor_lane = _held_lane
	game_controller.cursor_holding = _holding
	game_controller.process_update()
	_update_cursor_visual()
	_update_ring_indicators()

## ---- Lane geometry ----

func _compute_lane_geometry() -> void:
	var vw: float = get_viewport().get_visible_rect().size.x
	_lane_width = vw / float(NUM_LANES)
	_lane_centers.clear()
	for i in range(NUM_LANES):
		_lane_centers.append(_lane_width * (float(i) + 0.5))
	_scratch_threshold_y = vw * 0.06

func _get_lane_from_x(x: float) -> int:
	if _lane_width <= 0:
		return 1
	return clampi(int(x / _lane_width), 0, NUM_LANES - 1)

func _get_scratch_pair_from_x(x: float) -> int:
	var mid: float = _lane_centers[1] if _lane_centers.size() > 1 else 540.0
	return 0 if x < mid else 1

## ---- Cursor visual ----

func _update_cursor_visual() -> void:
	if not cursor_indicator or _lane_centers.is_empty():
		return
	var cx: float = _lane_centers[_held_lane] if _held_lane < _lane_centers.size() else 540.0
	var indicator_w: float = 80.0
	cursor_indicator.position.x = cx - indicator_w * 0.5
	cursor_indicator.size.x = indicator_w
	cursor_indicator.modulate.a = 0.7 if _holding else 0.35

## ---- Ring indicators (per lane at hitline) ----

func _create_ring_indicators() -> void:
	for i in range(NUM_LANES):
		var ring := ColorRect.new()
		ring.size = Vector2(60, 20)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.color = Color(0.7, 0.7, 0.7, 0.15)
		ring.position = Vector2(_lane_centers[i] - 30, hit_line.position.y - 10)
		add_child(ring)
		_ring_nodes.append(ring)

func _update_ring_indicators() -> void:
	for i in range(_ring_nodes.size()):
		var ring: ColorRect = _ring_nodes[i]
		if _holding and _held_lane == i:
			ring.color = Color(1.0, 0.85, 0.5, 0.5)  # bright gold when held
		else:
			ring.color = Color(0.7, 0.7, 0.7, 0.15)  # dim when not held

## ---- Hit boxes (per lane at hitline) ----

func _create_hit_boxes() -> void:
	var box_w: float = _lane_width * 0.92
	var box_y: float = hit_line.position.y - HIT_ZONE_HEIGHT * 0.5
	for i in range(NUM_LANES):
		var box := ColorRect.new()
		box.size = Vector2(box_w, HIT_ZONE_HEIGHT)
		box.position = Vector2(_lane_centers[i] - box_w * 0.5, box_y)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.color = Color(0.95, 0.88, 0.75, 0.08)
		add_child(box)
		# Move behind notes but in front of BG
		move_child(box, get_child_count() - 2)
		_hitbox_nodes.append(box)

func _flash_hit_box(lane: int) -> void:
	if lane < 0 or lane >= _hitbox_nodes.size():
		return
	var box: ColorRect = _hitbox_nodes[lane]
	var tw := create_tween()
	box.color = Color(1.0, 0.92, 0.7, 0.25)
	tw.tween_property(box, "color", Color(0.95, 0.88, 0.75, 0.08), 0.12)

## ---- Churu Gauge Bar (TICKET 10) ----

func _create_gauge_bar() -> void:
	var vw: float = get_viewport().get_visible_rect().size.x
	var bar_x: float = (vw - GAUGE_BAR_W) * 0.5
	var bar_y: float = 1240.0  # above target zone
	# Background (cream)
	_gauge_bg = ColorRect.new()
	_gauge_bg.size = Vector2(GAUGE_BAR_W, GAUGE_BAR_H)
	_gauge_bg.position = Vector2(bar_x, bar_y)
	_gauge_bg.color = Color(0.96, 0.93, 0.88, 0.5)
	_gauge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gauge_bg)
	# Fill (coral pastel)
	_gauge_fill = ColorRect.new()
	_gauge_fill.size = Vector2(0, GAUGE_BAR_H - 4)
	_gauge_fill.position = Vector2(bar_x + 2, bar_y + 2)
	_gauge_fill.color = Color(0.95, 0.55, 0.65, 0.8)
	_gauge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gauge_fill)

func _on_gauge_changed(value: float) -> void:
	if _gauge_fill:
		var ratio: float = clampf(value / 100.0, 0.0, 1.0)
		_gauge_fill.size.x = (GAUGE_BAR_W - 4) * ratio
		# Color shifts toward gold as gauge fills
		_gauge_fill.color = Color(
			lerpf(0.95, 1.0, ratio),
			lerpf(0.55, 0.85, ratio),
			lerpf(0.65, 0.4, ratio),
			0.8
		)

## ---- Fever Overlay (TICKET 10) ----

func _create_fever_overlay() -> void:
	# Fullscreen overlay (hidden by default)
	_fever_overlay = ColorRect.new()
	_fever_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fever_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fever_overlay.color = Color(1.0, 0.8, 0.9, 0.0)
	_fever_overlay.visible = false
	add_child(_fever_overlay)
	# FEVER label (hidden) — big and flashy
	_fever_label = Label.new()
	_fever_label.text = "🔥 FEVER TIME 🔥"
	_fever_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fever_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fever_label.position = Vector2(-250, 160)
	_fever_label.size = Vector2(500, 100)
	_fever_label.add_theme_font_size_override("font_size", 80)
	_fever_label.modulate = Color(1.0, 0.85, 0.2, 0.0)
	_fever_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fever_label.pivot_offset = Vector2(250, 50)
	add_child(_fever_label)

func _on_fever_started() -> void:
	if _fever_overlay:
		_fever_overlay.visible = true
		_start_rainbow_cycle()
	# Big flashy FEVER label entrance
	if _fever_label:
		_fever_label.scale = Vector2(0.3, 0.3)
		_fever_label.modulate.a = 1.0
		var tw := create_tween()
		# Bounce in
		tw.tween_property(_fever_label, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT)
		tw.tween_property(_fever_label, "scale", Vector2(0.9, 0.9), 0.1)
		tw.tween_property(_fever_label, "scale", Vector2(1.0, 1.0), 0.08)
		# Hold visible
		tw.tween_interval(1.2)
		# Fade out
		tw.tween_property(_fever_label, "modulate:a", 0.0, 0.3)

func _on_fever_ended() -> void:
	if _fever_overlay:
		_fever_overlay.visible = false
	if _fever_label:
		_fever_label.modulate.a = 0.0
	if _fever_tween and _fever_tween.is_valid():
		_fever_tween.kill()
		_fever_tween = null

func _start_rainbow_cycle() -> void:
	if _fever_tween and _fever_tween.is_valid():
		_fever_tween.kill()
	_fever_tween = create_tween().set_loops()
	# Vivid rainbow colors — more intense alpha for visibility
	var colors: Array[Color] = [
		Color(1.0, 0.5, 0.5, 0.18),  # vivid red
		Color(1.0, 0.75, 0.3, 0.18), # vivid orange
		Color(1.0, 1.0, 0.4, 0.18),  # vivid yellow
		Color(0.4, 1.0, 0.5, 0.18),  # vivid green
		Color(0.4, 0.7, 1.0, 0.18),  # vivid blue
		Color(0.7, 0.4, 1.0, 0.18),  # vivid purple
		Color(1.0, 0.5, 0.75, 0.18), # vivid pink
	]
	for col in colors:
		_fever_tween.tween_property(_fever_overlay, "color", col, 0.35)

## ---- Score / Combo Labels (TICKET 12: from scene HudCard) ----

func _on_score_changed(new_score: int, new_combo: int) -> void:
	if _score_label:
		_score_label.text = str(new_score)
	if _combo_label:
		if new_combo >= 2:
			_combo_label.text = "%d COMBO" % new_combo
			_combo_label.add_theme_color_override("font_color", Color(0.85, 0.5, 0.2, 0.9))
		else:
			_combo_label.text = ""
			_combo_label.add_theme_color_override("font_color", Color(0.85, 0.5, 0.2, 0.0))

## ---- Controller setup ----

func _setup_controller() -> void:
	game_controller.notes_layer = notes_layer
	game_controller.spawn_y = _note_spawn_y
	game_controller.hitline_y = hit_line.position.y
	game_controller.lane_centers_x = _lane_centers
	game_controller.hit_zone_half_h = HIT_ZONE_HEIGHT * 0.5

## ---- Difficulty (TICKET 12: moved to Boot, kept internal for debug) ----

func _on_diff_selected(diff: String) -> void:
	_current_diff = diff
	game_controller.stop_run()
	_start_chart(diff)

func _start_chart(diff: String) -> void:
	game_controller.start_run(diff)

## ---- Navigation ----

func _on_back() -> void:
	game_controller.stop_run()
	SceneRouter.back()

func _on_next() -> void:
	SaveData.last_run_summary = game_controller.get_run_summary()
	game_controller.stop_run()
	SceneRouter.flow_to_result()

func _on_run_finished() -> void:
	SaveData.last_run_summary = game_controller.get_run_summary()
	SceneRouter.flow_to_result()

## ---- Input ----

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		game_controller.stop_run()
		SceneRouter.handle_global_back_action()
		return
	# Debug keyboard TAP/SCRATCH (editor only) — press events only
	if DEBUG_KEYS and OS.has_feature("editor") and event is InputEventKey and event.pressed and not event.echo:
		_handle_debug_key(event.keycode)

func _on_tap_area_input(event: InputEvent) -> void:
	# Touch events
	if event is InputEventScreenTouch:
		_handle_touch(event.position, event.pressed)
		return
	if event is InputEventScreenDrag:
		_update_held_lane_from_x(event.position.x)
		return
	# Mouse events (editor testing)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(event.position, event.pressed)
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_update_held_lane_from_x(event.position.x)
		return

func _handle_touch(pos: Vector2, pressed: bool) -> void:
	if pressed:
		_touch_start_pos = pos
		_touch_active = true
		_holding = true
		_update_held_lane_from_x(pos.x)
	else:
		_holding = false
		if not _touch_active:
			return
		_touch_active = false
		tap_area.accept_event()
		_classify_and_dispatch(pos)

func _update_held_lane_from_x(x: float) -> void:
	_held_lane = _get_lane_from_x(x)
	_holding = true

func _classify_and_dispatch(end_pos: Vector2) -> void:
	var dx: float = end_pos.x - _touch_start_pos.x
	var dy: float = end_pos.y - _touch_start_pos.y
	if absf(dy) > absf(dx) and absf(dy) >= _scratch_threshold_y:
		_last_action = "scratch"
		game_controller.handle_scratch(_get_scratch_pair_from_x(_touch_start_pos.x))
	else:
		_last_action = "tap"
		game_controller.handle_tap(_get_lane_from_x(_touch_start_pos.x))

## ---- Judgement display + FX ----

func _on_judgement(grade: int, delta_ms: float) -> void:
	_show_judge(grade, delta_ms)
	_spawn_pawprint_fx(grade)
	_flash_hit_box(_held_lane)

func _show_judge(grade: int, delta_ms: float = 0.0) -> void:
	if _judge_tween and _judge_tween.is_valid():
		_judge_tween.kill()
	var ms_text: String = "%dms" % int(absf(delta_ms))
	judge_label.text = "%s (%s)" % [Judgement.get_grade_name(grade), ms_text]
	judge_label.modulate = Judgement.get_color(grade)
	judge_label.modulate.a = 1.0
	_judge_tween = create_tween()
	_judge_tween.tween_interval(0.25)
	_judge_tween.tween_property(judge_label, "modulate:a", 0.0, 0.15)

func _spawn_pawprint_fx(grade: int) -> void:
	var tint: Color = Judgement.get_color(grade)
	var spawn_pos: Vector2 = hit_line.global_position + Vector2(30.0, -30.0)
	var is_scratch: bool = (_last_action == "scratch")
	fx_layer.spawn_pawprint(spawn_pos, tint, is_scratch, 0)

## ---- Debug keyboard: QWE polling + press/release detection ----
## Polling detects physical hold state AND transitions (press/release).
## Press → fires TAP + moving_press.
## Release → fires moving_release.

func _poll_keyboard_hold() -> void:
	var q: bool = Input.is_key_pressed(KEY_Q)
	var w: bool = Input.is_key_pressed(KEY_W)
	var e: bool = Input.is_key_pressed(KEY_E)

	# Detect press transitions: was not held → now held
	if q and not _prev_q_held:
		game_controller.handle_moving_press(0)
	if w and not _prev_w_held:
		game_controller.handle_moving_press(1)
	if e and not _prev_e_held:
		game_controller.handle_moving_press(2)

	# Detect release transitions: was held → now not held
	if not q and _prev_q_held:
		game_controller.handle_moving_release(0)
	if not w and _prev_w_held:
		game_controller.handle_moving_release(1)
	if not e and _prev_e_held:
		game_controller.handle_moving_release(2)

	# Update prev state
	_prev_q_held = q
	_prev_w_held = w
	_prev_e_held = e

	# Set holding state from polling
	if q:
		_held_lane = 0
		_holding = true
	elif w:
		_held_lane = 1
		_holding = true
	elif e:
		_held_lane = 2
		_holding = true
	else:
		if not _touch_active:
			_holding = false

## TAP/SCRATCH on key press (co-exists with moving_press)
func _handle_debug_key(keycode: int) -> void:
	if keycode != KEY_Q and keycode != KEY_W and keycode != KEY_E:
		return
	var lane: int = _key_to_lane(keycode)
	# Check scratch combo
	var now_ms: float = float(Time.get_ticks_msec())
	if _last_key >= 0 and (now_ms - _last_key_time_ms) <= COMBO_WINDOW_MS:
		var pair: int = _try_scratch_pair(_last_key, keycode)
		if pair >= 0:
			_last_action = "scratch"
			game_controller.handle_scratch(pair)
			_last_key = -1
			return
	# Immediate TAP
	_last_action = "tap"
	game_controller.handle_tap(lane)
	_last_key = keycode
	_last_key_time_ms = now_ms

func _try_scratch_pair(first: int, second: int) -> int:
	if (first == KEY_Q and second == KEY_W) or (first == KEY_W and second == KEY_Q):
		return 0
	if (first == KEY_W and second == KEY_E) or (first == KEY_E and second == KEY_W):
		return 1
	return -1

func _key_to_lane(keycode: int) -> int:
	match keycode:
		KEY_Q: return 0
		KEY_W: return 1
		KEY_E: return 2
	return 1
