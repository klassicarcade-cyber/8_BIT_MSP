extends Control

signal finished

@export var show_seconds_after_save: float = 3.0

# --- TIMEOUTS ---
@export var entry_timeout_seconds: float = 20.0   # timeout while entering initials
@export var auto_finish_after_save: bool = true    # return to attract automatically after saving (MANUAL confirm only)

var _entry_idle_time: float = 0.0
var _post_save_time: float = 0.0
var _post_save_active: bool = false

# --- FONT SIZES (ABOVE THE BOX) ---
@export var title_font_size: int = 72        # GAME OVER
@export var sub_font_size: int = 34          # SCORE: $X.XX
@export var initials_font_size: int = 88     # M S P
@export var hint_font_size: int = 24         # instructions line

var entering: bool = false
var letters: Array[String] = ["M", "S", "P"] # default initials
var index: int = 0
var target_cents: int = 0
var qualifies: bool = false

# --- DOUBLE-CONFIRM STATE ---
# First START press arms the confirm; second START press locks the letter.
# Any joystick movement cancels the pending confirm (prevents accidental saves).
var _confirm_pending: bool = false
var _confirm_flash: float = 0.0   # drives the hint flash timer

# Block all input briefly after opening — prevents the Start press that ended
# the attract screen from also instantly dismissing the game over screen.
var _input_blocked: bool = false
var _input_block_timer: float = 0.0
const INPUT_BLOCK_SECONDS: float = 0.3

@onready var panel: Panel = _find_panel(["Panel", "PanelContainer", "OverlayPanel"])
@onready var dim: ColorRect = _find_colorrect(["Dim", "Panel/Dim"])
@onready var title: Label = _find_label(["Title", "Panel/Title"])
@onready var sub: Label = _find_label(["Sub", "Panel/Sub"])
@onready var hint: Label = _find_label(["Hint", "Panel/Hint"])
@onready var initials_row: HBoxContainer = _find_hbox(["InitialsRow", "Panel/InitialsRow"])
@onready var l1: Label = _find_label(["L1", "InitialsRow/L1", "Panel/InitialsRow/L1"])
@onready var l2: Label = _find_label(["L2", "InitialsRow/L2", "Panel/InitialsRow/L2"])
@onready var l3: Label = _find_label(["L3", "InitialsRow/L3", "Panel/InitialsRow/L3"])
@onready var scores_box: RichTextLabel = _find_richtext(["Scores", "Panel/Scores"])

var _layout_box: VBoxContainer = null
var _scores_card: PanelContainer = null
var _scores_margin: MarginContainer = null

const COLOR_WHITE := Color(1, 1, 1, 1)
const COLOR_WHITE_DIM := Color(1, 1, 1, 0.45)

# -------------------------
# Reset highscores (Button #2)
# -------------------------
var _reset_hold_time := 0.0
var _reset_holding := false
const RESET_HOLD_SECONDS := 1.0
const HIGHSCORE_VIEWER_SCENE := "res://core/ui/high_score_viewer.tscn"


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_layout_if_needed()
	_force_white_everywhere()
	_apply_font_sizes()


func open_game_over(cents: int) -> void:
	visible = true
	_entry_idle_time = 0.0
	_post_save_time = 0.0
	_post_save_active = false
	entering = false
	index = 0
	letters = ["M", "S", "P"]
	_confirm_pending = false
	_confirm_flash = 0.0
	_input_blocked = true
	_input_block_timer = 0.0

	target_cents = cents
	qualifies = hiscore.qualifies(cents)

	_force_white_everywhere()
	_apply_font_sizes()

	if title:
		title.text = "GAME OVER"
	if sub:
		sub.text = "SCORE: %s" % score.dollars_string()

	_render_scores()

	if qualifies:
		entering = true
		_entry_idle_time = 0.0
		if hint:
			hint.text = "UP/DOWN change   LEFT/RIGHT move   START BUTTON confirm"
		_update_initials()
	else:
		entering = false
		_post_save_active = false
		if hint:
			hint.text = "PRESS BUTTON"
		if sub:
			sub.text = "SCORE: %s  (NO NEW HIGH SCORE)" % score.dollars_string()

	grab_focus()


