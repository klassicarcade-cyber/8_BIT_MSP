# res://core/ui/high_score_viewer.gd  (MSP multicart: Gobles / Paw Paw / Mars / Fizz)
extends Control

const GAME_SELECT_SCENE := "res://core/game_select.tscn"
const SCREENSAVER_META_KEY := "show_screensaver_on_ready"
const IDLE_TIMEOUT_SECONDS := 30.0

const AUTO_CYCLE_SECONDS := 5.0
const FADE_SECONDS := 0.35

const RESET_HOLD_SECONDS := 1.0

# Maximum rows shown on the review screen. Matches the 10-place
# entry screen. The save file may contain more; we only show these.
const MAX_DISPLAY_ROWS := 10

# Extra vertical padding (total, top + bottom) added around the score
# text when auto-sizing the panel. Bump this if the panel feels tight.
const PANEL_VERTICAL_PADDING := 80.0

const PAGE_GAME_IDS: Array[String] = ["gobles", "paw_paw", "mars", "fizz"]
const PAGE_TITLES: Array[String] = [
	"MR SODA POP - GOBLES",
	"MR SODA POP - PAW PAW",
	"MR SODA POP - MARS MADNESS",
	"MR SODA POP - FIZZ AGE",
]

var _page: int = 0
var _idle_time: float = 0.0
var _cycle_time: float = 0.0
var _is_transitioning: bool = false
var _fade_tween: Tween = null

var _reset_holding: bool = false
var _reset_hold_time: float = 0.0
var _reset_message_time: float = 0.0

@onready var title_label: Label = get_node_or_null("TitleLabel") as Label
@onready var scores_panel: CanvasItem = get_node_or_null("ScoresPanel") as CanvasItem
@onready var scores_box: RichTextLabel = get_node_or_null("ScoresPanel/ScoresMargin/ScoresBox") as RichTextLabel
@onready var help_label: Label = get_node_or_null("HelpLabel") as Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_idle_time = 0.0
	_cycle_time = 0.0
	# Let the RichTextLabel grow to fit its text instead of clipping,
	# and disable the scrollbar so long lists never show a scroll UI.
	if scores_box:
		scores_box.fit_content = true
		scores_box.scroll_active = false
	_update_help_text()
	_show_page(_page)
	_set_fade_alpha(1.0)
	grab_focus()


func _process(delta: float) -> void:
	_idle_time += delta

	if not _reset_holding:
		_cycle_time += delta

	if _reset_message_time > 0.0:
		_reset_message_time = maxf(0.0, _reset_message_time - delta)
		if _reset_message_time <= 0.0:
			_update_help_text()

	if _reset_holding:
		_reset_hold_time += delta
		if _reset_hold_time >= RESET_HOLD_SECONDS:
			_reset_holding = false
			_reset_hold_time = 0.0
			_reset_current_page_scores()
			return

	if _idle_time >= IDLE_TIMEOUT_SECONDS:
		_go_to_screensaver()
		return

	if _cycle_time >= AUTO_CYCLE_SECONDS and not _is_transitioning:
		_cycle_time = 0.0
		_advance_page_with_fade()


func _unhandled_input(event: InputEvent) -> void:
	if _is_real_input(event):
		_idle_time = 0.0

	if _is_r_pressed(event):
		_start_reset_hold()
		accept_event()
		return

	if _is_r_released(event):
		_cancel_reset_hold()
		accept_event()
		return

	if _is_h_pressed(event):
		_idle_time = 0.0
		_cycle_time = 0.0
		_cancel_reset_hold()
		_advance_page_with_fade()
		accept_event()
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_go_to_screensaver()
		accept_event()


func _advance_page_with_fade() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade_alpha, 1.0, 0.0, FADE_SECONDS)
	await _fade_tween.finished
	_page = (_page + 1) % PAGE_GAME_IDS.size()
	_show_page(_page)
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade_alpha, 0.0, 1.0, FADE_SECONDS)
	await _fade_tween.finished
	_is_transitioning = false


func _set_fade_alpha(alpha: float) -> void:
	alpha = clampf(alpha, 0.0, 1.0)
	if title_label:
		var c := title_label.modulate
		c.a = alpha
		title_label.modulate = c
	if scores_panel:
		var c2 := scores_panel.modulate
		c2.a = alpha
		scores_panel.modulate = c2
	if scores_box and scores_panel == null:
		var c3 := scores_box.modulate
		c3.a = alpha
		scores_box.modulate = c3


func _show_page(page_index: int) -> void:
	if page_index < 0 or page_index >= PAGE_GAME_IDS.size():
		return
	var game_id: String = PAGE_GAME_IDS[page_index]
	if title_label:
		title_label.text = PAGE_TITLES[page_index]
	if scores_box == null:
		push_warning("HighScoreViewer: ScoresBox not found.")
		return
	scores_box.bbcode_enabled = true
	scores_box.clear()
	scores_box.append_text("[center][b]HIGH SCORES[/b][/center]\n\n")
	var scores: Array = _load_scores_for_game(game_id)
	if scores.is_empty():
		scores_box.append_text("[center]NO SCORES YET[/center]")
		call_deferred("_fit_panel_to_content")
		return
	var row_count: int = mini(scores.size(), MAX_DISPLAY_ROWS)
	for i in range(row_count):
		var entry: Dictionary = scores[i]
		var initials: String = str(entry.get("initials", entry.get("name", "MSP")))
		var cents: int = int(entry.get("cents", entry.get("score", 0)))
		var line: String = "[center]%2d.  %s   %s[/center]\n" % [i + 1, initials, _format_dollars(cents)]
		scores_box.append_text(line)
	# Resize the panel AFTER the RichTextLabel has laid out its text.
	call_deferred("_fit_panel_to_content")


