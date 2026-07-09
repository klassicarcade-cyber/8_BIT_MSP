# res://core/game_select.gd
extends Control

# -------------------------
# GameDef paths (order matters)
# TL = Gobles, TR = Paw Paw, BL = Mars, BR = Fizz
# -------------------------
const GOBLES_DEF := "res://series/gob/gobles_game.tres"
const PAWPAW_DEF := "res://series/paw/pawpaw_game.tres"
const MARS_DEF   := "res://series/mars/mars_game.tres"
const FIZZ_DEF   := "res://series/fizz/fizz_game.tres"

const GAMEPLAY_SCENE         := "res://core/scenes/gameplay_root.tscn"
const HIGHSCORE_VIEWER_SCENE := "res://core/ui/high_score_viewer.tscn"
const SCREENSAVER_META_KEY   := "show_screensaver_on_ready"

const VERSION := "26.7.1"

@export var free_play: bool = false

const SETTINGS_PATH    := "user://operator_settings.cfg"
const SETTINGS_SECTION := "operator"
const SETTINGS_KEY_FREE_PLAY := "free_play"

@onready var grid: GridContainer  = $Grid
@onready var slot_tl: Control     = $Grid/Slot_TL
@onready var slot_tr: Control     = $Grid/Slot_TR
@onready var slot_bl: Control     = $Grid/Slot_BL
@onready var slot_br: Control     = $Grid/Slot_BR
@onready var version_label: Label = $VersionLabel
@onready var mode_label: Label    = $ModeLabel

var _slots: Array[Control] = []
var _defs: Array[String]   = []
var _selected := 0

const HIGHLIGHT_COLOR := Color(1.0, 0.9, 0.1, 1.0)
const DIM_COLOR       := Color(1.0, 1.0, 1.0, 0.70)

const COINS_NEEDED := 2
var _coins: int = 0

@export var screensaver_seconds: float = 90.0
@export var screensaver_scene_path: String = "res://core/scenes/screensaver_overlay.tscn"

var _idle_time: float    = 0.0
var _saver: Node         = null
var _saver_visible: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode   = Control.FOCUS_ALL
	grab_focus()

	_slots = [slot_tl, slot_tr, slot_bl, slot_br]
	_defs  = [GOBLES_DEF, PAWPAW_DEF, MARS_DEF, FIZZ_DEF]

	grid.columns = 2

	for s in _slots:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical   = Control.SIZE_EXPAND_FILL

		var img := s.get_node_or_null("Image")
		if img and img is TextureRect:
			var t := img as TextureRect
			t.set_anchors_preset(Control.PRESET_FULL_RECT)
			t.offset_left   = 0
			t.offset_top    = 0
			t.offset_right  = 0
			t.offset_bottom = 0
			t.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_COVERED

		_ensure_highlight_overlay(s)

	_selected = 0
	_update_visuals()

	if version_label:
		version_label.text = "MSP Version " + VERSION

	_load_settings()
	_update_mode_label()

	_install_screensaver()
	_reset_idle()
	_check_force_show_screensaver()


func _process(delta: float) -> void:
	if _saver == null or _saver_visible:
		return
	_idle_time += delta
	if _idle_time >= screensaver_seconds:
		_show_screensaver()


func _unhandled_input(event: InputEvent) -> void:
	if _is_real_input(event):
		_reset_idle()
		if _saver_visible:
			_hide_screensaver()
			if not _is_h_pressed(event):
				accept_event()
				return

	if _is_h_pressed(event):
		_open_high_score_viewer()
		accept_event()
		return

	if _is_f1_pressed(event):
		free_play = not free_play
		_coins = 0
		_save_settings()
		_update_mode_label()
		accept_event()
		return

	if _is_m_pressed(event):
		if not free_play:
			_coins = min(_coins + 1, COINS_NEEDED)
			_update_mode_label()
		accept_event()
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("start") or event.is_action_pressed("start_game"):
		if free_play:
			_start_selected_game()
		elif _coins >= COINS_NEEDED:
			_coins -= COINS_NEEDED
			_update_mode_label()
			_start_selected_game()
		else:
			_flash_label()
		accept_event()
		return

	if event.is_action_pressed("ui_left"):
		_move(Vector2i(-1, 0))
		accept_event()
	elif event.is_action_pressed("ui_right"):
		_move(Vector2i(1, 0))
		accept_event()
	elif event.is_action_pressed("ui_up"):
		_move(Vector2i(0, -1))
		accept_event()
	elif event.is_action_pressed("ui_down"):
		_move(Vector2i(0, 1))
		accept_event()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY_FREE_PLAY, free_play)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("GameSelect: could not save settings (%d)" % err)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err == OK:
		free_play = cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY_FREE_PLAY, free_play)


func _update_mode_label() -> void:
	if not mode_label:
		return
	if free_play:
		mode_label.text = "FREE PLAY"
		mode_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))
	else:
		match _coins:
			0:
				mode_label.text = "INSERT COIN"
				mode_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 1.0))
			1:
				mode_label.text = "INSERT COIN  ( 1 / 2 )"
				mode_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.0, 1.0))
			_:
				mode_label.text = "PRESS ENTER TO START"
				mode_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))


