extends Control

## NoteView — procedural drawing for tap (CAN), scratch (FISH), 꾹꾹 (CHURU STRIP).
## TICKET 8.2: time-based smooth consume + on-track tint + near-end highlight.

var note_type: String = "tap"
var diag: String = "\\"
var lane_pair: int = -1
var note_len: float = 1.2

## 꾹꾹 visual state (updated by game_controller each frame)
var time_progress: float = 0.0   # 0..1 time through [start_t, end_t] — controls consume
var on_track_now: bool = false    # currently holding correct lane
var in_hold_window: bool = false  # within [start_t, end_t]
var near_end: bool = false        # near end_t — "ready to release" highlight
var is_holding: bool = false      # note has been started (pressed)

const NOTE_SIZE := Vector2(170, 100)
const STRIP_WIDTH := 68.0
const DEBUG_HINT := true

# FISH colors (scratch fallback)
const FISH_BODY := Color(0.45, 0.72, 0.95, 0.95)
const FISH_BELLY := Color(0.75, 0.88, 0.98, 0.85)
const FISH_TAIL := Color(0.5, 0.72, 0.88)
const FISH_OUTLINE := Color(0.36, 0.29, 0.24, 0.95)
const FISH_EYE := Color(0.15, 0.15, 0.2)
const FISH_CLAW := Color(0.36, 0.29, 0.24, 0.5)

# CHURU STRIP colors
const STRIP_ON := Color(0.95, 0.55, 0.75, 0.9)
const STRIP_ON_GLOW := Color(1.0, 0.7, 0.88, 0.4)
const STRIP_ON_HIGHLIGHT := Color(1.0, 0.88, 0.93, 0.6)
const STRIP_OFF := Color(0.55, 0.48, 0.52, 0.5)
const STRIP_OFF_GLOW := Color(0.6, 0.55, 0.58, 0.15)
const STRIP_OUTLINE := Color(0.6, 0.3, 0.45, 0.9)
const STRIP_STAR := Color(1.0, 0.95, 0.7, 0.85)
const STRIP_PAW := Color(0.6, 0.3, 0.45, 0.35)
const STRIP_END_GLOW := Color(1.0, 0.95, 0.5, 0.6)

# Hint colors
const HINT_BG := Color(0.1, 0.1, 0.1, 0.6)
const HINT_FG := Color(1.0, 1.0, 0.7, 0.9)

# COLOR PALETTE: Coral & Lavender (TICKET B-Next)
const COLOR_UFO_BODY := Color(1.0, 0.49, 0.44)    # Coral
const COLOR_UFO_SHADOW := Color(0.9, 0.4, 0.35)
const COLOR_UFO_GLOW := Color(0.9, 0.75, 1.0, 0.4) # Lavender Glow
const COLOR_PAW_TRAIL := Color(0.6, 0.3, 0.45, 0.25) # Cocoa Brown / Paw Purple
const COLOR_UFO_OUTLINE := Color(0.37, 0.29, 0.24, 0.9) # Cocoa Brown

var _spawn_anim_time: float = 0.0
const SPAWN_KUNG_DURATION := 0.25

var _full_height: float = 130.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(type: String, diag_dir: String = "\\", note_lane: int = 0,
		len_sec: float = 1.2, approach_time: float = 1.2, travel_dist: float = 1200.0) -> void:
	note_type = type
	diag = diag_dir
	note_len = len_sec
	if type == "scratch":
		lane_pair = clampi(note_lane, 0, 1)
		custom_minimum_size = NOTE_SIZE
		size = NOTE_SIZE
		# Increased tilt to 25 degrees to make it look like a very obvious diagonal requirement
		rotation_degrees = -25.0 if diag == "/" else 25.0
	elif type == "moving":
		lane_pair = -1
		var strip_h: float = (len_sec / maxf(approach_time, 0.1)) * travel_dist
		strip_h = maxf(strip_h, 80.0)
		_full_height = strip_h
		custom_minimum_size = Vector2(STRIP_WIDTH, strip_h)
		size = Vector2(STRIP_WIDTH, strip_h)
		rotation_degrees = 0.0
	else:
		lane_pair = -1
		custom_minimum_size = NOTE_SIZE
		size = NOTE_SIZE
		rotation_degrees = 0.0
	pivot_offset = size * 0.5
	queue_redraw()

func _draw() -> void:
	if note_type == "tap":
		_draw_ufo_stamp(false)
	elif note_type == "moving":
		_draw_churu_strip()
	else:
		_draw_ufo_stamp(true)

func _process(delta: float) -> void:
	if _spawn_anim_time < SPAWN_KUNG_DURATION:
		_spawn_anim_time += delta
		queue_redraw()

