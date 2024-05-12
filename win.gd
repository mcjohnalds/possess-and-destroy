class_name Win
extends Node3D

@onready var restart_button: Button = $UI/Button


func _ready() -> void:
	global.music_asp.volume_db = 0
