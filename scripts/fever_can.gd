extends Control

## FeverCan — Giant magical cat food tin can that requires scratching to open.
## Replaces FeverDoor: players scratch the surface to tear back the lid.

signal can_opened()

const OPEN_THRESHOLD := 20

var scratch_count: int = 0
var is_open: bool = false
var _scratch_marks: Array = []
var _progress: float = 0.0
var _shake_amount: float = 0.0
var _can_alpha: float = 1.0
var _flash: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func reset() -> void:
	scratch_count = 0
	is_open = false
	_progress = 0.0
	_shake_amount = 0.0
	_can_alpha = 1.0
	_flash = 0.0
	_scratch_marks.clear()
	show()
	queue_redraw()

func set_count(count: int) -> void:
	if is_open:
		return
	scratch_count = clampi(count, 0, OPEN_THRESHOLD)
	_progress = clampf(float(scratch_count) / float(OPEN_THRESHOLD), 0.0, 1.0)
	_shake_amount = 15.0
	_flash = 1.0
	if scratch_count >= OPEN_THRESHOLD:
		_open_can()
	queue_redraw()

func add_scratch(touch_pos: Vector2) -> void:
	if is_open:
		return

	var local_pos: Vector2 = touch_pos - global_position
	local_pos.x = clampf(local_pos.x, 20, size.x - 20)
	local_pos.y = clampf(local_pos.y, 20, size.y * 0.75)

	# Claw marks
	var base_angle: float = randf_range(-0.35, 0.35)
	for c in range(3):
		var off_y: float = float(c - 1) * randf_range(14, 22)
		var claw_pos := Vector2(local_pos.x, local_pos.y + off_y)
		var claw_len: float = randf_range(size.x * 0.18, size.x * 0.4)
		_scratch_marks.append({
			"pos": claw_pos, "angle": base_angle,
			"len": claw_len, "depth": randf_range(0.6, 1.0)
		})
		
	# Instantly update visuals before external sync
	scratch_count = clampi(scratch_count + 1, 0, OPEN_THRESHOLD)
	_progress = clampf(float(scratch_count) / float(OPEN_THRESHOLD), 0.0, 1.0)
	_shake_amount = 15.0
	_flash = 1.0
	queue_redraw()

func _open_can() -> void:
	is_open = true
	can_opened.emit()
	var tw := create_tween()
	# The lid pops off, can sinks and fades
	tw.set_parallel(true)
	tw.tween_property(self, "_can_alpha", 0.0, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector2(1.2, 1.2), 0.4).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(self.hide)

func _process(delta: float) -> void:
	_time += delta
	if _shake_amount > 0.1:
		_shake_amount = lerpf(_shake_amount, 0.0, delta * 8.0)
	if _flash > 0.01:
		_flash = lerpf(_flash, 0.0, delta * 12.0)
	queue_redraw()

func slide_away() -> void:
	if is_open:
		return
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - size.y - 100, 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(self.hide)

