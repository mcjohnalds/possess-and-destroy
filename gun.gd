class_name Gun
extends Node3D

@export var gun_type: Level.GunType
var last_fired_at := -1000.0
var kick_velocity := Vector3.ZERO
var accuracy := 1.0
@onready var muzzle_flash := $MuzzleFlash as Node3D
@onready var muzzle_flash_particles := (
	$MuzzleFlash/GPUParticles3D as GPUParticles3D
)
@onready var model: Node3D = $Model
@onready var gun_shot_audio_stream_player: AudioStreamPlayer3D = (
	$GunShotAudioStreamPlayer
)
