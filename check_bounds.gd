@tool
extends SceneTree

func _init():
	var img = Image.load_from_file("res://assets/logo_title.png")
	if img == null:
		print("Failed to load image")
		quit()
		return
	var rect = img.get_used_rect()
	print("BOUNDS: ", rect.position.x, ",", rect.position.y, " ", rect.size.x, "x", rect.size.y)
	quit()
