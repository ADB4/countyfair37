class_name TargetCharacter
extends CharacterBody3D
## The pie target: health, a behavior state machine, dodge logic, and an
## animation abstraction layer that drives either a real AnimationTree (once
## the rigged model exists) or placeholder procedural motion (greybox).
##
## SWAPPING IN THE REAL CHARACTER
## ------------------------------
## 1. Replace Pivot/BodyMesh and Pivot/HeadMesh with the imported GLTF scene
##    (drop it under Pivot).
## 2. Add an AnimationTree (anywhere under this node) whose tree_root is an
##    AnimationNodeStateMachine with states named exactly:
##        idle, walk, duck, cower, hit
##    Inside the state machine, give hit/duck/cower transitions back to idle
##    with "switch at end + auto advance" so they return to idle on their own.
## 3. Re-fit the HitZoneHead / HitZoneBody collision shapes to the new
##    silhouette.
## Nothing else changes — this script auto-detects the AnimationTree and
## stops using the placeholder tweens.
##
## BEHAVIOR MODEL
## --------------
## Alertness (IDLE -> CAUTIOUS -> ACTIVE) escalates as pies fly at the
## target. Damage states (SOILED, LOW_HEALTH) are driven by health ratio and
## override alertness. Ducking disables the head hit zone for its duration,
## so a well-timed duck makes face shots sail over and splat on the backdrop.

signal hit(points: int, zone: String)
signal defeated
signal behavior_changed(behavior: int)

enum MovementMode { STATIONARY, PATH }
enum Behavior { IDLE, CAUTIOUS, ACTIVE, SOILED, LOW_HEALTH }

# Canonical animation state names (see header).
const ANIM_IDLE := "idle"
const ANIM_WALK := "walk"
const ANIM_DUCK := "duck"
const ANIM_COWER := "cower"
const ANIM_HIT := "hit"

# Per-behavior tuning:
#   speed    - patrol speed in m/s (PATH mode only)
#   dodge    - chance to react to an incoming pie
#   sidestep - of those dodges, chance to sidestep instead of duck
#              (sidesteps only happen in PATH mode)
#   pause    - chance to linger for a moment at each patrol point
const BEHAVIOR_PARAMS := {
	Behavior.IDLE: { "speed": 0.0, "dodge": 0.0, "sidestep": 0.0, "pause": 1.0 },
	Behavior.CAUTIOUS: { "speed": 1.2, "dodge": 0.65, "sidestep": 0.3, "pause": 0.5 },
	Behavior.ACTIVE: { "speed": 2.6, "dodge": 0.8, "sidestep": 0.6, "pause": 0.1 },
	Behavior.SOILED: { "speed": 1.6, "dodge": 0.45, "sidestep": 0.4, "pause": 0.35 },
	Behavior.LOW_HEALTH: { "speed": 0.7, "dodge": 0.2, "sidestep": 0.1, "pause": 0.7 },
}

const SPLAT_COLOR := Color(0.93, 0.86, 0.7)

@export_group("Setup")
@export var movement_mode := MovementMode.PATH
## Starting alertness. Use IDLE, CAUTIOUS or ACTIVE here — SOILED and
## LOW_HEALTH are reached through damage, not configuration.
@export var initial_behavior := Behavior.IDLE
@export var path_min_x := -3.5
@export var path_max_x := 3.5

@export_group("Health")
@export var max_health := 100.0
@export_range(0.0, 1.0) var soiled_below := 0.6
@export_range(0.0, 1.0) var low_health_below := 0.3
@export var head_damage := 15.0
@export var body_damage := 10.0
@export var head_points := 25
@export var body_points := 10
@export var defeat_bonus := 100
@export var respawn_delay := 2.5

@export_group("Alertness")
## How many pies must come flying before an IDLE target wises up.
@export var pies_to_go_cautious := 1
@export var pies_to_go_active := 4

@export_group("Dodging")
@export var dodge_cooldown := 1.1
@export var duck_duration := 0.6
@export var sidestep_speed := 6.0
@export var sidestep_duration := 0.35

var health := 100.0

