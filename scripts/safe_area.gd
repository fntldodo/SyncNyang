extends RefCounted

## SafeArea — static helper to apply display safe-area insets to UI nodes.
## Prevents UI from being hidden behind notches, punch-holes, or navigation bars.

## Returns {top, bottom, left, right} insets in viewport coordinates.
static func get_insets() -> Dictionary:
	var vp_rect: Rect2 = Engine.get_main_loop().root.get_visible_rect()
	var vp_size: Vector2 = vp_rect.size

	# Try to get the platform safe area
	var safe: Rect2 = DisplayServer.get_display_safe_area()

	# If safe area is zero/invalid, use fallback
	if safe.size.x < 1.0 or safe.size.y < 1.0:
		# Fallback: assume 48px top (status bar) and 32px bottom (nav bar) at 1080 width
		return {"top": 48.0, "bottom": 32.0, "left": 0.0, "right": 0.0}

	# DisplayServer returns screen-pixel coordinates.
	# Convert to viewport coordinates.
	var screen_size: Vector2 = DisplayServer.screen_get_size()
	if screen_size.x < 1.0 or screen_size.y < 1.0:
		screen_size = vp_size  # fallback

	var scale_x: float = vp_size.x / screen_size.x
	var scale_y: float = vp_size.y / screen_size.y

	var top: float = safe.position.y * scale_y
	var left: float = safe.position.x * scale_x
	var bottom: float = (screen_size.y - (safe.position.y + safe.size.y)) * scale_y
	var right: float = (screen_size.x - (safe.position.x + safe.size.x)) * scale_x

	# Clamp to reasonable range (avoid negative or absurdly large values)
	top = clampf(top, 0.0, vp_size.y * 0.15)
	bottom = clampf(bottom, 0.0, vp_size.y * 0.10)
	left = clampf(left, 0.0, vp_size.x * 0.10)
	right = clampf(right, 0.0, vp_size.x * 0.10)

	return {"top": top, "bottom": bottom, "left": left, "right": right}

## Apply safe insets as margin offsets to a Control node.
## The Control should use Full Rect anchors (preset 15).
## top_only / bottom_only can limit which insets are applied.
static func apply_margins(node: Control, top: bool = true, bottom: bool = true,
		left: bool = true, right: bool = true) -> void:
	var insets: Dictionary = get_insets()
	if top:
		node.offset_top += insets["top"]
	if bottom:
		node.offset_bottom -= insets["bottom"]
	if left:
		node.offset_left += insets["left"]
	if right:
		node.offset_right -= insets["right"]
