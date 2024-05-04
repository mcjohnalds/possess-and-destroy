class_name M16
extends Node3D

@onready var muzzle_flash := $MuzzleFlash as Node3D
@onready var muzzle_flash_particles := (
	$MuzzleFlash/GPUParticles3D as GPUParticles3D
)