var _behavior: int = -1
var _alert_level := 0  # 0 IDLE, 1 CAUTIOUS, 2 ACTIVE (damage states override)
var _pies_seen := 0
var _dodge_ready := true
var _ducking := false
var _is_defeated := false
var _sidestep_time_left := 0.0
var _sidestep_dir := 1.0
var _pause_time_left := 0.0
var _patrol_target_x := 0.0
var _locomotion_anim := ""
var _action_lock := 0.0  # while > 0, locomotion won't override action anims

# Animation backends. Exactly one path is used per _play_anim call:
# AnimationTree state machine > AnimationPlayer > placeholder tweens.
var _anim_state_machine: AnimationNodeStateMachine
var _anim_playback: AnimationNodeStateMachinePlayback
var _anim_player: AnimationPlayer
var _placeholder_tween: Tween
var _placeholder_time := 0.0

# Grime: the body material gets progressively pie-colored as health drops.
var _body_mat: StandardMaterial3D
var _base_body_color := Color.WHITE
var _body_mesh_base_y := 0.0

@onready var _pivot: Node3D = $Pivot
@onready var _body_mesh: MeshInstance3D = get_node_or_null("Pivot/BodyMesh")
@onready var _hit_zone_head: Area3D = $Pivot/HitZoneHead
@onready var _hit_zone_body: Area3D = $Pivot/HitZoneBody
@onready var _dodge_sensor: Area3D = $DodgeSensor


func _ready() -> void:
	_hit_zone_head.body_entered.connect(_on_hit_zone_body_entered.bind("head"))
	_hit_zone_body.body_entered.connect(_on_hit_zone_body_entered.bind("body"))
	_dodge_sensor.body_entered.connect(_on_dodge_sensor_body_entered)
	_detect_animation_backend()
	_setup_grime_material()
	if _body_mesh != null:
		_body_mesh_base_y = _body_mesh.position.y
	reset()


## Full reset: health, alertness, pose, zones. Called on round start and
## after the post-knockout respawn delay.
func reset() -> void:
	health = max_health
	_is_defeated = false
	_pies_seen = 0
	_alert_level = clampi(initial_behavior, Behavior.IDLE, Behavior.ACTIVE)
	_dodge_ready = true
	_ducking = false
	_sidestep_time_left = 0.0
	_pause_time_left = 0.0
	_action_lock = 0.0
	_locomotion_anim = ""
	_patrol_target_x = path_max_x
	if _placeholder_tween:
		_placeholder_tween.kill()
	_pivot.scale = Vector3.ONE
	_pivot.rotation = Vector3.ZERO
	_set_zones_enabled(true)
	_update_grime()
	_behavior = -1
	_resolve_behavior()
	_play_anim(ANIM_IDLE)


func _physics_process(delta: float) -> void:
	_action_lock = maxf(_action_lock - delta, 0.0)
	if _is_defeated:
		velocity = Vector3.ZERO
		return
	var vx := 0.0
	if _sidestep_time_left > 0.0:
		_sidestep_time_left -= delta
		vx = _sidestep_dir * sidestep_speed
	elif movement_mode == MovementMode.PATH and not _ducking:
		vx = _patrol(delta)
	velocity = Vector3(vx, 0.0, 0.0)
	move_and_slide()
	global_position.x = clampf(global_position.x, path_min_x, path_max_x)
	_update_locomotion_anim()


func _process(delta: float) -> void:
	_placeholder_time += delta
	_process_placeholder_locomotion()


# --- Behavior state machine -------------------------------------------------

## Recomputes the current behavior. Health-driven states (LOW_HEALTH,
## SOILED) always win; otherwise the alertness ladder decides.
func _resolve_behavior() -> void:
	var ratio := health / max_health
	var next: int
	if ratio <= low_health_below:
		next = Behavior.LOW_HEALTH
	elif ratio <= soiled_below:
		next = Behavior.SOILED
	else:
		next = _alert_level  # 0..2 maps directly onto IDLE/CAUTIOUS/ACTIVE
	if next != _behavior:
		_behavior = next
		behavior_changed.emit(_behavior)


func _param(key: String) -> float:
	return BEHAVIOR_PARAMS[_behavior][key]


func _update_alertness() -> void:
	var new_level := _alert_level
	if _pies_seen >= pies_to_go_active:
		new_level = 2
	elif _pies_seen >= pies_to_go_cautious:
		new_level = maxi(new_level, 1)
	if new_level != _alert_level:
		_alert_level = new_level
		_resolve_behavior()


