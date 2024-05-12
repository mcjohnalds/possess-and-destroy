class_name Dead
extends Node3D

@onready var restart_button: Button = $UI/Button
@onready var asp: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	asp.play(2.6)