func _process(delta: float) -> void:
	if not visible:
		return

	# Count down the input block so same-frame Start press can't dismiss instantly
	if _input_blocked:
		_input_block_timer += delta
		if _input_block_timer >= INPUT_BLOCK_SECONDS:
			_input_blocked = false

	# Flash hint when confirm is pending
	if _confirm_pending:
		_confirm_flash -= delta
		if _confirm_flash <= 0.0:
			_confirm_flash = 0.45
			if hint:
				hint.visible = not hint.visible

	# High score entry timeout
	if entering:
		_entry_idle_time += delta
		if entry_timeout_seconds > 0.0 and _entry_idle_time >= entry_timeout_seconds:
			_entry_idle_time = 0.0
			_save_and_show(false)
	else:
		_entry_idle_time = 0.0
		if _post_save_active:
			_post_save_time += delta
			if show_seconds_after_save > 0.0 and _post_save_time >= show_seconds_after_save:
				_post_save_active = false
				emit_signal("finished")

	# Hold to reset highscores
	if _reset_holding:
		_reset_hold_time += delta
		if _reset_hold_time >= RESET_HOLD_SECONDS:
			_reset_holding = false
			_reset_hold_time = 0.0

			if hiscore.has_method("reset_highscores_low_test_values"):
				hiscore.reset_highscores_low_test_values()

			_render_scores()

			entering = false
			_confirm_pending = false
			_confirm_flash = 0.0
			if hint:
				hint.visible = true
				hint.text = "PRESS BUTTON"
			if sub:
				sub.text = "SCORE: %s" % score.dollars_string()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# Don't accept any input during the brief block window after opening
	if _input_blocked:
		return

	# Any input resets timers
	if event.is_pressed():
		_entry_idle_time = 0.0
		_post_save_time = 0.0

	# Button #2: reset highscores (hold)
	if event.is_action_pressed("reset_highscores"):
		_start_reset_hold()
		return
	if event.is_action_released("reset_highscores"):
		_cancel_reset_hold()
		return

	# High score viewer — only available after entry is done
	if not entering and _is_h_pressed(event):
		_open_high_score_viewer()
		return

	if entering:
		_handle_initials_input(event)
	else:
		if event.is_action_pressed("ui_accept"):
			emit_signal("finished")


func _start_reset_hold() -> void:
	_reset_holding = true
	_reset_hold_time = 0.0
	if hint:
		hint.text = ""


func _cancel_reset_hold() -> void:
	_reset_holding = false
	_reset_hold_time = 0.0


func _handle_initials_input(event: InputEvent) -> void:
	# Movement cancels any pending confirm
	if event.is_action_pressed("ui_left"):
		_confirm_pending = false
		_confirm_flash = 0.0
		if hint: hint.visible = true
		index = clamp(index - 1, 0, 2)
		_update_initials()
		_restore_hint_text()
		return

	if event.is_action_pressed("ui_right"):
		_confirm_pending = false
		_confirm_flash = 0.0
		if hint: hint.visible = true
		index = clamp(index + 1, 0, 2)
		_update_initials()
		_restore_hint_text()
		return

	if event.is_action_pressed("ui_up"):
		_confirm_pending = false
		_confirm_flash = 0.0
		if hint: hint.visible = true
		_change_letter(+1)
		_restore_hint_text()
		return

	if event.is_action_pressed("ui_down"):
		_confirm_pending = false
		_confirm_flash = 0.0
		if hint: hint.visible = true
		_change_letter(-1)
		_restore_hint_text()
		return

	# START / ui_accept — auto-advance on letters 1 & 2, double-confirm on letter 3
	if event.is_action_pressed("ui_accept"):
		if index < 2:
			# Letters 1 & 2: single press advances immediately
			index += 1
			_confirm_pending = false
			_confirm_flash = 0.0
			if hint: hint.visible = true
			_update_initials()
			_restore_hint_text()
		else:
			# Letter 3: double-confirm required before saving
			if not _confirm_pending:
				_confirm_pending = true
				_confirm_flash = 0.45
				if hint:
					hint.visible = true
					hint.text = "PRESS START AGAIN TO CONFIRM"
			else:
				# Second press — save
				_confirm_pending = false
				_confirm_flash = 0.0
				if hint: hint.visible = true
				_save_and_show(false)
		return


