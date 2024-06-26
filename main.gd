class_name Main
extends Node3D

@onready var start_scene := preload("res://start.tscn")
@onready var level_scene := preload("res://airbase_level.tscn")
@onready var dead_scene := preload("res://dead.tscn")
@onready var win_scene := preload("res://win.tscn")
var scene: Node


func _ready() -> void:
	go_to_start()


func go_to_start() -> void:
	if scene:
		scene.queue_free()
	
	var start: Start = start_scene.instantiate()
	add_child(start)
	start.start_button.button_down.connect(go_to_level)
	scene = start


func go_to_level() -> void:
	if scene:
		scene.queue_free()
	
	var level: Level = level_scene.instantiate()
	add_child(level)
	level.player_died.connect(go_to_dead)
	scene = level
	level.won.connect(go_to_win)


func go_to_dead() -> void:
	if scene:
		scene.queue_free()
	
	var dead: Dead = dead_scene.instantiate()
	add_child(dead)
	dead.restart_button.button_down.connect(go_to_start)
	scene = dead


func go_to_win() -> void:
	if scene:
		scene.queue_free()
	
	var win: Win = win_scene.instantiate()
	add_child(win)
	win.restart_button.button_down.connect(go_to_start)
	scene = win


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if get_child(0) is Start:
			get_tree().quit()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			go_to_start()