## ---- UFO STAMP (TICKET B-Next) ----

func _draw_ufo_stamp(is_scratch: bool) -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	
	# 1. Draw Paw Trail (Repeating icons behind the note)
	# The trail fades out as it goe up
	_draw_paw_trail(cx, cy, h)
	
	# 2. Spawn Animation (Kung Bounce)
	var t: float = clampf(_spawn_anim_time / SPAWN_KUNG_DURATION, 0.0, 1.0)
	var anim_scale: float = 1.0
	
	if t < 1.0:
		anim_scale = lerpf(1.3, 1.0, t) # Bounce from 1.3 to 1.0

	# UFO Body Drawing (Coral)
	var body_w: float = w * 0.65 * anim_scale
	var body_h: float = h * 0.5 * anim_scale
	var body_rect := Rect2(cx - body_w * 0.5, cy - body_h * 0.5, body_w, body_h)
	
	# Glow (Lavender)
	draw_circle(Vector2(cx, cy), body_w * 0.6, COLOR_UFO_GLOW)
	
	# Main Body
	draw_rect(body_rect, COLOR_UFO_BODY, true)
	draw_rect(body_rect, COLOR_UFO_OUTLINE, false, 2.0)
	
	# Top Handle/Dome
	var dome_r: float = body_w * 0.25
	draw_circle(Vector2(cx, cy - body_h * 0.4), dome_r, COLOR_UFO_SHADOW)
	draw_circle(Vector2(cx, cy - body_h * 0.4), dome_r, COLOR_UFO_OUTLINE, false, 2.0)
	
	# Stamp Pattern (Tiny paw in the center)
	_draw_tiny_paw(Vector2(cx, cy), COLOR_UFO_OUTLINE)
	
	if is_scratch:
		# Draw directional indicators for scratch
		var arrow_col := Color(1.0, 1.0, 0.8)
		var txt := ">>" if diag == "\\" else "<<"
		draw_string(ThemeDB.fallback_font, Vector2(cx - 20, cy + 10), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 24, arrow_col)

func _draw_paw_trail(cx: float, cy: float, _h: float) -> void:
	# Only draw trail if not at the very top
	var count := 4
	for i in range(1, count + 1):
		var offset_y: float = -i * 120.0
		var trail_alpha: float = lerpf(0.3, 0.0, float(i) / float(count))
		var trail_col := COLOR_PAW_TRAIL
		trail_col.a *= trail_alpha
		_draw_tiny_paw(Vector2(cx, cy + offset_y), trail_col)

## ---- FISH (scratch note) ----

func _draw_fish() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	var rx: float = w * 0.36
	var ry: float = h * 0.22
	var body_pts := _make_ellipse(cx, cy, rx, ry)
	draw_colored_polygon(body_pts, FISH_BODY)
	var belly_pts := _make_ellipse(cx, cy + 4, rx * 0.6, ry * 0.45)
	draw_colored_polygon(belly_pts, FISH_BELLY)
	var tail_x: float = cx - rx - 4
	var tail_sz: float = h * 0.18
	var tail_pts := PackedVector2Array([
		Vector2(tail_x + 4, cy),
		Vector2(tail_x - tail_sz, cy - tail_sz),
		Vector2(tail_x - tail_sz, cy + tail_sz),
	])
	draw_colored_polygon(tail_pts, FISH_TAIL)
	draw_polyline(PackedVector2Array([
		tail_pts[0], tail_pts[1], tail_pts[2], tail_pts[0]
	]), FISH_OUTLINE, 0.8)
	_draw_polygon_outline(body_pts)
	var eye_x: float = cx + rx * 0.45
	draw_circle(Vector2(eye_x, cy - 4), w * 0.04, Color.WHITE)
	draw_circle(Vector2(eye_x, cy - 4), w * 0.025, FISH_EYE)
	_draw_body_claws(cx, cy, ry)

## ---- CHURU STRIP (꾹꾹) with time-based smooth consume ----

