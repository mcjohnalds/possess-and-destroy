class_name M16
extends Node3D

var last_fired_at := -1000.0
var kick_velocity := Vector3.ZERO
var accuracy := 1.0
@onready var muzzle_flash := $MuzzleFlash as Node3D
@onready var muzzle_flash_particles := (
	$MuzzleFlash/GPUParticles3D as GPUParticles3D
)
@onready var mesh: MeshInstance3D = (
	find_children("*", "MeshInstance3D", true, false)[0]
)
@onready var gun_shot_audio_stream_player: AudioStreamPlayer3D = (
	$GunShotAudioStreamPlayer
)
