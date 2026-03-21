extends Node2D

## Note.gd
## 단순 도트 낙하 테스트용 스크립트

@export var speed: float = 400.0
var lane_index: int = 0

func _ready() -> void:
	# 시각 요소 생성 (ColorRect)
	var rect = ColorRect.new()
	rect.size = Vector2(40, 40)
	rect.position = -rect.size / 2.0 # 중심 정렬
	rect.color = Color.CYAN
	add_child(rect)

func _process(delta: float) -> void:
	# 아래로 이동
	position.y += speed * delta
	
	# 화면 아래로 벗어나면 삭제 (1300 정도 기준)
	if position.y > 1300:
		queue_free()
