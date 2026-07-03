class_name PieProjectile
extends RigidBody3D
## A thrown pie. Physically collides with the world only (layer setup:
## layer = projectile, mask = world). The target's hit zones are Area3Ds
## that detect the pie and call splat() themselves, so pies never bounce
## off the target's physics body.
##
## Web/perf notes: continuous_cd is enabled in the scene so fast pies don't
## tunnel through thin geometry, the splat uses CPUParticles3D (safe on the
## Compatibility renderer used by web exports), and every pie frees itself
## after `lifetime` seconds so they can't pile up in WASM memory.

signal splattered

@export var lifetime := 8.0
@export var spin := 7.0
@export var cleanup_delay := 2.0

## Set by the target the moment it scores this pie, so overlapping hit
## zones (head + body) can never double-count one pie.
var scored := false

var _splatted := false

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _particles: CPUParticles3D = $SplatParticles


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_expire)


## Called by the player controller right after spawning.
func launch(direction: Vector3, speed: float) -> void:
	linear_velocity = direction.normalized() * speed
	angular_velocity = Vector3(
			randf_range(-spin, spin),
			randf_range(-spin, spin),
			randf_range(-spin, spin))


func is_splatted() -> bool:
	return _splatted


func _on_body_entered(_body: Node) -> void:
	splat()


## Freeze in place, flatten, burst particles, then clean up. Safe to call
## from physics callbacks (Area3D/body signals): the physics state change
## is deferred.
func splat() -> void:
	if _splatted:
		return
	_splatted = true
	splattered.emit()
	set_deferred("freeze", true)
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3(1.5, 0.3, 1.5), 0.08)
	_particles.emitting = true
	get_tree().create_timer(cleanup_delay).timeout.connect(queue_free)


func _expire() -> void:
	if not _splatted:
		queue_free()
