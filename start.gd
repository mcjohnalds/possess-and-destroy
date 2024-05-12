class_name Start
extends Node3D

const BUTTON_STYLE_BOXES = ["normal", "hover", "pressed", "disabled", "focus"]
@onready var unselected_style: StyleBox = (
	preload("res://button_style_box_unselected.tres")
)
@onready var camera_parent: Node3D = $CameraParent
@onready var start_button: Button = $UI/StartButton
@onready var graphics_low_button: Button = $UI/Graphics/LowButton
@onready var graphics_med_button: Button = $UI/Graphics/MedButton
@onready var graphics_high_button: Button = $UI/Graphics/HighButton
@onready var resolution_low_button: Button = $UI/Resolution/LowButton
@onready var resolution_med_button: Button = $UI/Resolution/MedButton
@onready var resolution_high_button: Button = $UI/Resolution/HighButton


func _process(_delta: float) -> void:
	camera_parent.rotation.y = (
		sin(Level.get_ticks_sec() * 0.17) * 0.002 * TAU
	)
	camera_parent.position.y = (
		sin(Level.get_ticks_sec() * 0.15) * 0.1
	)
	graphics_low_button.button_down.connect(func() -> void:
		global.set_graphics_low()
		update_buttons()
	)
	graphics_med_button.button_down.connect(func() -> void:
		global.set_graphics_medium()
		update_buttons()
	)
	graphics_high_button.button_down.connect(func() -> void:
		global.set_graphics_high()
		update_buttons()
	)
	resolution_low_button.button_down.connect(func() -> void:
		global.set_resolution_low()
		update_buttons()
	)
	resolution_med_button.button_down.connect(func() -> void:
		global.set_resolution_medium()
		update_buttons()
	)
	resolution_high_button.button_down.connect(func() -> void:
		global.set_resolution_high()
		update_buttons()
	)
	update_buttons()


func update_buttons() -> void:
	set_button_selected(
		graphics_low_button, global.graphics == Global.Graphics.LOW
	)
	set_button_selected(
		graphics_med_button, global.graphics == Global.Graphics.MEDIUM
	)
	set_button_selected(
		graphics_high_button, global.graphics == Global.Graphics.HIGH
	)
	set_button_selected(
		resolution_low_button, global.resolution == Global.Resolution.LOW
	)
	set_button_selected(
		resolution_med_button, global.resolution == Global.Resolution.MEDIUM
	)
	set_button_selected(
		resolution_high_button, global.resolution == Global.Resolution.HIGH
	)


func set_button_selected(button: Button, selected: bool) -> void:
	if selected:
		if button.has_theme_stylebox_override("normal"):
			for s: String in BUTTON_STYLE_BOXES:
				button.remove_theme_stylebox_override(s)
	else:
		for s: String in BUTTON_STYLE_BOXES:
			button.add_theme_stylebox_override(s, unselected_style)
