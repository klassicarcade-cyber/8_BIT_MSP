extends Node
class_name VoiceBank

# Caches loaded voice clips per speaker key.
var _cache: Dictionary = {}

func get_random_voice(speaker_key: String, dir_path: String) -> AudioStream:
	# speaker_key example: "msp", "louie"
	# dir_path example: "res://series/gob/voice/msp"
	if speaker_key.is_empty() or dir_path.is_empty():
		return null

	var cache_key := speaker_key + "|" + dir_path
	if _cache.has(cache_key):
		var arr: Array = _cache[cache_key]
		if arr.size() == 0:
			return null
		return arr[randi() % arr.size()]

	var streams: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_cache[cache_key] = streams
		return null

	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var lower := f.to_lower()
			if lower.ends_with(".wav") or lower.ends_with(".ogg") or lower.ends_with(".mp3"):
				var full := dir_path.path_join(f)
				var s := load(full)
				if s is AudioStream:
					streams.append(s)
		f = dir.get_next()
	dir.list_dir_end()

	_cache[cache_key] = streams
	if streams.size() == 0:
		return null
	return streams[randi() % streams.size()]