func _draw() -> void:
	if _can_alpha <= 0.01:
		return
		
	var w: float = size.x
	var h: float = size.y
	var shake := Vector2.ZERO
	if _shake_amount > 0.1:
		shake = Vector2(
			randf_range(-_shake_amount, _shake_amount),
			randf_range(-_shake_amount * 0.3, _shake_amount * 0.3))

	# Shift everything down a bit for the lid animation
	var can_top := h * 0.15 + shake.y
	var can_h := h * 0.65
	
	# ===== CAN BODY =====
	var r := Rect2(Vector2(shake.x, can_top), Vector2(w, can_h))
	
	# Rim Shadow (Bottom ellipse)
	_draw_ellipse(Vector2(w * 0.5 + shake.x, can_top + can_h), w * 0.5, h * 0.08, Color(0.1, 0.1, 0.15, _can_alpha * 0.8))
	
	# Body (Gradient from side to center to simulate cylinder)
	# Base metallic body
	draw_rect(r, Color(0.7, 0.75, 0.85, _can_alpha))
	# Shadows on the edges
	draw_rect(Rect2(Vector2(shake.x, can_top), Vector2(w * 0.15, can_h)), Color(0.15, 0.15, 0.2, _can_alpha * 0.8))
	draw_rect(Rect2(Vector2(w * 0.85 + shake.x, can_top), Vector2(w * 0.15, can_h)), Color(0.15, 0.15, 0.2, _can_alpha * 0.8))
	
	# Soft highlight near center
	draw_rect(Rect2(Vector2(w * 0.35 + shake.x, can_top), Vector2(w * 0.2, can_h)), Color(1.0, 1.0, 1.0, _can_alpha * 0.4))
	
	# Middle Stripe Label (Coral / Lavender)
	var label_top := can_top + can_h * 0.3
	var label_h := can_h * 0.4
	draw_rect(Rect2(Vector2(shake.x, label_top), Vector2(w, label_h)), Color(0.95, 0.55, 0.65, _can_alpha)) # Coral
	draw_line(Vector2(shake.x, label_top), Vector2(w + shake.x, label_top), Color(0.65, 0.5, 0.85, _can_alpha * 0.6), 8) # Lavender Trim
	draw_line(Vector2(shake.x, label_top + label_h), Vector2(w + shake.x, label_top + label_h), Color(0.65, 0.5, 0.85, _can_alpha * 0.6), 8)

	# ===== CAN LID (Tear-away style) =====
	# As progress goes up, lid opens backwards
	var lid_shift_y := _progress * 40.0
	var lid_w := w * 0.96
	var lid_cy := can_top - lid_shift_y
	var lid_cx := w * 0.5 + shake.x
	
	# Inner Darkness (seen as lid pulls back)
	if _progress > 0.05:
		_draw_ellipse(Vector2(w * 0.5 + shake.x, can_top), w * 0.45, h * 0.05, Color(0.05, 0.05, 0.1, _can_alpha * 0.9))
		# Rainbow inner light from the opened can
		var inner_gw := _progress * w * 0.4
		draw_circle(Vector2(w * 0.5 + shake.x, can_top), inner_gw, Color(1.0, 0.9, 0.4, _can_alpha * _progress * 0.6))

	# Solid Lid Top
	_draw_ellipse(Vector2(lid_cx, lid_cy), lid_w * 0.5, h * 0.06, Color(0.8, 0.85, 0.9, _can_alpha))
	_draw_ellipse(Vector2(lid_cx, lid_cy), lid_w * 0.45, h * 0.05, Color(0.6, 0.65, 0.7, _can_alpha))
	
	# Pull Tab Ring
	var tab_x := lid_cx + w * 0.2
	var tab_y := lid_cy + _progress * 15.0
	draw_circle(Vector2(tab_x, tab_y), 15.0, Color(0.3, 0.3, 0.35, _can_alpha))
	draw_circle(Vector2(tab_x, tab_y), 10.0, Color(0.8, 0.85, 0.9, _can_alpha)) # Inner hole
	
	# Lid Outline
	draw_arc(Vector2(lid_cx, lid_cy), lid_w * 0.5, 0, TAU, 32, Color(0.9, 0.9, 0.95, _can_alpha * 0.8), 2.0)

	# ===== CLAW SCRATCH MARKS =====
	for mark in _scratch_marks:
		var p: Vector2 = mark["pos"] + shake
		var a: float = mark["angle"]
		var ml: float = mark["len"]
		var dp: float = mark["depth"]
		var dir := Vector2(cos(a), sin(a))
		var sp: Vector2 = p - dir * ml * 0.5
		var ep: Vector2 = p + dir * ml * 0.5
		# Big outer spark (yellow-orange)
		draw_line(sp, ep, Color(1.0, 0.8, 0.2, 0.35 * dp * _can_alpha), 16.0)
		# Inner cut (magenta/cyan)
		draw_line(sp, ep, Color(0.8, 0.2, 0.9, 0.6 * dp * _can_alpha), 6.0)
		# Deep tear (white)
		draw_line(sp, ep, Color(1.0, 1.0, 1.0, 0.95 * dp * _can_alpha), 2.0)

	# ===== PROGRESS BAR =====
	var bar_y := can_top + can_h + 30
	var bar_h := 16.0
	var bar_mx := w * 0.1
	var bar_w := w - bar_mx * 2
	draw_rect(Rect2(Vector2(bar_mx, bar_y), Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.15, _can_alpha * 0.8))
	var fill_w: float = (bar_w - 4) * _progress
	if fill_w > 2:
		draw_rect(Rect2(Vector2(bar_mx + 2, bar_y + 2), Vector2(fill_w, bar_h - 4)), Color(1.0, 0.8, 0.3, _can_alpha))

	# ===== INSTRUCTION TEXT =====
	draw_string(ThemeDB.fallback_font, Vector2(w * 0.5 - 90, bar_y + 46), "← SCRATCH! →", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(1.0, 0.95, 0.85, _can_alpha * 0.85))

	var count_text: String = "%d / %d" % [scratch_count, OPEN_THRESHOLD]
	draw_string(ThemeDB.fallback_font, Vector2(w * 0.5 - 30, bar_y + 24), count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(1.0, 1.0, 1.0, _can_alpha * 0.9))

	# ===== FLASH OVERLAY =====
	if _flash > 0.02:
		var fr := Rect2(Vector2(-w * 0.1, can_top - h * 0.1), Vector2(w * 1.2, can_h + h * 0.2))
		draw_rect(fr, Color(1.0, 1.0, 1.0, _flash * 0.35 * _can_alpha))

func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var segs := 32
	for i in range(segs + 1):
		var t := float(i) / float(segs) * TAU
		pts.append(center + Vector2(cos(t) * rx, sin(t) * ry))
	draw_colored_polygon(pts, color)