func _restore_hint_text() -> void:
	if hint:
		hint.text = "UP/DOWN change   LEFT/RIGHT move   START BUTTON confirm"


func _change_letter(dir: int) -> void:
	var c: int = letters[index].unicode_at(0)
	c += dir
	if c > "Z".unicode_at(0):
		c = "A".unicode_at(0)
	elif c < "A".unicode_at(0):
		c = "Z".unicode_at(0)
	letters[index] = String.chr(c)
	_update_initials()


func _update_initials() -> void:
	if l1: l1.text = letters[0]
	if l2: l2.text = letters[1]
	if l3: l3.text = letters[2]
	if l1: l1.modulate = COLOR_WHITE if index == 0 else COLOR_WHITE_DIM
	if l2: l2.modulate = COLOR_WHITE if index == 1 else COLOR_WHITE_DIM
	if l3: l3.modulate = COLOR_WHITE if index == 2 else COLOR_WHITE_DIM


func _save_and_show(enable_auto_finish: bool) -> void:
	entering = false
	_confirm_pending = false
	_confirm_flash = 0.0
	_post_save_time = 0.0
	_post_save_active = enable_auto_finish

	if hint: hint.visible = true

	var name := "%s%s%s" % [letters[0], letters[1], letters[2]]
	hiscore.add_score(name, target_cents)

	# Upload to remote leaderboard immediately after saving
	if has_node("/root/ScoreUploader"):
		get_node("/root/ScoreUploader").upload_now()

	_render_scores()

	if hint:
		hint.text = "SAVED!  PRESS BUTTON"
	if sub:
		sub.text = "SCORE: %s" % score.dollars_string()


func _render_scores() -> void:
	if not scores_box:
		return
	scores_box.bbcode_enabled = true
	scores_box.clear()
	scores_box.append_text("[color=#ffffff]")
	scores_box.append_text("[center][b]HIGH SCORES[/b]\n\n[/center]")
	for i in range(hiscore.scores.size()):
		var e = hiscore.scores[i]
		var line := "%2d.  %s   %s\n" % [i + 1, e["name"], hiscore.format_dollars(int(e["cents"]))]
		scores_box.append_text(line)
	scores_box.append_text("[/color]")


# --------------------------------------------------
# LAYOUT + DIM + SCORE CARD BACKDROP
# --------------------------------------------------
func _build_layout_if_needed() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	if dim == null:
		dim = ColorRect.new()
		dim.name = "Dim"
		add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_left = 0
	dim.offset_top = 0
	dim.offset_right = 0
	dim.offset_bottom = 0
	dim.color = Color(0, 0, 0, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_layout_box = get_node_or_null("LayoutBox") as VBoxContainer
	if _layout_box == null:
		_layout_box = VBoxContainer.new()
		_layout_box.name = "LayoutBox"
		add_child(_layout_box)

	_layout_box.set_anchors_preset(Control.PRESET_CENTER)
	_layout_box.offset_left = -520
	_layout_box.offset_right = 520
	_layout_box.offset_top = -500
	_layout_box.offset_bottom = 100
	_layout_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_layout_box.add_theme_constant_override("separation", 16)

	_reparent_if_needed(title, _layout_box)
	_reparent_if_needed(sub, _layout_box)
	_reparent_if_needed(initials_row, _layout_box)
	_reparent_if_needed(hint, _layout_box)

	if scores_box:
		_scores_card = _layout_box.get_node_or_null("ScoresCard") as PanelContainer
		if _scores_card == null:
			_scores_card = PanelContainer.new()
			_scores_card.name = "ScoresCard"
			_layout_box.add_child(_scores_card)

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.60)
		sb.corner_radius_top_left = 18
		sb.corner_radius_top_right = 18
		sb.corner_radius_bottom_left = 18
		sb.corner_radius_bottom_right = 18
		_scores_card.add_theme_stylebox_override("panel", sb)
		_scores_card.custom_minimum_size = Vector2(900, 420)

		_scores_margin = _scores_card.get_node_or_null("Margin") as MarginContainer
		if _scores_margin == null:
			_scores_margin = MarginContainer.new()
			_scores_margin.name = "Margin"
			_scores_card.add_child(_scores_margin)
			_scores_margin.add_theme_constant_override("margin_left", 24)
			_scores_margin.add_theme_constant_override("margin_right", 24)
			_scores_margin.add_theme_constant_override("margin_top", 20)
			_scores_margin.add_theme_constant_override("margin_bottom", 20)

		_reparent_if_needed(scores_box, _scores_margin)

		scores_box.fit_content = true
		scores_box.scroll_active = false
		scores_box.custom_minimum_size = Vector2(0, 360)
		scores_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if panel:
		panel.visible = false


