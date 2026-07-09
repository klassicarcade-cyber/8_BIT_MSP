# press_start.gd
extends Control

@export var gameplay_root_path: NodePath

var gameplay_root: Node = null

const HIGHSCORE_VIEWER_SCENE := "res://core/ui/high_score_viewer.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_NONE

	if gameplay_root_path != NodePath():
		gameplay_root = get_node_or_null(gameplay_root_path)

	if gameplay_root == null:
		gameplay_root = get_tree().current_scene

	show()
	set_process_input(true)

	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# --- HIGH SCORE (H key) ---
	if _is_h_pressed(event):
		open_high_score_viewer()
		accept_event()
		return

	# --- START GAME (bulletproof) ---
	if _is_start_pressed(event):
		start_game()
		return


func start_game() -> void:
	var dim_layer := get_node_or_null("../UI_Dim")
	if dim_layer:
		dim_layer.hide()
	else:
		var root := get_tree().current_scene
		if root:
			var dim_from_root := root.get_node_or_null("UI_Dim")
			if dim_from_root:
				dim_from_root.hide()

	hide()
	set_process_input(false)

	if gameplay_root and gameplay_root.has_method("reload_current_game"):
		gameplay_root.call_deferred("reload_current_game")


func open_high_score_viewer() -> void:
	if ResourceLoader.exists(HIGHSCORE_VIEWER_SCENE):
		get_tree().change_scene_to_file(HIGHSCORE_VIEWER_SCENE)
	else:
		push_warning("PressStart: high score viewer scene not found: " + HIGHSCORE_VIEWER_SCENE)


# --- INPUT HELPERS ---

func _is_h_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_H
	return false


func _is_start_pressed(event: InputEvent) -> bool:
	# 1. Direct Enter key (MOST reliable)
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.physical_keycode == KEY_ENTER or key_event.physical_keycode == KEY_KP_ENTER:
				return true

	# 2. Godot input actions (keyboard + joystick)
	if event.is_action_pressed("start_game") or event.is_action_pressed("ui_accept"):
		return true

	return false
