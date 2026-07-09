# ScoreUploader.gd
# Autoload — res://core/systems/ScoreUploader.gd
#
# Uploads local high scores to sodapopfest.com/msp/ after every game.
# Reads score files directly instead of switching hiscore game_id.

extends Node

# ── CONFIGURE PER CABINET ──
const LOCATION: String = "3.0"
																																										
const SECRET_KEY: String = "klass1c_msp_2026"
const SERVER_URL: String = "http://sodapopfest.com/msp/scores.php"

const AUTO_UPLOAD_INTERVAL: float = 120.0

# Map: local save file suffix → server game name
const GAME_FILE_MAP: Dictionary = {
	"gobles":  "gobles",
	"paw_paw": "paw_paw",
	"mars":    "mars",
	"fizz":    "fizz",
}

var _timer: float = 0.0
var _http: HTTPRequest = null
var _queue: Array = []   # queue of {game, scores} dicts to upload
var _uploading: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	# Upload shortly after startup
	_timer = AUTO_UPLOAD_INTERVAL - 8.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= AUTO_UPLOAD_INTERVAL:
		_timer = 0.0
		upload_all_games()


# ── PUBLIC API ──
func upload_now() -> void:
	_timer = 0.0
	upload_all_games()


func upload_all_games() -> void:
	for file_suffix in GAME_FILE_MAP.keys():
		var server_game: String = GAME_FILE_MAP[file_suffix]
		var scores := _read_scores_from_file(file_suffix)
		if scores.is_empty():
			continue
		_queue.append({ "game": server_game, "scores": scores })
		print("ScoreUploader: queued %d scores for %s @ location %s" % [scores.size(), server_game, LOCATION])

	_process_queue()


func _read_scores_from_file(file_suffix: String) -> Array:
	var save_path := "user://highscores_%s.cfg" % file_suffix
	var cfg := ConfigFile.new()
	var err := cfg.load(save_path)
	if err != OK:
		return []

	var result: Array = []
	var count: int = int(cfg.get_value("highscores", "count", 0))
	for i in range(count):
		var name_val: String = str(cfg.get_value("highscores", "name_%d" % i, "MSP"))
		var cents_val: int   = int(cfg.get_value("highscores", "cents_%d" % i, 0))
		if cents_val > 0:
			result.append({ "name": name_val, "cents": cents_val })

	return result


func _process_queue() -> void:
	if _uploading or _queue.is_empty():
		return

	_uploading = true
	var item: Dictionary = _queue.pop_front()
	_send(item["game"], item["scores"])


func _send(server_game: String, scores_array: Array) -> void:
	var payload: Dictionary = {
		"key":      SECRET_KEY,
		"game":     server_game,
		"location": LOCATION,
		"scores":   scores_array,
	}

	var json_body: String = JSON.stringify(payload)
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])

	var err: int = _http.request(SERVER_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		push_warning("ScoreUploader: HTTPRequest error %d for game %s" % [err, server_game])
		_uploading = false
		_process_queue()
	else:
		print("ScoreUploader: uploading %d scores for %s @ location %s" % [scores_array.size(), server_game, LOCATION])


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_uploading = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("ScoreUploader: upload failed — result=%d http=%d" % [result, response_code])
	else:
		var text: String = body.get_string_from_utf8()
		print("ScoreUploader: server response → ", text)

	# Process next item in queue
	_process_queue()
