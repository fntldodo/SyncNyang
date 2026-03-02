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
const SCRATCH_SIZE := Vector2(190, 100)
const STRIP_WIDTH := 68.0

const DEBUG_HINT := true

# CAN colors
const CAN_BODY := Color(0.95, 0.72, 0.55)
const CAN_TOP := Color(0.85, 0.62, 0.45)
const CAN_OUTLINE := Color(0.5, 0.35, 0.25)
const CAN_LABEL := Color(1.0, 0.95, 0.85)

# FISH colors
const FISH_BODY := Color(0.45, 0.72, 0.95, 0.95)
const FISH_BELLY := Color(0.75, 0.88, 0.98, 0.85)
const FISH_TAIL := Color(0.5, 0.72, 0.88)
const FISH_OUTLINE := Color(0.36, 0.29, 0.24, 0.95)
const FISH_EYE := Color(0.15, 0.15, 0.2)
const FISH_CLAW := Color(0.36, 0.29, 0.24, 0.5)

# CHURU STRIP colors — on-track (bright)
const STRIP_ON := Color(0.95, 0.55, 0.75, 0.9)
const STRIP_ON_GLOW := Color(1.0, 0.7, 0.88, 0.4)
const STRIP_ON_HIGHLIGHT := Color(1.0, 0.88, 0.93, 0.6)
# off-track (dimmed)
const STRIP_OFF := Color(0.55, 0.48, 0.52, 0.5)
const STRIP_OFF_GLOW := Color(0.6, 0.55, 0.58, 0.15)
# shared
const STRIP_OUTLINE := Color(0.6, 0.3, 0.45, 0.9)
const STRIP_STAR := Color(1.0, 0.95, 0.7, 0.85)
const STRIP_PAW := Color(0.6, 0.3, 0.45, 0.35)
# near-end release indicator
const STRIP_END_GLOW := Color(1.0, 0.95, 0.5, 0.6)

# Hint colors
const HINT_BG := Color(0.1, 0.1, 0.1, 0.6)
const HINT_FG := Color(1.0, 1.0, 0.7, 0.9)

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
		custom_minimum_size = SCRATCH_SIZE
		size = SCRATCH_SIZE
		rotation_degrees = -15.0 if diag == "/" else 15.0
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
		_draw_can()
	elif note_type == "moving":
		_draw_churu_strip()
	else:
		_draw_fish()
		_draw_debug_hint()

## ---- CAN (tap note) ----

func _draw_can() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = w * 0.5
	var mx: float = w * 0.12
	var body_rect := Rect2(mx, h * 0.25, w - mx * 2, h * 0.69)
	draw_rect(body_rect, CAN_BODY)
	draw_rect(Rect2(mx + 2, h * 0.4, w - mx * 2 - 4, h * 0.18), CAN_LABEL)
	var top_rect := Rect2(mx + 4, h * 0.17, w - mx * 2 - 8, h * 0.1)
	draw_rect(top_rect, CAN_TOP)
	draw_circle(Vector2(cx + w * 0.1, h * 0.2), w * 0.05, CAN_OUTLINE)
	draw_circle(Vector2(cx + w * 0.1, h * 0.2), w * 0.03, CAN_TOP)
	draw_rect(body_rect, CAN_OUTLINE, false, 1.0)
	draw_rect(top_rect, CAN_OUTLINE, false, 0.8)
	_draw_tiny_paw(Vector2(cx, h * 0.52), CAN_OUTLINE)

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
	draw_circle(pos + Vector2(0, 2), 4.5, color)
	draw_circle(pos + Vector2(-5, -4), 2.5, color)
	draw_circle(pos + Vector2(0, -6), 2.5, color)
	draw_circle(pos + Vector2(5, -4), 2.5, color)