func _flash_label() -> void:
	if not mode_label:
		return
	var tween := create_tween()
	for i in range(3):
		tween.tween_property(mode_label, "modulate", Color(1, 0.15, 0.15, 1), 0.07)
		tween.tween_property(mode_label, "modulate", Color(1, 1, 1, 1),       0.07)


func _move(dir: Vector2i) -> void:
	var row := _selected / 2
	var col := _selected % 2
	col = clamp(col + dir.x, 0, 1)
	row = clamp(row + dir.y, 0, 1)
	var next := row * 2 + col
	if next != _selected:
		_selected = next
		_update_visuals()


func _start_selected_game() -> void:
	if _selected < 0 or _selected >= _defs.size():
		return
	var def_path := _defs[_selected]
	var game_def := load(def_path)
	if game_def == null:
		push_error("GameDef failed to load: " + def_path)
		return
	if get_tree().root.has_node("CurrentGame"):
		get_tree().root.get_node("CurrentGame").call("set_game", game_def)
	elif get_tree().root.has_node("current_game"):
		get_tree().root.get_node("current_game").call("set_game", game_def)
	else:
		push_error("Missing AutoLoad: CurrentGame/current_game")
		return
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


func _update_visuals() -> void:
	for i in range(_slots.size()):
		var s  := _slots[i]
		var hl := s.get_node_or_null("Highlight") as Panel
		if hl:
			hl.visible = (i == _selected)
		s.modulate = Color.WHITE if i == _selected else DIM_COLOR


func _ensure_highlight_overlay(slot: Control) -> void:
	if slot.get_node_or_null("Highlight") != null:
		return
	var p  := Panel.new()
	p.name         = "Highlight"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.focus_mode   = Control.FOCUS_NONE
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left   = 0
	p.offset_top    = 0
	p.offset_right  = 0
	p.offset_bottom = 0
	var sb := StyleBoxFlat.new()
	sb.bg_color                   = Color(0, 0, 0, 0)
	sb.border_width_left          = 8
	sb.border_width_top           = 8
	sb.border_width_right         = 8
	sb.border_width_bottom        = 8
	sb.border_color               = HIGHLIGHT_COLOR
	sb.corner_radius_top_left     = 18
	sb.corner_radius_top_right    = 18
	sb.corner_radius_bottom_left  = 18
	sb.corner_radius_bottom_right = 18
	p.add_theme_stylebox_override("panel", sb)
	slot.add_child(p)
	p.visible = false


# -------------------------
# Key detectors — keyboard AND control panel buttons
# -------------------------
func _is_f1_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo and k.physical_keycode == KEY_F1
	return event.is_action_pressed("toggle_free_play")


func _is_m_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo and k.physical_keycode == KEY_M
	return event.is_action_pressed("add_credit")


func _is_h_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo and k.physical_keycode == KEY_H
	return event.is_action_pressed("view_high_scores")


func _is_real_input(event: InputEvent) -> bool:
	if event is InputEventKey:          return event.pressed
	if event is InputEventJoypadButton: return event.pressed
	if event is InputEventJoypadMotion: return absf(event.axis_value) > 0.35
	if event is InputEventMouseButton:  return event.pressed
	return false


# -------------------------
# Screensaver helpers
# -------------------------
func _install_screensaver() -> void:
	if screensaver_scene_path.strip_edges() == "":
		return
	if not ResourceLoader.exists(screensaver_scene_path):
		push_warning("GameSelect: screensaver scene not found: " + screensaver_scene_path)
		return
	var ps: PackedScene = load(screensaver_scene_path)
	if ps == null:
		return
	_saver = ps.instantiate()
	if _saver == null:
		return
	add_child(_saver)
	_saver_visible = false
	_hide_screensaver()


func _show_screensaver() -> void:
	if _saver == null:
		return
	_saver_visible = true
	if _saver.has_method("show_screensaver"):
		_saver.call("show_screensaver")
	elif _saver is CanvasItem:
		(_saver as CanvasItem).visible = true


func _hide_screensaver() -> void:
	if _saver == null:
		return
	_saver_visible = false
	_reset_idle()   # ✅ FIX: reset idle timer so screensaver doesn't re-fire immediately
	if _saver.has_method("hide_screensaver"):
		_saver.call("hide_screensaver")
	elif _saver is CanvasItem:
		(_saver as CanvasItem).visible = false


func _reset_idle() -> void:
	_idle_time = 0.0


func _check_force_show_screensaver() -> void:
	if get_tree() == null or get_tree().root == null:
		return
	if get_tree().root.has_meta(SCREENSAVER_META_KEY):
		get_tree().root.remove_meta(SCREENSAVER_META_KEY)
		_show_screensaver()


func _open_high_score_viewer() -> void:
	if ResourceLoader.exists(HIGHSCORE_VIEWER_SCENE):
		get_tree().change_scene_to_file(HIGHSCORE_VIEWER_SCENE)
	else:
		push_warning("GameSelect: high score viewer scene not found: " + HIGHSCORE_VIEWER_SCENE)
