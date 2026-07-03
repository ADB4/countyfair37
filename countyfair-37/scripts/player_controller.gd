class_name PlayerController
extends Node3D
## First-person booth controller: captured-mouse look, sliding left/right
## along the counter (X axis), and a hold-to-charge / release-to-throw pie.
##
## Scene contract (see main.tscn):
##   PlayerController (this script)
##   └── Camera3D            - pitch lives here; yaw lives on the root
##       └── SpawnPoint      - Marker3D where pies appear (offset like a
##                             pie held slightly right and below the eyes)

signal charge_started
signal charge_updated(ratio: float)
signal charge_released
signal pie_thrown(pie: PieProjectile)

@export var pie_scene: PackedScene
## Node thrown pies get parented to (keeps the tree tidy and makes it easy
## to count or clear live projectiles later).
@export var projectile_parent: Node3D

@export_group("Movement")
@export var move_speed := 3.0
@export var min_x := -3.2
@export var max_x := 3.2

@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var yaw_limit_deg := 75.0
@export var pitch_min_deg := -50.0
@export var pitch_max_deg := 40.0

@export_group("Throw")
@export var min_throw_speed := 9.0
@export var max_throw_speed := 24.0
@export var full_charge_time := 1.1
@export var throw_cooldown := 0.25

## Toggled by the game manager. While false, gameplay input is ignored.
var active := false:
	set(value):
		active = value
		if not value:
			_cancel_charge()

var _yaw := 0.0
var _pitch := 0.0
var _charging := false
var _charge_time := 0.0
var _cooldown_left := 0.0

@onready var _camera: Camera3D = $Camera3D
@onready var _spawn_point: Marker3D = $Camera3D/SpawnPoint


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw = clampf(_yaw - event.relative.x * mouse_sensitivity,
				-deg_to_rad(yaw_limit_deg), deg_to_rad(yaw_limit_deg))
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity,
				deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		rotation.y = _yaw
		_camera.rotation.x = _pitch
		return
	# NOTE (web export): browsers only grant pointer lock inside an input
	# callback, so re-capturing after the user pressed Esc must happen here,
	# not from _process polling.
	if active and event.is_action_pressed("throw") \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()
		_cooldown_left = 0.2  # don't let the re-capture click start a charge


func _process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not active:
		return
	_handle_movement(delta)
	_handle_throw(delta)


func _handle_movement(delta: float) -> void:
	var axis := Input.get_axis("move_left", "move_right")
	position.x = clampf(position.x + axis * move_speed * delta, min_x, max_x)


func _handle_throw(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_cancel_charge()  # pointer lock lost mid-charge (Esc in the browser)
		return
	if _charging:
		_charge_time = minf(_charge_time + delta, full_charge_time)
		charge_updated.emit(_charge_time / full_charge_time)
		if Input.is_action_just_released("throw"):
			_throw()
	elif Input.is_action_just_pressed("throw") and _cooldown_left <= 0.0:
		_charging = true
		_charge_time = 0.0
		charge_started.emit()
		charge_updated.emit(0.0)


func _throw() -> void:
	_charging = false
	_cooldown_left = throw_cooldown
	charge_released.emit()
	var ratio := _charge_time / full_charge_time
	var speed := lerpf(min_throw_speed, max_throw_speed, ratio)
	var pie: PieProjectile = pie_scene.instantiate()
	projectile_parent.add_child(pie)
	pie.global_transform = _spawn_point.global_transform
	pie.launch(-_camera.global_transform.basis.z, speed)
	pie_thrown.emit(pie)


func _cancel_charge() -> void:
	if _charging:
		_charging = false
		charge_released.emit()


## Called by the game manager when a round begins. The short cooldown stops
## the click that started the round from doubling as a throw charge.
func reset_for_round() -> void:
	_cancel_charge()
	_cooldown_left = 0.3


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
