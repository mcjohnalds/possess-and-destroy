class_name Player
extends FPSController3D

var last_known_position: Vector3
var last_seen_at := -10000.0
var last_possessed_at := -10000.0
var invisible := false
var initial_health := 5.0
var health := initial_health
var gun: Gun
var initial_energy := 9.5
var energy := initial_energy
@onready var gun_transform: Node3D = $Head/GunTransform
@onready var camera: Camera3D = $Head/FirstPersonCameraReference/Camera3D
@onready var m_16_audio_stream_player := (
	$M16AudioStreamPlayer as AudioStreamPlayer
)
@onready var sniper_rifle_audio_stream_player := (
	$SniperRifleAudioStreamPlayer as AudioStreamPlayer
)
@onready var shotgun_audio_stream_player := (
	$ShotgunAudioStreamPlayer as AudioStreamPlayer
)
@onready var invisibility_audio_stream_player := (
	$InvisibilityAudioStreamPlayer as AudioStreamPlayer
)
@onready var hitmarker_audio_stream_player := (
	$HitmarkerAudioStreamPlayer as AudioStreamPlayer
)
@onready var headshot_audio_stream_player := (
	$HeadshotAudioStreamPlayer as AudioStreamPlayer
)
@onready var possession_audio_stream_player := (
	$PossessionAudioStreamPlayer as AudioStreamPlayer
)
@onready var damage_audio_stream_player := (
	$DamageAudioStreamPlayer as AudioStreamPlayer
)
@onready var crosshair := $HUD/Crosshair as Control
@onready var invisibility_overlay: Control = $HUD/InvisibilityOverlay
@onready var vignette: TextureRect = $HUD/Vignette
@onready var use_label: Label = $HUD/UseLabel
@onready var possessing_label: Label = $HUD/PossessingLabel
@onready var vignette_gradient_2d: GradientTexture2D = vignette.texture
@onready var vignette_gradient: Gradient = (
	vignette_gradient_2d.gradient
)
@onready var messages := $HUD/Messages as Control
@onready var health_label := $HUD/HealthLabel as Label
@onready var energy_label := $HUD/EnergyLabel as Label
@onready var compromised_control := $HUD/Compromised as Control
@onready var capsule: CapsuleShape3D = ($Collision as CollisionShape3D).shape