func _force_white_everywhere() -> void:
	_force_label_white(title)
	_force_label_white(sub)
	_force_label_white(hint)
	_force_label_white(l1)
	_force_label_white(l2)
	_force_label_white(l3)
	if scores_box:
		scores_box.modulate = COLOR_WHITE
		scores_box.add_theme_color_override("default_color", COLOR_WHITE)
		scores_box.bbcode_enabled = true


func _apply_font_sizes() -> void:
	_apply_font_size(title, title_font_size)
	_apply_font_size(sub, sub_font_size)
	_apply_font_size(hint, hint_font_size)
	_apply_font_size(l1, initials_font_size)
	_apply_font_size(l2, initials_font_size)
	_apply_font_size(l3, initials_font_size)


func _apply_font_size(lbl: Label, px: int) -> void:
	if lbl == null:
		return
	lbl.add_theme_font_size_override("font_size", px)
	var ls: LabelSettings = lbl.label_settings
	if ls == null:
		ls = LabelSettings.new()
		lbl.label_settings = ls
	ls.font_size = px


func _force_label_white(lbl: Label) -> void:
	if lbl == null:
		return
	lbl.add_theme_color_override("font_color", COLOR_WHITE)
	var ls: LabelSettings = lbl.label_settings
	if ls == null:
		ls = LabelSettings.new()
		lbl.label_settings = ls
	ls.font_color = COLOR_WHITE
	lbl.modulate = COLOR_WHITE


func _reparent_if_needed(n: Node, new_parent: Node) -> void:
	if n == null:
		return
	if n.get_parent() == new_parent:
		return
	n.reparent(new_parent)


# --------------------------------------------------
# SAFE NODE FINDERS
# --------------------------------------------------
func _find_panel(paths: Array[String]) -> Panel:
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n is Panel:
			return n
	var deep := find_child(paths[0], true, false)
	if deep is Panel:
		return deep
	return null

func _find_colorrect(paths: Array[String]) -> ColorRect:
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n is ColorRect:
			return n
	var deep := find_child(paths[0], true, false)
	if deep is ColorRect:
		return deep
	return null

func _find_label(paths: Array[String]) -> Label:
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n is Label:
			return n
	var deep := find_child(paths[0], true, false)
	if deep is Label:
		return deep
	return null

func _find_hbox(paths: Array[String]) -> HBoxContainer:
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n is HBoxContainer:
			return n
	var deep := find_child(paths[0], true, false)
	if deep is HBoxContainer:
		return deep
	return null

func _find_richtext(paths: Array[String]) -> RichTextLabel:
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n is RichTextLabel:
			return n
	var deep := find_child(paths[0], true, false)
	if deep is RichTextLabel:
		return deep
	return null


func _open_high_score_viewer() -> void:
	if ResourceLoader.exists(HIGHSCORE_VIEWER_SCENE):
		get_tree().change_scene_to_file(HIGHSCORE_VIEWER_SCENE)
	else:
		push_warning("GameOverUI: high score viewer scene not found: " + HIGHSCORE_VIEWER_SCENE)


func _is_h_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_H
	return false
