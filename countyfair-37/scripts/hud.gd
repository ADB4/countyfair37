class_name GameHud
extends CanvasLayer
## HUD: gameplay overlay (score, timer, crosshair, power bar, toast) plus
## three menu panels built in code: Main Menu, Pause, and Options.
##
## Purely presentational — the game manager pushes values in through public
## methods and reacts to the signals below. Menu navigation between Pause
## and Options is handled internally; only actions that affect game state
## (start, resume, return to main menu, FOV change) are emitted as signals.
##
## IMPORTANT: the full-rect Root control uses mouse_filter = IGNORE so
## clicks fall through to _unhandled_input (needed for click-to-start and
## pointer-lock recapture). The menu panels are added as siblings of Root
## directly on the CanvasLayer, with mouse_filter = STOP, so they capture
## clicks when visible.

## Emitted when the player presses "Play" on the main menu.
signal start_pressed
## Emitted when the player presses "Resume" on the pause menu.
signal resume_pressed
## Emitted when the player presses "Main Menu" on the pause menu.
signal main_menu_pressed
## Emitted when the FOV slider value changes.
signal fov_changed(value: float)

## Shows the target's current behavior state in the top-right corner.
## Handy while tuning; switch off for "release" builds.
@export var show_debug_state := true

@export_group("FOV")
@export var default_fov := 75.0
@export var min_fov := 50.0
@export var max_fov := 120.0

var _toast_tween: Tween

# --- Existing gameplay nodes (from hud.tscn) ---------------------------------

@onready var _root: Control = $Root
@onready var _score_label: Label = %ScoreLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _state_label: Label = %StateLabel
@onready var _power_bar: ProgressBar = %PowerBar
@onready var _message_label: Label = %MessageLabel
@onready var _toast_label: Label = %ToastLabel
@onready var _crosshair: Control = $Root/Crosshair

# --- Menu panels (built in _ready) -------------------------------------------

var _main_menu_panel: Control
var _pause_panel: Control
var _options_panel: Control
var _fov_slider: HSlider
var _fov_value_label: Label


func _ready() -> void:
	# Keep processing while the tree is paused so buttons and sliders work.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_power_bar.visible = false
	_toast_label.visible = false
	_state_label.visible = show_debug_state

	_build_main_menu_panel()
	_build_pause_panel()
	_build_options_panel()

	hide_all_menus()


# =============================================================================
#  GAMEPLAY HUD (public interface — called by the game manager)
# =============================================================================

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


## Toggle the in-game HUD elements (score, timer, crosshair, debug state).
## Power bar and message label are managed separately.
func set_gameplay_hud_visible(vis: bool) -> void:
	_score_label.visible = vis
	_timer_label.visible = vis
	_state_label.visible = vis and show_debug_state
	_crosshair.visible = vis


# =============================================================================
#  MENU VISIBILITY
# =============================================================================

func show_main_menu() -> void:
	hide_all_menus()
	set_gameplay_hud_visible(false)
	_main_menu_panel.visible = true


func show_pause_menu() -> void:
	hide_all_menus()
	_pause_panel.visible = true


func hide_all_menus() -> void:
	_main_menu_panel.visible = false
	_pause_panel.visible = false
	_options_panel.visible = false
	_message_label.visible = false


# =============================================================================
#  PANEL BUILDERS  (called once from _ready)
# =============================================================================

## ---- MAIN MENU --------------------------------------------------------------

