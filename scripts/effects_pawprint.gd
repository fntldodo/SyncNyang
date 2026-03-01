extends Node

## Pawprint FX — spawns pawprint silhouette with tint color on judgement.
## TICKET 4: base pawprint + swipe afterimages (2~4)

const PAW_SIZE := Vector2(60, 60)
const FADE_DURATION_MIN := 0.35
const FADE_DURATION_MAX := 0.50
const AFTERIMAGE_COUNT := 3        # 2~4 afterimages for swipe
const AFTERIMAGE_SPACING := 40.0   # px between each afterimage
const AFTERIMAGE_DELAY := 0.04     # seconds between each spawn

## Try to load pawprint texture; null if not yet available.
var _paw_texture: Texture2D = null

func _ready() -> void:
	# Attempt to load external texture (when asset is added later)
	if ResourceLoader.exists("res://assets/sprites/paw_silhouette.png"):
		_paw_texture = load("res://assets/sprites/paw_silhouette.png")

## Main entry point: call from game_ui when judgement happens.
## pos: global spawn position
## tint: judgement color
## is_swipe: whether this was a swipe action
## swipe_dir: -1 = left, +1 = right, 0 = tap
func spawn_pawprint(pos: Vector2, tint: Color, is_swipe: bool, swipe_dir: int) -> void:
	# Spawn main pawprint
	_create_single_paw(pos, tint, 1.0)

	# Swipe afterimages
	if is_swipe:
		for i in range(AFTERIMAGE_COUNT):
			var offset_x: float = swipe_dir * AFTERIMAGE_SPACING * (i + 1)
			var after_pos: Vector2 = pos + Vector2(offset_x, 0)
			var alpha_scale: float = 0.7 - (i * 0.15)  # progressively more transparent
			var delay: float = AFTERIMAGE_DELAY * (i + 1)
			_spawn_delayed_paw(after_pos, tint, alpha_scale, delay)

## Create a single pawprint node at given position.
func _create_single_paw(pos: Vector2, tint: Color, alpha_scale: float) -> void:
	var paw: Control
	if _paw_texture:
		# Use real texture
		var tex_rect := TextureRect.new()
		tex_rect.texture = _paw_texture
		tex_rect.custom_minimum_size = PAW_SIZE
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paw = tex_rect
	else:
		# Procedural placeholder: circle-ish shape using ColorRect
		paw = _create_placeholder_paw()

	# Position (centered on pos)
	paw.position = pos - PAW_SIZE * 0.5
	paw.modulate = tint
	paw.modulate.a = alpha_scale

	add_child(paw)

	# Fade out tween
	var duration: float = randf_range(FADE_DURATION_MIN, FADE_DURATION_MAX)
	var tw: Tween = create_tween()
	tw.tween_property(paw, "modulate:a", 0.0, duration)
	tw.tween_callback(paw.queue_free)

## Procedural placeholder pawprint (main pad + 3 toe pads)
func _create_placeholder_paw() -> Control:
	var container := Control.new()
	container.custom_minimum_size = PAW_SIZE
	container.size = PAW_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Main pad (larger circle in center-bottom)
	var main_pad := ColorRect.new()
	main_pad.size = Vector2(28, 24)
	main_pad.position = Vector2(16, 28)
	main_pad.color = Color.BLACK
	main_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(main_pad)

	# Toe pads (3 small circles on top)
	var toe_positions: Array[Vector2] = [
		Vector2(8, 10),
		Vector2(24, 4),
		Vector2(40, 10),
	]
	for toe_pos in toe_positions:
		var toe := ColorRect.new()
		toe.size = Vector2(14, 14)
		toe.position = toe_pos
		toe.color = Color.BLACK
		toe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(toe)

	return container

## Spawn a pawprint after a delay (for afterimages).
func _spawn_delayed_paw(pos: Vector2, tint: Color, alpha_scale: float, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if is_inside_tree():
			_create_single_paw(pos, tint, alpha_scale)
	)
