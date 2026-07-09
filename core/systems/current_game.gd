extends Node

var def: Resource

func set_game(game_def: Resource) -> void:
	def = game_def

	var gid := _extract_game_id(def)
	print("CurrentGame set to:", gid)

	var h := _find_hiscore()
	if h != null:
		h.call("set_game_id", gid)
	else:
		push_warning("CurrentGame: couldn't find hiscore AutoLoad. Expected name 'hiscore' in AutoLoad list.")

func has_game() -> bool:
	return def != null

func get_game() -> Resource:
	return def

func clear_game() -> void:
	def = null
	# Optional: don't fall back to shared file automatically.
	# If you DO want fallback, uncomment:
	# var h := _find_hiscore()
	# if h != null:
	#     h.call("set_game_id", "")

# -------------------------
# Helpers
# -------------------------
func _extract_game_id(r: Resource) -> String:
	if r == null:
		return ""

	# 1) direct property (works for exported vars on Resources)
	# In Godot 4, we can check property list to avoid errors.
	for p in r.get_property_list():
		if String(p.name) == "game_id":
			return str(r.get("game_id"))

	# 2) fallback: try metadata or name
	if r.has_meta("game_id"):
		return str(r.get_meta("game_id"))

	return ""

func _find_hiscore() -> Node:
	# Preferred: AutoLoad named "hiscore"
	if get_tree().root.has_node("hiscore"):
		return get_tree().root.get_node("hiscore")

	# Fallback: scan root children for a node with set_game_id()
	for c in get_tree().root.get_children():
		if c != null and c.has_method("set_game_id"):
			return c

	return null
