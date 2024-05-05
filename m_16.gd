class_name M16
extends Node3D

var last_fired_at := -1000.0
var kick_velocity := Vector3.ZERO
var accuracy := 1.0
@onready var muzzle_flash := $MuzzleFlash as Node3D
@onready var muzzle_flash_particles := (
	$MuzzleFlash/GPUParticles3D as GPUParticles3D
)
