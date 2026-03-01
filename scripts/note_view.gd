extends Control

## NoteView — procedural drawing for tap (CAN), scratch (FISH), moving (LINE).
## Supports diagonal rotation (fish) and debug key hints.

var note_type: String = "tap"
var diag: String = "\\"
var lane_pair: int = -1
var note_len: float = 0.6  # for moving notes: visual length in seconds

const NOTE_SIZE := Vector2(130, 130)
const SCRATCH_SIZE := Vector2(160, 130)
const MOVING_SIZE := Vector2(100, 130)

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

# LINE (moving) colors
const LINE_BODY := Color(0.92, 0.55, 0.75, 0.9)
const LINE_GLOW := Color(1.0, 0.7, 0.85, 0.35)
const LINE_OUTLINE := Color(0.6, 0.3, 0.45, 0.95)
const LINE_STAR := Color(1.0, 0.95, 0.7, 0.9)

# Hint colors
const HINT_BG := Color(0.1, 0.1, 0.1, 0.6)
const HINT_FG := Color(1.0, 1.0, 0.7, 0.9)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(type: String, diag_dir: String = "\\", note_lane: int = 0, len_sec: float = 0.6) -> void:
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
		custom_minimum_size = MOVING_SIZE
		size = MOVING_SIZE
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
		_draw_line_note()
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
	draw_rect(body_rect, CAN_OUTLINE, false, 2.5)
	draw_rect(top_rect, CAN_OUTLINE, false, 2.0)
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
	]), FISH_OUTLINE, 2.0)
	_draw_polygon_outline(body_pts)
	var eye_x: float = cx + rx * 0.45
	draw_circle(Vector2(eye_x, cy - 4), w * 0.04, Color.WHITE)
	draw_circle(Vector2(eye_x, cy - 4), w * 0.025, FISH_EYE)
	_draw_body_claws(cx, cy, ry)

## ---- LINE (moving note) — churu tube ----

func _draw_line_note() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = w * 0.5
	# Outer glow
	var glow_rect := Rect2(cx - 24, 4, 48, h - 8)
	draw_rect(glow_rect, LINE_GLOW)
	# Tube body (rounded feel via layered rects)
	var tube_rect := Rect2(cx - 16, 8, 32, h - 16)
	draw_rect(tube_rect, LINE_BODY)
	# Highlight stripe
	draw_rect(Rect2(cx - 6, 10, 12, h - 20), Color(1.0, 0.85, 0.92, 0.5))
	# Outline
	draw_rect(tube_rect, LINE_OUTLINE, false, 2.5)
	# Cap top (squeeze top)
	draw_rect(Rect2(cx - 20, 4, 40, 10), LINE_OUTLINE, false, 2.0)
	# Small star/sparkle at bottom
	_draw_sparkle(Vector2(cx, h - 18))
	# Tiny paw at center
	_draw_tiny_paw(Vector2(cx, h * 0.45), LINE_OUTLINE)

func _draw_sparkle(pos: Vector2) -> void:
	var arm: float = 8.0
	draw_line(pos + Vector2(-arm, 0), pos + Vector2(arm, 0), LINE_STAR, 2.0)
	draw_line(pos + Vector2(0, -arm), pos + Vector2(0, arm), LINE_STAR, 2.0)
	draw_line(pos + Vector2(-5, -5), pos + Vector2(5, 5), LINE_STAR, 1.5)
	draw_line(pos + Vector2(5, -5), pos + Vector2(-5, 5), LINE_STAR, 1.5)

## ---- Debug key hint (editor only) ----

func _draw_debug_hint() -> void:
	if not DEBUG_HINT or not OS.has_feature("editor"):
		return
	var key: String = _get_hint_key()
	if key.is_empty():
		return
	var w: float = size.x
	var pos := Vector2(w - 20, 14)
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
			FISH_CLAW, 3.0
		)

func _draw_polygon_outline(pts: PackedVector2Array) -> void:
	for i in range(pts.size()):
		draw_line(pts[i], pts[(i + 1) % pts.size()], FISH_OUTLINE, 2.0)

func _make_ellipse(cx: float, cy: float, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(32):
		var angle: float = TAU * i / 32.0
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	return pts

func _draw_tiny_paw(pos: Vector2, color: Color) -> void:
	draw_circle(pos + Vector2(0, 3), 6.0, color)
	draw_circle(pos + Vector2(-7, -5), 3.5, color)
	draw_circle(pos + Vector2(0, -8), 3.5, color)
	draw_circle(pos + Vector2(7, -5), 3.5, color)