func _draw_churu_strip() -> void:
	var w: float = size.x
	var h: float = _full_height
	var cx: float = w * 0.5
	var tube_w: float = w * 0.47
	var half_tw: float = tube_w * 0.5

	# Time-based consume: top portion disappears smoothly
	var consumed_px: float = h * clampf(time_progress, 0.0, 0.95)
	var draw_top: float = consumed_px
	var draw_h: float = h - consumed_px
	if draw_h < 14.0:
		draw_h = 14.0
		draw_top = h - 14.0

	# Choose colors based on hold correctness
	var body_col: Color = STRIP_ON if (on_track_now and is_holding) else STRIP_OFF
	var glow_col: Color = STRIP_ON_GLOW if (on_track_now and is_holding) else STRIP_OFF_GLOW

	# If not yet started (idle), show full brightness
	if not is_holding and time_progress < 0.01:
		body_col = STRIP_ON
		glow_col = STRIP_ON_GLOW

	# Outer glow
	draw_rect(Rect2(cx - half_tw - 8, draw_top, tube_w + 16, draw_h), glow_col)
	# Main tube body
	draw_rect(Rect2(cx - half_tw, draw_top + 2, tube_w, draw_h - 4), body_col)
	# Center highlight (only when on-track)
	if on_track_now and is_holding:
		draw_rect(Rect2(cx - 5, draw_top + 4, 10, draw_h - 8), STRIP_ON_HIGHLIGHT)
	# Outline
	draw_rect(Rect2(cx - half_tw, draw_top + 2, tube_w, draw_h - 4), STRIP_OUTLINE, false, 1.6)

	# Top cap
	draw_rect(Rect2(cx - half_tw - 3, draw_top, tube_w + 6, 4), STRIP_OUTLINE, false, 1.3)
	# Bottom cap
	draw_rect(Rect2(cx - half_tw - 3, h - 4, tube_w + 6, 4), STRIP_OUTLINE, false, 1.3)

	# Paw marks on remaining strip
	var paw_y: float = draw_top + 50.0
	while paw_y < h - 30.0:
		_draw_tiny_paw(Vector2(cx, paw_y), STRIP_PAW)
		paw_y += 160.0

	# Bottom sparkle (hit point indicator)
	_draw_sparkle(Vector2(cx, h - 16))

	# Near-end release highlight — golden glow at bottom
	if near_end and is_holding:
		draw_circle(Vector2(cx, h - 8), 22.0, STRIP_END_GLOW)
		draw_circle(Vector2(cx, h - 8), 14.0, Color(1.0, 0.98, 0.8, 0.4))

	# On-track holding ring at bottom
	if on_track_now and is_holding and in_hold_window:
		draw_circle(Vector2(cx, h - 8), 18.0, Color(1.0, 0.9, 0.6, 0.3))

func _draw_sparkle(pos: Vector2) -> void:
	var arm: float = 7.0
	draw_line(pos + Vector2(-arm, 0), pos + Vector2(arm, 0), STRIP_STAR, 1.3)
	draw_line(pos + Vector2(0, -arm), pos + Vector2(0, arm), STRIP_STAR, 1.3)
	draw_line(pos + Vector2(-5, -5), pos + Vector2(5, 5), STRIP_STAR, 1.0)
	draw_line(pos + Vector2(5, -5), pos + Vector2(-5, 5), STRIP_STAR, 1.0)

## ---- Debug key hint (editor only) ----

func _draw_debug_hint() -> void:
	if not DEBUG_HINT or not OS.has_feature("editor"):
		return
	var key: String = _get_hint_key()
	if key.is_empty():
		return
	var pos := Vector2(size.x - 20, 14)
	draw_circle(pos, 14.0, HINT_BG)
	draw_string(ThemeDB.fallback_font, pos + Vector2(-7, 7), key, HORIZONTAL_ALIGNMENT_CENTER, -1, 20, HINT_FG)

func _get_hint_key() -> String:
	if note_type != "scratch" or lane_pair < 0:
		return ""
	return "QW" if lane_pair == 0 else "WE"

## ---- Drawing helpers ----

func _draw_body_claws(cx: float, cy: float, ry: float) -> void:
	var offsets: Array = [-10.0, 0.0, 10.0]
	for ox in offsets:
		draw_line(
			Vector2(cx + ox - 6, cy - ry * 0.5),
			Vector2(cx + ox + 6, cy + ry * 0.5),
			FISH_CLAW, 1.2
		)

func _draw_polygon_outline(pts: PackedVector2Array) -> void:
	for i in range(pts.size()):
		draw_line(pts[i], pts[(i + 1) % pts.size()], FISH_OUTLINE, 0.8)

func _make_ellipse(cx: float, cy: float, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(32):
		var angle: float = TAU * i / 32.0
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	return pts

func _draw_tiny_paw(pos: Vector2, color: Color) -> void:
	# Main pad
	draw_circle(pos + Vector2(0, 2), 6.5, color)
	# Toe pads
	draw_circle(pos + Vector2(-7, -4), 3.5, color)
	draw_circle(pos + Vector2(0, -7), 3.5, color)
	draw_circle(pos + Vector2(7, -4), 3.5, color)
