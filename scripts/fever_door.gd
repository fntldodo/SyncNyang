extends Control

## FeverDoor — Spaceship hatch over a starfield.
## Stars are always visible. Door panel is semi-transparent from the start.
## Scratching adds dramatic claw marks and door gets more transparent over time.

signal door_opened()

const OPEN_THRESHOLD := 20

var scratch_count: int = 0
var is_open: bool = false
var _scratch_marks: Array = []
var _progress: float = 0.0
var _shake_amount: float = 0.0
var _door_alpha: float = 1.0
var _flash: float = 0.0    ## White flash on each scratch (1.0 → 0.0)
var _stars: Array = []
var _time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_generate_stars()
	hide()  # Hidden by default

func reset() -> void:
	scratch_count = 0
	is_open = false
	_progress = 0.0
	_shake_amount = 0.0
	_door_alpha = 1.0
	_flash = 0.0
	_scratch_marks.clear()
	show()
	queue_redraw()

func _generate_stars() -> void:
	_stars.clear()
	# Big bright stars
	for i in range(15):
		_stars.append({
			"x": randf(), "y": randf_range(0.05, 0.8),
			"b": randf_range(0.8, 1.0), "s": randf_range(0.5, 1.5),
			"r": randf_range(5.0, 10.0), "type": "big"
		})
	# Medium stars
	for i in range(40):
		_stars.append({
			"x": randf(), "y": randf_range(0.02, 0.82),
			"b": randf_range(0.5, 0.9), "s": randf_range(1.0, 2.5),
			"r": randf_range(2.5, 5.0), "type": "med"
		})
	# Small twinkly stars
	for i in range(60):
		_stars.append({
			"x": randf(), "y": randf_range(0.0, 0.84),
			"b": randf_range(0.3, 0.7), "s": randf_range(1.5, 4.0),
			"r": randf_range(1.0, 2.5), "type": "sm"
		})

## Set the authoritative count from game_controller (single source of truth).
func set_count(count: int) -> void:
	if is_open:
		return
	scratch_count = clampi(count, 0, OPEN_THRESHOLD)
	_progress = clampf(float(scratch_count) / float(OPEN_THRESHOLD), 0.0, 1.0)
	_shake_amount = 15.0
	_flash = 1.0
	if scratch_count >= OPEN_THRESHOLD:
		_open_door()
	queue_redraw()

## Visual-only: adds claw mark lines at the touch position (no count change).
func add_scratch(touch_pos: Vector2) -> void:
	if is_open:
		return

	var local_pos: Vector2 = touch_pos - global_position
	local_pos.x = clampf(local_pos.x, 20, size.x - 20)
	local_pos.y = clampf(local_pos.y, 20, size.y * 0.75)

	# Cat claw marks: 3 parallel lines
	var base_angle: float = randf_range(-0.35, 0.35)
	for c in range(3):
		var off_y: float = float(c - 1) * randf_range(14, 22)
		var claw_pos := Vector2(local_pos.x, local_pos.y + off_y)
		var claw_len: float = randf_range(size.x * 0.18, size.x * 0.4)
		_scratch_marks.append({
			"pos": claw_pos, "angle": base_angle,
			"len": claw_len, "depth": randf_range(0.6, 1.0)
		})
	queue_redraw()