# --- Patrol movement ---------------------------------------------------------

func _patrol(delta: float) -> float:
	var speed := _param("speed")
	if speed <= 0.0:
		return 0.0
	if _pause_time_left > 0.0:
		_pause_time_left -= delta
		return 0.0
	var to_target := _patrol_target_x - global_position.x
	if absf(to_target) < 0.1:
		_pick_next_patrol_point()
		return 0.0
	return signf(to_target) * speed


func _pick_next_patrol_point() -> void:
	var mid := (path_min_x + path_max_x) * 0.5
	_patrol_target_x = path_min_x if global_position.x > mid else path_max_x
	# Occasionally aim for a random midpoint so the movement is less metronomic.
	if randf() < 0.35:
		_patrol_target_x = randf_range(path_min_x, path_max_x)
	if randf() < _param("pause"):
		_pause_time_left = randf_range(0.5, 1.4)


# --- Dodging -----------------------------------------------------------------

func _on_dodge_sensor_body_entered(body: Node3D) -> void:
	if _is_defeated or not (body is PieProjectile):
		return
	var pie := body as PieProjectile
	if pie.is_splatted():
		return
	_pies_seen += 1
	_update_alertness()
	_try_dodge()


func _try_dodge() -> void:
	if not _dodge_ready or _ducking:
		return
	if randf() > _param("dodge"):
		return
	_dodge_ready = false
	get_tree().create_timer(dodge_cooldown).timeout.connect(
			func() -> void: _dodge_ready = true)
	var can_sidestep := movement_mode == MovementMode.PATH
	if can_sidestep and randf() < _param("sidestep"):
		_sidestep()
	else:
		_duck()


func _sidestep() -> void:
	# Step toward whichever side has more room, so the target never pins
	# itself against the edge of its path.
	var margin := 1.0
	var room_left := global_position.x - (path_min_x + margin)
	var room_right := (path_max_x - margin) - global_position.x
	_sidestep_dir = 1.0 if room_right > room_left else -1.0
	_sidestep_time_left = sidestep_duration
	# No explicit anim: the burst of velocity makes locomotion pick "walk".


## Ducking protects the face: the head hit zone switches off for the
## duration, so pies aimed at it fly over and splat on the backdrop. This is
## deliberately decoupled from the visuals — it works identically whether
## the duck is shown by the placeholder squash or a real rig animation.
func _duck() -> void:
	_ducking = true
	_set_head_zone_enabled(false)
	_play_action_anim(ANIM_DUCK, duck_duration)
	get_tree().create_timer(duck_duration).timeout.connect(_end_duck)


func _end_duck() -> void:
	_ducking = false
	if not _is_defeated:
		_set_head_zone_enabled(true)


# --- Getting hit -------------------------------------------------------------

func _on_hit_zone_body_entered(body: Node3D, zone: String) -> void:
	if _is_defeated or not (body is PieProjectile):
		return
	var pie := body as PieProjectile
	if pie.scored or pie.is_splatted():
		return
	pie.scored = true  # head + body zones overlap slightly; first one wins
	pie.splat()
	health = maxf(health - (head_damage if zone == "head" else body_damage), 0.0)
	hit.emit(head_points if zone == "head" else body_points, zone)
	_update_grime()
	_flash()
	if health <= 0.0:
		_defeat()
	else:
		_play_action_anim(ANIM_HIT, 0.4)
		_resolve_behavior()


func _defeat() -> void:
	_is_defeated = true
	_set_zones_enabled(false)
	_play_action_anim(ANIM_COWER, respawn_delay)
	defeated.emit()
	get_tree().create_timer(respawn_delay).timeout.connect(reset)


func _set_zones_enabled(enabled: bool) -> void:
	_hit_zone_body.set_deferred("monitoring", enabled)
	_set_head_zone_enabled(enabled)


func _set_head_zone_enabled(enabled: bool) -> void:
	_hit_zone_head.set_deferred("monitoring", enabled)


# --- Hit feedback (flash + grime) -------------------------------------------

func _setup_grime_material() -> void:
	if _body_mesh == null:
		return
	var source := _body_mesh.get_active_material(0)
	if source is StandardMaterial3D:
		# Duplicate so we never tint the shared resource inside the scene file.
		_body_mat = source.duplicate()
		_body_mesh.material_override = _body_mat
		_base_body_color = _body_mat.albedo_color


