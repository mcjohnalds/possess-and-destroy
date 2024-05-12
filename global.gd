extends Node


func _input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("ui_cancel"):
		get_tree().quit()
