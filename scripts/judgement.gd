extends RefCounted

## Static-like helper for judgement grading.
## Usage: var grade = Judgement.get_grade(delta_ms)
##        var color = Judgement.get_color(grade)

enum Grade { PERFECT, EXCELLENT, GOOD, SO_SO, MISS }

const GRADE_NAMES: Dictionary = {
	Grade.PERFECT: "PERFECT",
	Grade.EXCELLENT: "EXCELLENT",
	Grade.GOOD: "GOOD",
	Grade.SO_SO: "SO-SO",
	Grade.MISS: "MISS",
}

const GRADE_COLORS: Dictionary = {
	Grade.PERFECT: Color(1.0, 0.84, 0.0),      # gold
	Grade.EXCELLENT: Color(0.75, 0.75, 0.75),    # silver
	Grade.GOOD: Color(0.2, 0.4, 1.0),            # blue
	Grade.SO_SO: Color(0.2, 0.8, 0.3),           # green
	Grade.MISS: Color(1.0, 0.2, 0.2),            # red
}

## Thresholds in milliseconds (absolute value of delta).
const PERFECT_MS := 30
const EXCELLENT_MS := 60
const GOOD_MS := 90
const SO_SO_MS := 130

static func get_grade(delta_ms: float) -> int:
	var abs_ms: float = absf(delta_ms)
	if abs_ms <= PERFECT_MS:
		return Grade.PERFECT
	elif abs_ms <= EXCELLENT_MS:
		return Grade.EXCELLENT
	elif abs_ms <= GOOD_MS:
		return Grade.GOOD
	elif abs_ms <= SO_SO_MS:
		return Grade.SO_SO
	else:
		return Grade.MISS

static func get_color(grade: int) -> Color:
	if GRADE_COLORS.has(grade):
		return GRADE_COLORS[grade]
	return Color.WHITE

static func get_grade_name(grade: int) -> String:
	if GRADE_NAMES.has(grade):
		return GRADE_NAMES[grade]
	return "???"
