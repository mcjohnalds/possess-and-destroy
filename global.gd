class_name Global
extends Node

enum Graphics { LOW, MEDIUM, HIGH }
enum Resolution { LOW, MEDIUM, HIGH }

var graphics := Graphics.HIGH
var resolution := Resolution.HIGH
@onready var environment: Environment = preload("res://environment.tres")
@onready var music_asp: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	set_graphics_high()
	set_resolution_high()


func set_graphics_low() -> void:
	graphics = Graphics.LOW
	environment.sdfgi_enabled = false
	environment.glow_enabled = false
	environment.volumetric_fog_enabled = false
	ProjectSettings.set_setting(
		"rendering/anti_aliasing/quality/msaa_3d", 0
	)


func set_graphics_medium() -> void:
	graphics = Graphics.MEDIUM
	environment.sdfgi_enabled = false
	environment.glow_enabled = true
	environment.volumetric_fog_enabled = false
	ProjectSettings.set_setting(
		"rendering/anti_aliasing/quality/msaa_3d", 1
	)


func set_graphics_high() -> void:
	graphics = Graphics.HIGH
	environment.sdfgi_enabled = true
	environment.glow_enabled = true
	environment.volumetric_fog_enabled = true
	ProjectSettings.set_setting(
		"rendering/anti_aliasing/quality/msaa_3d", 3
	)


func set_resolution_low() -> void:
	resolution = Resolution.LOW
	get_viewport().scaling_3d_scale = 0.25


func set_resolution_medium() -> void:
	resolution = Resolution.MEDIUM
	get_viewport().scaling_3d_scale = 0.50


func set_resolution_high() -> void:
	resolution = Resolution.HIGH
	get_viewport().scaling_3d_scale = 1.0


func decals_enabled() -> bool:
	return graphics > Global.Graphics.LOW


func _input(event: InputEvent) -> void:
	if  OS.is_debug_build() and event.is_action_pressed("debug_quit"):
		get_tree().quit()