func _open_door() -> void:
	is_open = true
	door_opened.emit()
	var tw := create_tween()
	tw.tween_property(self, "_door_alpha", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(self.hide)

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
	tw.tween_property(self, "position:y", position.y - size.y - 100, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(self.hide)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var shake := Vector2.ZERO
	if _shake_amount > 0.1:
		shake = Vector2(
			randf_range(-_shake_amount, _shake_amount),
			randf_range(-_shake_amount * 0.3, _shake_amount * 0.3))

	# ===== LAYER 1: DEEP SPACE BACKGROUND =====
	var space_h: float = h * 0.84
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, space_h)), Color(0.015, 0.005, 0.06))

	# Nebula glow (soft purple/blue blobs)
	_draw_nebula(w, space_h)

	# Stars
	for star in _stars:
		var sx: float = star["x"] * w
		var sy: float = star["y"] * space_h
		var twinkle: float = (sin(_time * star["s"] * 2.5 + star["x"] * 17.0) + 1.0) * 0.5
		var b: float = star["b"] * lerpf(0.3, 1.0, twinkle)
		var sr: float = star["r"]

		if star["type"] == "big":
			# Big stars with glow halo + cross spikes
			draw_circle(Vector2(sx, sy), sr * 1.8, Color(0.4, 0.5, 0.9, b * 0.15))
			draw_circle(Vector2(sx, sy), sr, Color(0.6, 0.7, 1.0, b * 0.6))
			draw_circle(Vector2(sx, sy), sr * 0.4, Color(1, 1, 1, b))
			# Cross spikes
			var spike_len: float = sr * 2.5
			draw_line(Vector2(sx - spike_len, sy), Vector2(sx + spike_len, sy),
					  Color(0.8, 0.85, 1.0, b * 0.3), 1.0)
			draw_line(Vector2(sx, sy - spike_len), Vector2(sx, sy + spike_len),
					  Color(0.8, 0.85, 1.0, b * 0.3), 1.0)
		elif star["type"] == "med":
			draw_circle(Vector2(sx, sy), sr, Color(0.7, 0.8, 1.0, b * 0.7))
			draw_circle(Vector2(sx, sy), sr * 0.35, Color(1, 1, 1, b * 0.9))
		else:
			draw_circle(Vector2(sx, sy), sr, Color(0.8, 0.85, 1.0, b))

	# ===== LAYER 2: DOOR PANEL (semi-transparent, overlays stars) =====
	var door_opacity: float = lerpf(0.5, 0.05, _progress) * _door_alpha
	var door_margin: float = w * 0.04
	var door_top: float = space_h * 0.05 + shake.y
	var door_w: float = w - door_margin * 2
	var door_h: float = space_h * 0.9

	# Frame (slightly darker border)
	draw_rect(Rect2(Vector2(door_margin - 3 + shake.x, door_top - 3),
					Vector2(door_w + 6, door_h + 6)),
			  Color(0.08, 0.06, 0.15, door_opacity * 1.2))
	# Main door body
	draw_rect(Rect2(Vector2(door_margin + shake.x, door_top),
					Vector2(door_w, door_h)),
			  Color(0.2, 0.18, 0.32, door_opacity))
	# Inner panel highlight
	draw_rect(Rect2(Vector2(door_margin + 12 + shake.x, door_top + 12),
					Vector2(door_w - 24, door_h - 24)),
			  Color(0.28, 0.26, 0.45, door_opacity * 0.7))

	# Horizontal seam + glow
	var seam_y: float = door_top + door_h * 0.5
	draw_line(Vector2(door_margin + shake.x, seam_y),
			  Vector2(door_margin + door_w + shake.x, seam_y),
			  Color(0.4, 0.38, 0.55, door_opacity * 0.5), 2.0)
	if _progress > 0.02:
		var gw: float = 4.0 + _progress * 16.0
		draw_line(Vector2(door_margin + shake.x, seam_y),
				  Vector2(door_margin + door_w + shake.x, seam_y),
				  Color(0.4, 0.8, 1.0, _progress * 0.8 * _door_alpha), gw)

	# Rivets
	var rv_a: float = door_opacity * 0.5
	for fx in [0.15, 0.5, 0.85]:
		for fy in [0.1, 0.5, 0.9]:
			var rx: float = door_margin + door_w * fx + shake.x
			var ry: float = door_top + door_h * fy
			draw_circle(Vector2(rx, ry), 4.0, Color(0.5, 0.48, 0.6, rv_a))

	# ===== LAYER 3: CLAW SCRATCH MARKS =====
	for mark in _scratch_marks:
		var p: Vector2 = mark["pos"] + shake
		var a: float = mark["angle"]
		var ml: float = mark["len"]
		var dp: float = mark["depth"]
		var dir := Vector2(cos(a), sin(a))
		var sp: Vector2 = p - dir * ml * 0.5
		var ep: Vector2 = p + dir * ml * 0.5
		# Wide outer glow (blue)
		draw_line(sp, ep, Color(0.3, 0.6, 1.0, 0.25 * dp * _door_alpha), 12.0)
		# Inner glow (cyan)
		draw_line(sp, ep, Color(0.6, 0.9, 1.0, 0.5 * dp * _door_alpha), 5.0)
		# Sharp bright core (white-yellow)
		draw_line(sp, ep, Color(1.0, 1.0, 0.9, 0.95 * dp * _door_alpha), 2.0)

	# ===== LAYER 4: PROGRESS BAR =====
	var bar_y: float = space_h + 8
	var bar_h: float = 16.0
	var bar_mx: float = w * 0.08
	var bar_w: float = w - bar_mx * 2
	draw_rect(Rect2(Vector2(bar_mx, bar_y), Vector2(bar_w, bar_h)),
			  Color(0.06, 0.04, 0.12, _door_alpha * 0.8))
	var fill_w: float = (bar_w - 4) * _progress
	if fill_w > 2:
		draw_rect(Rect2(Vector2(bar_mx + 2, bar_y + 2), Vector2(fill_w, bar_h - 4)),
				  Color(1.0, 0.85, 0.3, _door_alpha))

	# ===== LAYER 5: INSTRUCTION TEXT =====
	draw_string(ThemeDB.fallback_font,
				Vector2(w * 0.5 - 90, space_h + 46),
				"← SCRATCH! →", HORIZONTAL_ALIGNMENT_CENTER, -1, 28,
				Color(1.0, 0.95, 0.85, _door_alpha * 0.85))

	# ===== LAYER 6: SCRATCH COUNT on progress bar =====
	var count_text: String = "%d / %d" % [scratch_count, OPEN_THRESHOLD]
	draw_string(ThemeDB.fallback_font,
				Vector2(w * 0.5 - 30, space_h + 24),
				count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 20,
				Color(1.0, 1.0, 1.0, _door_alpha * 0.9))

	# ===== LAYER 7: FLASH OVERLAY (whole door flashes white on scratch) =====
	if _flash > 0.02:
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, space_h)),
				  Color(1.0, 1.0, 1.0, _flash * 0.4 * _door_alpha))

func _draw_nebula(w: float, h: float) -> void:
	# Soft colored blobs for nebula effect
	var neb_data := [
		[0.3, 0.4, 80.0, Color(0.15, 0.05, 0.3, 0.2)],
		[0.7, 0.5, 60.0, Color(0.05, 0.1, 0.25, 0.15)],
		[0.5, 0.3, 100.0, Color(0.1, 0.03, 0.2, 0.12)],
		[0.2, 0.7, 50.0, Color(0.08, 0.12, 0.3, 0.1)],
	]
	for neb in neb_data:
		var nx: float = neb[0] * w
		var ny: float = neb[1] * h
		var nr: float = neb[2]
		var nc: Color = neb[3]
		# Draw concentric circles for soft glow
		for i in range(4):
			var frac: float = float(4 - i) / 4.0
			draw_circle(Vector2(nx, ny), nr * frac, nc * Color(1, 1, 1, frac * 0.5))
