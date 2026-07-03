extends Node3D
## Game manager for CountyFair-37.
##
## Owns the round loop (READY -> PLAYING -> ROUND_OVER), the score, and the
## round timer. The player, target, and HUD only talk to each other through
## signals wired up here, so each piece stays independently swappable.

enum GameState { READY, PLAYING, ROUND_OVER }

@export var round_length := 60.0

var _state := GameState.READY
var _score := 0
var _time_left := 0.0

@onready var _player: PlayerController = %PlayerController
@onready var _target: TargetCharacter = %TargetCharacter
@onready var _hud: GameHud = %HUD


func _ready() -> void:
	_target.hit.connect(_on_target_hit)
	_target.defeated.connect(_on_target_defeated)
	_target.behavior_changed.connect(_on_target_behavior_changed)
	_player.charge_started.connect(_hud.show_charge)
	_player.charge_updated.connect(_hud.set_charge)
	_player.charge_released.connect(_hud.hide_charge)
	_hud.set_score(0)
	_hud.set_time(round_length)
	_hud.show_message(
			"COUNTYFAIR-37\n\nClick to start\nMouse: aim    A/D: slide    Hold LMB: charge, release: throw")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_start_round()
		return
	if _state == GameState.PLAYING:
		return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# NOTE (web export): browsers only grant pointer lock from inside an
		# input callback, which is why the round starts (and the mouse gets
		# captured) here rather than from _process polling.
		_start_round()


func _process(delta: float) -> void:
	if _state != GameState.PLAYING:
		return
	_time_left -= delta
	_hud.set_time(maxf(_time_left, 0.0))
	if _time_left <= 0.0:
		_end_round()


func _start_round() -> void:
	_state = GameState.PLAYING
	_score = 0
	_time_left = round_length
	_hud.set_score(_score)
	_hud.set_time(_time_left)
	_hud.hide_message()
	_target.reset()
	_player.reset_for_round()
	_player.active = true
	_player.capture_mouse()


func _end_round() -> void:
	_state = GameState.ROUND_OVER
	_player.active = false
	_player.release_mouse()
	_hud.hide_charge()
	_hud.show_message("ROUND OVER\nFINAL SCORE: %d\n\nClick to play again" % _score)


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
