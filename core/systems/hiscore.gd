extends Node

const MAX_SCORES := 10

# If no game is selected yet, we fall back to this:
const FALLBACK_SAVE_PATH := "user://highscores.cfg"

# Each entry: { "name": "MSP", "cents": 1230 }
var scores: Array = []

var _game_id: String = ""
var _save_path: String = FALLBACK_SAVE_PATH


func _ready() -> void:
	# Loads fallback until CurrentGame tells us the real game_id
	load_scores()


# --------------------------------------------------
# Per-game support
# --------------------------------------------------
func set_game_id(game_id: String) -> void:
	var clean := _sanitize_game_id(game_id)

	if clean == _game_id and _save_path != "":
		return

	_game_id = clean

	if _game_id == "":
		_save_path = FALLBACK_SAVE_PATH
	else:
		_save_path = "user://highscores_%s.cfg" % _game_id

	print("hiscore: using save file -> ", _save_path)
	load_scores()


func get_game_id() -> String:
	return _game_id


func get_save_path() -> String:
	return _save_path


func _sanitize_game_id(s: String) -> String:
	s = s.strip_edges().to_lower()
	if s == "":
		return ""

	# Keep only [a-z0-9_], replace everything else with "_"
	var out := ""
	for i in range(s.length()):
		var ch := s[i]
		var code := ch.unicode_at(0)
		var is_num := (code >= 48 and code <= 57)
		var is_low := (code >= 97 and code <= 122)
		var is_us := (ch == "_")
		out += ch if (is_num or is_low or is_us) else "_"

	# compress repeating underscores
	while out.find("__") != -1:
		out = out.replace("__", "_")

	return out


# --------------------------------------------------
# Load / Save
# --------------------------------------------------
func load_scores() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(_save_path)

	if err != OK:
		# Default table when file doesn't exist yet
		scores = [
			{"name":"MSP","cents":2000},
			{"name":"MSP","cents":1500},
			{"name":"MSP","cents":1000},
		]
		_trim()
		return

	scores.clear()
	var count := int(cfg.get_value("highscores", "count", 0))
	for i in range(count):
		var name := str(cfg.get_value("highscores", "name_%d" % i, "MSP"))
		var cents := int(cfg.get_value("highscores", "cents_%d" % i, 0))
		scores.append({"name": name, "cents": cents})

	scores.sort_custom(func(a, b): return int(a["cents"]) > int(b["cents"]))
	_trim()


func save_scores() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("highscores", "count", scores.size())
	for i in range(scores.size()):
		cfg.set_value("highscores", "name_%d" % i, scores[i]["name"])
		cfg.set_value("highscores", "cents_%d" % i, scores[i]["cents"])
	cfg.save(_save_path)


# --------------------------------------------------
# API used by the rest of the game
# --------------------------------------------------
func qualifies(cents: int) -> bool:
	if scores.size() < MAX_SCORES:
		return true
	return cents > int(scores[-1]["cents"])


func add_score(name: String, cents: int) -> void:
	name = name.strip_edges().to_upper()
	if name.length() == 0:
		name = "MSP"

	scores.append({"name": name, "cents": cents})
	scores.sort_custom(func(a, b): return int(a["cents"]) > int(b["cents"]))
	_trim()
	save_scores()


func _trim() -> void:
	while scores.size() > MAX_SCORES:
		scores.pop_back()


func format_dollars(cents: int) -> String:
	return "$%.2f" % (cents / 100.0)


# ==================================================
# RESET FUNCTIONS (your Button #2 / R action calls these)
# ==================================================
func reset_highscores_low_test_values() -> void:
	# Tiny values for testing: $0.50, $1.00, $1.50, ...
	scores = [
		{"name":"MSP","cents":50},
		{"name":"MSP","cents":100},
		{"name":"MSP","cents":150},
		{"name":"MSP","cents":200},
		{"name":"MSP","cents":250},
		{"name":"MSP","cents":300},
		{"name":"MSP","cents":350},
		{"name":"MSP","cents":400},
		{"name":"MSP","cents":450},
		{"name":"MSP","cents":500},
	]
	_trim()
	save_scores()
	print("✅ High scores RESET to low test values for file:", _save_path)


func reset_highscores_blank() -> void:
	scores.clear()
	save_scores()
	print("✅ High scores CLEARED for file:", _save_path)
