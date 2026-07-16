extends Node3D
## Game manager for CountyFair-37.
##
## Owns the round loop (MAIN_MENU -> PLAYING -> PAUSED / ROUND_OVER), the
## score, and the round timer. The player, target, and HUD only talk to each
## other through signals wired up here, so each piece stays independently
## swappable.
##
## PAUSE / WEB-EXPORT NOTE
## -----------------------
## Pausing uses get_tree().paused so physics, projectiles and the target all
## freeze. Main and HUD set process_mode = ALWAYS so they can still handle
## input and draw menus while paused. The auto-pause in _process catches the
## case where the browser silently releases pointer lock on Esc (the key
## event never reaches Godot, but the mode change does).

enum GameState { MAIN_MENU, PLAYING, PAUSED, ROUND_OVER }

@export var round_length := 60.0

var _state := GameState.MAIN_MENU
var _score := 0
var _time_left := 0.0

@onready var _player: PlayerController = %PlayerController
@onready var _target: TargetCharacter = %TargetCharacter
@onready var _hud: GameHud = %HUD
@onready var _projectile_manager: Node3D = $ProjectileManager


func _ready() -> void:
	# Keep processing while the tree is paused so we can handle menus.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Gameplay signals (unchanged from Phase 2).
	_target.hit.connect(_on_target_hit)
	_target.defeated.connect(_on_target_defeated)
	_target.behavior_changed.connect(_on_target_behavior_changed)
	_player.charge_started.connect(_hud.show_charge)
	_player.charge_updated.connect(_hud.set_charge)
	_player.charge_released.connect(_hud.hide_charge)

	# Menu signals from HUD.
	_hud.start_pressed.connect(_start_round)
	_hud.resume_pressed.connect(_resume_game)
	_hud.main_menu_pressed.connect(_go_to_main_menu)
	_hud.fov_changed.connect(_on_fov_changed)

	# Initial state.
	_hud.set_score(0)
	_hud.set_time(round_length)
	_hud.show_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	# R to restart works from any non-menu state.
	if event.is_action_pressed("restart"):
		if _state == GameState.PAUSED:
			get_tree().paused = false
		_start_round()
		return

	# Esc toggles pause (on desktop; in browser the auto-pause in _process
	# handles the Esc-releases-pointer-lock case).
	if event.is_action_pressed("pause"):
		if _state == GameState.PLAYING:
			_pause_game()
			return
		elif _state == GameState.PAUSED:
			_resume_game()
			return

	# Click to replay after round over.
	if _state == GameState.ROUND_OVER:
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_round()


func _process(delta: float) -> void:
	# Auto-pause when pointer lock is lost during gameplay. In browsers Esc
	# releases the pointer lock without the key event reaching Godot, so this
	# is the reliable detection path for web.
	if _state == GameState.PLAYING \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_pause_game()
		return

	if _state != GameState.PLAYING:
		return

	_time_left -= delta
	_hud.set_time(maxf(_time_left, 0.0))
	if _time_left <= 0.0:
		_end_round()


# --- State transitions -------------------------------------------------------

func _start_round() -> void:
	get_tree().paused = false
	_state = GameState.PLAYING
	_score = 0
	_time_left = round_length
	_hud.set_score(_score)
	_hud.set_time(_time_left)
	_hud.hide_all_menus()
	_hud.set_gameplay_hud_visible(true)
	_clear_projectiles()
	_target.reset()
	_player.reset_for_round()
	_player.active = true
	# NOTE (web export): capture_mouse is called from _ready context here,
	# but _start_round itself is always invoked from an input callback
	# (button press or _unhandled_input), so the browser will grant pointer
	# lock.
	_player.capture_mouse()


func _pause_game() -> void:
	_state = GameState.PAUSED
	_player.active = false
	_player.release_mouse()
	_hud.hide_charge()
	get_tree().paused = true
	_hud.show_pause_menu()


func _resume_game() -> void:
	_hud.hide_all_menus()
	get_tree().paused = false
	_state = GameState.PLAYING
	_player.active = true
	# Re-capture happens inside this button click callback → browser allows
	# pointer lock.
	_player.capture_mouse()


func _go_to_main_menu() -> void:
	get_tree().paused = false
	_state = GameState.MAIN_MENU
	_score = 0
	_player.active = false
	_player.release_mouse()
	_hud.hide_charge()
	_hud.set_gameplay_hud_visible(false)
	_clear_projectiles()
	_target.reset()
	_hud.show_main_menu()


func _end_round() -> void:
	_state = GameState.ROUND_OVER
	_player.active = false
	_player.release_mouse()
	_hud.hide_charge()
	_hud.hide_all_menus()
	_hud.show_message("ROUND OVER\nFINAL SCORE: %d\n\nClick to play again" % _score)


func _clear_projectiles() -> void:
	for child in _projectile_manager.get_children():
		child.queue_free()


# --- Signal callbacks --------------------------------------------------------

func _on_target_hit(points: int, zone: String) -> void:
	if _state != GameState.PLAYING:
		return
	_score += points
	_hud.set_score(_score)
	var suffix := "  IN THE FACE!" if zone == "head" else ""
	_hud.show_toast("+%d%s" % [points, suffix])


func _on_target_defeated() -> void:
	if _state != GameState.PLAYING:
		return
	_score += _target.defeat_bonus
	_hud.set_score(_score)
	_hud.show_toast("KNOCKOUT!  +%d" % _target.defeat_bonus)


func _on_target_behavior_changed(behavior: int) -> void:
	_hud.set_debug_state(TargetCharacter.Behavior.keys()[behavior])


func _on_fov_changed(value: float) -> void:
	_player.camera_fov = value