# Resizes ScoresPanel vertically so ALL rows fit (no more clipping at
# 7 entries), then re-centers it on screen. Horizontal position and
# width are left exactly as set in the editor. Runs deferred so the
# RichTextLabel has finished laying out its content first.
func _fit_panel_to_content() -> void:
	if scores_box == null:
		return
	var panel := scores_panel as Control
	if panel == null:
		return
	var content_h: float = float(scores_box.get_content_height())
	if content_h <= 0.0:
		return
	var new_h: float = content_h + PANEL_VERTICAL_PADDING
	var viewport_h: float = get_viewport_rect().size.y
	# Never grow past the viewport (leave a little breathing room).
	new_h = minf(new_h, viewport_h - 40.0)
	var panel_x: float = panel.position.x
	var panel_w: float = panel.size.x
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(panel_x, (viewport_h - new_h) * 0.5)
	panel.size = Vector2(panel_w, new_h)


func _load_scores_for_game(game_id: String) -> Array:
	var possible_paths: Array[String] = _possible_score_paths(game_id)
	for save_path in possible_paths:
		var cfg := ConfigFile.new()
		var err := cfg.load(save_path)
		if err == OK:
			return _scores_from_config(cfg)
	return [
		{"initials":"MSP", "cents":2000},
		{"initials":"POP", "cents":1500},
		{"initials":"SOD", "cents":1000},
	]


func _possible_score_paths(game_id: String) -> Array[String]:
	return [
		"user://highscores_%s.cfg" % game_id,
		"user://high_scores_%s.cfg" % game_id,
		"user://%s_highscores.cfg" % game_id,
	]


func _scores_from_config(cfg: ConfigFile) -> Array:
	var result: Array = []
	if cfg.has_section("highscores"):
		var count: int = int(cfg.get_value("highscores", "count", 0))
		for i in range(count):
			var initials: String = str(cfg.get_value("highscores", "initials_%d" % i, cfg.get_value("highscores", "name_%d" % i, "MSP")))
			var cents: int = int(cfg.get_value("highscores", "cents_%d" % i, cfg.get_value("highscores", "score_%d" % i, 0)))
			result.append({"initials": initials, "cents": cents})
	if result.is_empty():
		for section in cfg.get_sections():
			if section.begins_with("score") or section.begins_with("entry"):
				var initials2: String = str(cfg.get_value(section, "initials", cfg.get_value(section, "name", "MSP")))
				var cents2: int = int(cfg.get_value(section, "cents", cfg.get_value(section, "score", 0)))
				result.append({"initials": initials2, "cents": cents2})
	result.sort_custom(func(a, b): return int(a["cents"]) > int(b["cents"]))
	return result


func _start_reset_hold() -> void:
	_reset_holding = true
	_reset_hold_time = 0.0
	_idle_time = 0.0
	_cycle_time = 0.0
	if help_label:
		help_label.text = "HOLD R TO RESET THIS TABLE..."


func _cancel_reset_hold() -> void:
	if not _reset_holding:
		return
	_reset_holding = false
	_reset_hold_time = 0.0
	_update_help_text()


func _reset_current_page_scores() -> void:
	var game_id: String = PAGE_GAME_IDS[_page]
	var save_path: String = "user://highscores_%s.cfg" % game_id
	var cfg := ConfigFile.new()
	cfg.set_value("highscores", "count", 0)
	var err := cfg.save(save_path)
	if err != OK:
		push_warning("HighScoreViewer: could not save blank score file: " + save_path)
		if help_label:
			help_label.text = "RESET FAILED: " + PAGE_TITLES[_page]
		return
	if get_tree() and get_tree().root and get_tree().root.has_node("hiscore"):
		var hs = get_tree().root.get_node("hiscore")
		if hs:
			var active_id := ""
			if hs.has_method("get_game_id"):
				active_id = str(hs.call("get_game_id")).strip_edges().to_lower().replace(" ", "_")
			if active_id == game_id:
				if "scores" in hs:
					hs.scores.clear()
				if hs.has_method("load_scores"):
					hs.call("load_scores")
	_cycle_time = 0.0
	_idle_time = 0.0
	_reset_message_time = 2.0
	_show_page(_page)
	if help_label:
		help_label.text = "RESET COMPLETE: " + PAGE_TITLES[_page]


func _update_help_text() -> void:
	if help_label:
		help_label.text = "H = NEXT TABLE   •   AUTO-CYCLES EVERY 5 SEC   •   HOLD R = RESET THIS TABLE   •   30 SEC IDLE = SCREEN SAVER"


func _format_dollars(cents: int) -> String:
	return "$%.2f" % (float(cents) / 100.0)


func _go_to_screensaver() -> void:
	if get_tree() == null or get_tree().root == null:
		return
	get_tree().root.set_meta(SCREENSAVER_META_KEY, true)
	get_tree().change_scene_to_file(GAME_SELECT_SCENE)


# -------------------------
# Key detectors — keyboard AND control panel buttons
# -------------------------
func _is_h_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_H
	return event.is_action_pressed("view_high_scores")


func _is_r_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_R
	return event.is_action_pressed("reset_highscores")


func _is_r_released(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return not key_event.pressed and key_event.physical_keycode == KEY_R
	return event.is_action_released("reset_highscores")


func _is_real_input(event: InputEvent) -> bool:
	if event is InputEventKey:          return (event as InputEventKey).pressed
	if event is InputEventJoypadButton: return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion: return absf((event as InputEventJoypadMotion).axis_value) > 0.35
	if event is InputEventMouseButton:  return (event as InputEventMouseButton).pressed
	return false
