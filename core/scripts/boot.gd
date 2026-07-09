extends Node

# Boot now goes to the 4-game selector
const GAME_SELECT_SCENE := "res://core/game_select.tscn"

func _ready() -> void:
	var err := get_tree().change_scene_to_file(GAME_SELECT_SCENE)
	if err != OK:
		push_error("BOOT: Failed to change to game select scene: %s (err=%d)" % [GAME_SELECT_SCENE, err])