func _build_main_menu_panel() -> void:
	_main_menu_panel = _make_full_rect_panel()
	add_child(_main_menu_panel)

	# Background
	var bg := _make_background(Color(0.06, 0.06, 0.10, 0.93))
	_main_menu_panel.add_child(bg)

	# Centered content column
	var vbox := _make_centered_vbox(420.0)
	_main_menu_panel.add_child(vbox)

	# Title
	var title := _make_label("COUNTYFAIR-37", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)

	vbox.add_child(_make_spacer(18.0))

	# Subtitle
	var subtitle := _make_label("~ Finest Pie-Throwing Booth at the Fair ~", 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	vbox.add_child(subtitle)

	vbox.add_child(_make_spacer(28.0))

	# Rules / context placeholder
	var rules_text := (
		"Step right up! Take aim at the target and let those pies fly.\n\n"
		+ "RULES\n"
		+ "  •  Score points by hitting the target with pies\n"
		+ "  •  Headshots: 25 pts  |  Body shots: 10 pts\n"
		+ "  •  Knock out the target for a 100 pt bonus\n"
		+ "  •  Watch out — the target gets craftier the more you throw\n"
		+ "  •  You have 60 seconds per round — make every pie count!\n\n"
		+ "[Placeholder — replace with final flavour text during art pass]"
	)
	var rules := _make_label(rules_text, 16)
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	rules.custom_minimum_size.x = 420.0
	vbox.add_child(rules)

	vbox.add_child(_make_spacer(32.0))

	# Play button
	var play_btn := _make_button("PLAY", 24)
	play_btn.pressed.connect(func() -> void: start_pressed.emit())
	vbox.add_child(play_btn)


## ---- PAUSE MENU -------------------------------------------------------------

func _build_pause_panel() -> void:
	_pause_panel = _make_full_rect_panel()
	add_child(_pause_panel)

	var bg := _make_background(Color(0.0, 0.0, 0.0, 0.72))
	_pause_panel.add_child(bg)

	var vbox := _make_centered_vbox(300.0)
	_pause_panel.add_child(vbox)

	var title := _make_label("PAUSED", 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)

	vbox.add_child(_make_spacer(28.0))

	var resume_btn := _make_button("Resume", 22)
	resume_btn.pressed.connect(func() -> void: resume_pressed.emit())
	vbox.add_child(resume_btn)

	vbox.add_child(_make_spacer(10.0))

	var options_btn := _make_button("Options", 22)
	options_btn.pressed.connect(_show_options)
	vbox.add_child(options_btn)

	vbox.add_child(_make_spacer(10.0))

	var menu_btn := _make_button("Main Menu", 22)
	menu_btn.pressed.connect(func() -> void: main_menu_pressed.emit())
	vbox.add_child(menu_btn)


## ---- OPTIONS PANEL ----------------------------------------------------------

func _build_options_panel() -> void:
	_options_panel = _make_full_rect_panel()
	add_child(_options_panel)

	var bg := _make_background(Color(0.06, 0.06, 0.10, 0.93))
	_options_panel.add_child(bg)

	var vbox := _make_centered_vbox(460.0)
	_options_panel.add_child(vbox)

	# Title
	var title := _make_label("OPTIONS", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)

	vbox.add_child(_make_spacer(30.0))

	# --- FOV slider ---
	var fov_header := _make_label("Field of View", 20)
	fov_header.add_theme_color_override("font_color", Color(0.9, 0.85, 0.65))
	vbox.add_child(fov_header)

	vbox.add_child(_make_spacer(8.0))

	var fov_row := HBoxContainer.new()
	fov_row.add_theme_constant_override("separation", 12)
	vbox.add_child(fov_row)

	var fov_min_lbl := _make_label(str(int(min_fov)), 14)
	fov_min_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	fov_row.add_child(fov_min_lbl)

	_fov_slider = HSlider.new()
	_fov_slider.min_value = min_fov
	_fov_slider.max_value = max_fov
	_fov_slider.step = 1.0
	_fov_slider.value = default_fov
	_fov_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fov_slider.custom_minimum_size.y = 24.0
	_fov_slider.value_changed.connect(_on_fov_slider_changed)
	fov_row.add_child(_fov_slider)

	var fov_max_lbl := _make_label(str(int(max_fov)), 14)
	fov_max_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	fov_row.add_child(fov_max_lbl)

	_fov_value_label = _make_label(str(int(default_fov)), 18)
	_fov_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_fov_value_label)

	vbox.add_child(_make_spacer(30.0))

	# --- Controls diagram ---
	var controls_header := _make_label("Controls", 20)
	controls_header.add_theme_color_override("font_color", Color(0.9, 0.85, 0.65))
	vbox.add_child(controls_header)

	vbox.add_child(_make_spacer(12.0))

	var diagram := _build_controls_diagram()
	vbox.add_child(diagram)

	vbox.add_child(_make_spacer(30.0))

	# Back button
	var back_btn := _make_button("Back", 20)
	back_btn.pressed.connect(_hide_options)
	vbox.add_child(back_btn)


## Builds a grid showing each control as a key-cap label + description.
func _build_controls_diagram() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)

	var bindings: Array[Array] = [
		["Mouse", "Look / Aim"],
		["LMB  Hold", "Charge Throw"],
		["LMB  Release", "Throw Pie"],
		["A  /  D", "Slide Left / Right"],
		["Esc", "Pause"],
		["R", "Restart Round"],
	]

	for row: Array in bindings:
		var key_lbl := _make_keycap_label(row[0])
		grid.add_child(key_lbl)

		var desc_lbl := _make_label(row[1], 16)
		desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
		grid.add_child(desc_lbl)

	return grid


# =============================================================================
#  INTERNAL NAVIGATION
# =============================================================================

func _show_options() -> void:
	_pause_panel.visible = false
	_options_panel.visible = true


func _hide_options() -> void:
	_options_panel.visible = false
	_pause_panel.visible = true


func _on_fov_slider_changed(value: float) -> void:
	_fov_value_label.text = str(int(value))
	fov_changed.emit(value)


# =============================================================================
#  UI FACTORY HELPERS
# =============================================================================

## A full-rect control that captures mouse events (used as a panel root).
func _make_full_rect_panel() -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel


## Full-rect semi-transparent backdrop.
func _make_background(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A VBoxContainer anchored to the center of its parent.
func _make_centered_vbox(width: float) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.custom_minimum_size.x = width
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	return vbox


func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _make_button(text: String, font_size: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = Vector2(260, 48)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Rounded, subtle style so it doesn't clash with any future theme.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.22, 0.22, 0.28)
	normal.border_color = Color(0.45, 0.45, 0.52)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.30, 0.30, 0.38)
	hover.border_color = Color(0.6, 0.6, 0.65)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.16, 0.16, 0.22)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	# Focused style matches hover so keyboard/gamepad nav looks right.
	var focus := hover.duplicate() as StyleBoxFlat
	btn.add_theme_stylebox_override("focus", focus)
	return btn


## Label styled to look like a keyboard key (rounded border, subtle depth).
func _make_keycap_label(text: String) -> Label:
	var label := Label.new()
	label.text = "  %s  " % text
	label.add_theme_font_size_override("font_size", 15)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(140, 32)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.24)
	style.border_color = Color(0.42, 0.42, 0.48)
	style.set_border_width_all(1)
	style.border_width_bottom = 3  # extra bottom border → key depth illusion
	style.set_corner_radius_all(5)
	style.set_content_margin_all(4)
	label.add_theme_stylebox_override("normal", style)
	return label