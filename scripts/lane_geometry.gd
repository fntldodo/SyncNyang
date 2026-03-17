const NUM_LANES := 3

static func get_lane_centers(viewport_size: Vector2, _y_ratio: float) -> Array:
	var vw := viewport_size.x
	var lane_w := vw / float(NUM_LANES)
	var centers := []
	for i in range(NUM_LANES):
		centers.append(lane_w * (float(i) + 0.5))
	return centers

static func get_lane_at_pos(pos: Vector2, viewport_size: Vector2) -> int:
	var vw := viewport_size.x
	var lane_w := vw / float(NUM_LANES)
	return clampi(int(pos.x / lane_w), 0, NUM_LANES - 1)

static func get_lane_width(viewport_size: Vector2, _y_ratio: float) -> float:
	return viewport_size.x / float(NUM_LANES)