func _update_grime() -> void:
	if _body_mat == null:
		return
	var mess := 1.0 - health / max_health
	_body_mat.albedo_color = _base_body_color.lerp(SPLAT_COLOR, mess * 0.85)


func _flash() -> void:
	if _body_mat == null:
		return
	var restore_to := _body_mat.albedo_color
	_body_mat.albedo_color = Color(1, 1, 1)
	var flash_tween := create_tween()
	flash_tween.tween_property(_body_mat, "albedo_color", restore_to, 0.25)


# --- Animation abstraction layer ---------------------------------------------

func _detect_animation_backend() -> void:
	var trees := find_children("*", "AnimationTree", true, false)
	if not trees.is_empty():
		var tree: AnimationTree = trees[0]
		if tree.tree_root is AnimationNodeStateMachine:
			_anim_state_machine = tree.tree_root
			_anim_playback = tree.get("parameters/playback")
			tree.active = true
			return
	var players := find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim_player = players[0]


## Single entry point for all animation. Prefers the AnimationTree state
## machine, falls back to a plain AnimationPlayer, and finally to procedural
## placeholder tweens on the greybox capsule.
func _play_anim(anim_name: String) -> void:
	if _anim_playback != null and _anim_state_machine.has_node(anim_name):
		_anim_playback.travel(anim_name)
	elif _anim_player != null and _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
	else:
		_play_placeholder(anim_name)


## Action anims (hit/duck/cower) lock locomotion out for `lock_time` so the
## very next frame doesn't immediately travel back to idle/walk.
func _play_action_anim(anim_name: String, lock_time: float) -> void:
	_action_lock = lock_time
	_locomotion_anim = ""  # force locomotion to re-assert once the lock ends
	_play_anim(anim_name)


func _update_locomotion_anim() -> void:
	if _is_defeated or _ducking or _action_lock > 0.0:
		return
	var next := ANIM_WALK if absf(velocity.x) > 0.1 else ANIM_IDLE
	if next != _locomotion_anim:
		_locomotion_anim = next
		_play_anim(next)


# --- Placeholder (greybox) animation ------------------------------------------

func _play_placeholder(anim_name: String) -> void:
	if _placeholder_tween:
		_placeholder_tween.kill()
	# Start each action from a clean pose.
	_pivot.scale = Vector3.ONE
	_pivot.rotation.x = 0.0
	match anim_name:
		ANIM_DUCK:
			_placeholder_tween = create_tween()
			_placeholder_tween.tween_property(_pivot, "scale:y", 0.45, 0.1)
			_placeholder_tween.tween_interval(maxf(duck_duration - 0.3, 0.05))
			_placeholder_tween.tween_property(_pivot, "scale:y", 1.0, 0.2)
		ANIM_HIT:
			_placeholder_tween = create_tween()
			_placeholder_tween.tween_property(
					_pivot, "scale", Vector3(1.18, 0.82, 1.18), 0.06)
			_placeholder_tween.tween_property(_pivot, "scale", Vector3.ONE, 0.22)
		ANIM_COWER:
			_placeholder_tween = create_tween().set_parallel(true)
			_placeholder_tween.tween_property(
					_pivot, "scale", Vector3(0.9, 0.55, 0.9), 0.18)
			_placeholder_tween.tween_property(_pivot, "rotation:x", 0.5, 0.18)
		_:
			pass  # idle / walk are handled continuously below


## Gentle bob + rock on the capsule so the greybox doesn't feel dead. Does
## nothing once a real animation backend is detected.
func _process_placeholder_locomotion() -> void:
	if _anim_playback != null or _anim_player != null:
		return
	if _body_mesh == null or _is_defeated or _ducking or _action_lock > 0.0:
		return
	var t := _placeholder_time
	if absf(velocity.x) > 0.1:
		_body_mesh.position.y = _body_mesh_base_y + absf(sin(t * 9.0)) * 0.05
		_pivot.rotation.z = sin(t * 9.0) * 0.06
	else:
		_body_mesh.position.y = _body_mesh_base_y + sin(t * 2.2) * 0.02
		_pivot.rotation.z = lerpf(_pivot.rotation.z, 0.0, 0.2)
