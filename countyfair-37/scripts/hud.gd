class_name GameHud
extends CanvasLayer
## HUD: score, round timer, crosshair, throw power bar, center messages, and
## a small score toast. Purely presentational — the game manager pushes
## values in through the methods below, the HUD never reaches into gameplay.
##
## IMPORTANT: the full-rect Root control uses mouse_filter = IGNORE so
## clicks fall through to _unhandled_input (needed for click-to-start and
## pointer-lock recapture).

## Shows the target's current behavior state in the top-right corner.
## Handy while tuning; switch off for "release" builds.
@export var show_debug_state := true

var _toast_tween: Tween

@onready var _score_label: Label = %ScoreLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _state_label: Label = %StateLabel
@onready var _power_bar: ProgressBar = %PowerBar
@onready var _message_label: Label = %MessageLabel
@onready var _toast_label: Label = %ToastLabel


func _ready() -> void:
	_power_bar.visible = false
	_toast_label.visible = false
	_state_label.visible = show_debug_state


func set_score(value: int) -> void:
	_score_label.text = "SCORE: %d" % value


func set_time(seconds: float) -> void:
	var total := ceili(seconds)
	_timer_label.text = "%d:%02d" % [int(total / 60.0), total % 60]


func set_debug_state(state_name: String) -> void:
	_state_label.text = "TARGET: %s" % state_name


func show_charge() -> void:
	_power_bar.value = 0.0
	_power_bar.visible = true


func set_charge(ratio: float) -> void:
	_power_bar.value = ratio


func hide_charge() -> void:
	_power_bar.visible = false


func show_message(text: String) -> void:
	_message_label.text = text
	_message_label.visible = true


func hide_message() -> void:
	_message_label.visible = false


## Brief fading feedback like "+25  IN THE FACE!". A new toast replaces any
## toast still on screen.
func show_toast(text: String) -> void:
	if _toast_tween:
		_toast_tween.kill()
	_toast_label.text = text
	_toast_label.visible = true
	_toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.9).set_delay(0.25)
