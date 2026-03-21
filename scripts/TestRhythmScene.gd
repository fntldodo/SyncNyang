extends Node2D

## TestRhythmScene.gd
## BGM 재생 + 3레인 도트 낙하 테스트

# 설정 가능한 상수들
# --- TUNING PARAMETERS ---
const NOTE_SPEED: float = 500.0        # 낙하 속도
const HITLINE_Y: float = 1100.0        # 히트라인 시각화 위치
const SPAWN_Y: float = -50.0           # 생성 위치
const LANE_WIDTH: float = 180.0        # 레인 폭
const TRAVEL_TIME: float = 2.3         # (1100 - (-50)) / 500
const GLOBAL_OFFSET: float = 0.0      # 전체 싱크 오프셋 (초)
const USE_AUDIO_COMPENSATION: bool = true # 하드웨어 레이턴시 보정 여부

# --- ASSETS & PATHS ---
const CHARTS_DIR = "res://data/charts/"
# --- STATE ---
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var notes_container: Node2D = $Notes

var active_chart: Array = []
var next_note_idx: int = 0
var screen_center_x: float = 360.0
var lane_x_positions: Array = []
var current_song_offset: float = 0.0

func _ready() -> void:
	print("[TestRhythmScene] Stage 1 JSON Implementation...")
	
	lane_x_positions = [
		screen_center_x - LANE_WIDTH,
		screen_center_x,
		screen_center_x + LANE_WIDTH
	]
	
	_setup_visual_guides()
	_reset_test_session()

var last_chart_path: String = ""

func _reset_test_session(pick_random: bool = true) -> void:
	# 1. Cleanup
	music_player.stop()
	next_note_idx = 0
	active_chart = []
	current_song_offset = 0.0
	
	for n in notes_container.get_children():
		n.queue_free()
	
	# 2. Dynamic Loading (JSON based via Manifest)
	var manifest_path = "res://data/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		push_error("[TestRhythmScene] manifest.json not found!")
		return
		
	var manifest_text = FileAccess.get_file_as_string(manifest_path)
	var songs = JSON.parse_string(manifest_text)
	
	if songs == null or songs.size() == 0:
		push_error("[TestRhythmScene] Empty or invalid manifest!")
		return
	
	var chart_path = ""
	if pick_random or last_chart_path == "":
		var random_song = songs[randi() % songs.size()]
		chart_path = random_song["chart_path"]
		last_chart_path = chart_path
	else:
		chart_path = last_chart_path
		
	var success = load_chart_from_json(chart_path)
	
	# 3. Start Playback only on success
	if success and music_player.stream:
		music_player.play()
		print("[TestRhythmScene] RESET (Random:", pick_random, "): Playing with JSON Chart (Notes: ", active_chart.size(), ")")

func load_chart_from_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("[TestRhythmScene] JSON Chart not found: " + path)
		_clear_stale_state()
		return false
		
	var json_as_text = FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(json_as_text)
	
	if data == null:
		push_error("[TestRhythmScene] Failed to parse JSON: " + path)
		_clear_stale_state()
		return false
		
	# JSON 데이터 적용
	active_chart = data.get("notes", [])
	current_song_offset = data.get("config", {}).get("song_offset", 0.0)
	
	var audio_res_path = data.get("config", {}).get("audio_path", "")
	if audio_res_path != "":
		if not ResourceLoader.exists(audio_res_path):
			push_error("[TestRhythmScene] Audio file not found: " + audio_res_path)
			_clear_stale_state()
			return false
			
		var stream = load(audio_res_path)
		if stream:
			music_player.stream = stream
			return true
		else:
			push_error("[TestRhythmScene] Failed to load audio: " + audio_res_path)
			_clear_stale_state()
			return false
	
	return true # notes loaded but stream might be handle elsewhere (though usually here)

func _clear_stale_state() -> void:
	active_chart = []
	current_song_offset = 0.0
	music_player.stream = null

func _process(_delta: float) -> void:
	if not music_player.playing: return
	
	# --- SINGULAR EFFECTIVE TIMING SOURCE ---
	var audio_pos = music_player.get_playback_position()
	var compensation = 0.0
	if USE_AUDIO_COMPENSATION:
		compensation = AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	
	var effective_time = audio_pos + compensation + GLOBAL_OFFSET + current_song_offset
	
	# Spawning Logic
	while next_note_idx < active_chart.size():
		var note_data = active_chart[next_note_idx]
		# JSON에서는 t(time), l(lane) 키 사용 - SAFE DICT ACCESS
		if effective_time >= note_data["t"] - TRAVEL_TIME:
			_spawn_note_at(note_data["l"])
			next_note_idx += 1
		else:
			break

func _spawn_note_at(lane: int) -> void:
	var note_scene = load("res://scenes/Note.tscn")
	if note_scene:
		var note = note_scene.instantiate()
		note.lane_index = lane
		note.position = Vector2(lane_x_positions[lane], SPAWN_Y)
		note.speed = NOTE_SPEED
		notes_container.add_child(note)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		# 'R' 키로 세션 리셋
		if event.keycode == KEY_R:
			if event.shift_pressed:
				_reset_test_session(true)  # Shift+R: 새로운 랜덤 곡
			else:
				_reset_test_session(false) # R: 현재 곡 재시작
			return
			
		print("[SYNC_CHECK] Key Pressed at Time: ", music_player.get_playback_position())
		var lane := -1
		match event.keycode:
			KEY_Q: lane = 0
			KEY_W: lane = 1
			KEY_E: lane = 2
		if lane != -1:
			_check_hit(lane)
	
	# 터치/마우스 입력 처리
	if (event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)) and event.pressed:
		var vw := get_viewport_rect().size.x
		var lane := clampi(int(event.position.x / (vw / 3.0)), 0, 2)
		_check_hit(lane)

func _check_hit(lane_index: int) -> void:
	var hit_threshold: float = 100.0 # 판정 범위 (px)
	var best_note: Node2D = null
	var min_dist: float = 9999.0
	
	# Notes 컨테이너 안의 모든 노트를 검사
	for note in notes_container.get_children():
		if note.lane_index == lane_index:
			var dist = absf(note.position.y - HITLINE_Y)
			if dist < hit_threshold and dist < min_dist:
				min_dist = dist
				best_note = note
	
	if best_note:
		print("[TestRhythmScene] HIT! Lane: ", lane_index, " Dist: ", int(min_dist))
		best_note.queue_free() # 간단하게 삭제로 피드백
	else:
		print("[TestRhythmScene] MISS / Empty Lane: ", lane_index)

func _setup_visual_guides() -> void:
	# 레인 표시 (반투명 라인)
	for i in range(3):
		var lane_line = ColorRect.new()
		lane_line.size = Vector2(2, 1280)
		lane_line.position = Vector2(lane_x_positions[i] - 1, 0)
		lane_line.color = Color(1, 1, 1, 0.1)
		add_child(lane_line)
	
	# 히트라인 표시
	var hit_line = ColorRect.new()
	hit_line.size = Vector2(600, 4)
	hit_line.position = Vector2(screen_center_x - 300, HITLINE_Y)
	hit_line.color = Color(1, 0.2, 0.2, 0.8)
	add_child(hit_line)
