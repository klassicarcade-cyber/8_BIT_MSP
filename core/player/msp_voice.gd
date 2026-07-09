extends Node2D

# --------------------------------------------------
# MSP VOICE: Mr Soda Pop shout/callout controller
# Godot 4.x
#
# Drop-in script for MSPVoice node (a child of Player).
#
# Nodes expected under MSPVoice:
# - ShoutPlayer (AudioStreamPlayer2D)  [required]
# - ShoutLabel  (Label)               [optional]
#
# Folder layout expected:
# res://series/<pack>/voice/msp/
#   msp_01.wav, msp_02.wav, ... (any .wav/.ogg/.mp3)
# --------------------------------------------------

# Voice folder for this game pack
@export var voice_dir: String = "res://series/gob/voice/msp"

# Idle/random shouts (OFF by default so it won't talk when game isn't playing)
@export var allow_idle_shouts: bool = false
@export var shout_delay_min: float = 1.2
@export var shout_delay_max: float = 2.2
@export var shout_chance: float = 0.75

# Audio shaping
@export var shout_volume_db: float = -2.0
@export var pitch_min: float = 0.90
@export var pitch_max: float = 1.08

# Optional subtitles
@export var shout_texts: Array[String] = []
@export var local_subtitles: bool = false

@onready var shout_player: AudioStreamPlayer2D = get_node_or_null("ShoutPlayer") as AudioStreamPlayer2D
@onready var shout_label: Label = get_node_or_null("ShoutLabel") as Label

var shout_clips: Array[AudioStream] = []
var frozen: bool = false


func _ready() -> void:
	if shout_label:
		shout_label.visible = false

	_load_shout_clips()

	# Idle/random shout is controlled and OFF by default
	if allow_idle_shouts and shout_clips.size() > 0 and randf() <= shout_chance:
		call_deferred("_schedule_shout")


# --------------------------------------------------
# PUBLIC API (other scripts call these)
# --------------------------------------------------

# Play one shout right now (safe to call repeatedly).
func play_now() -> void:
	_play_random_shout()


# Play one shout right now, but only if not already playing a voice line.
func play_now_if_free() -> void:
	if shout_player and shout_player.playing:
		return
	_play_random_shout()


# --------------------------------------------------
# INTERNALS
# --------------------------------------------------
func _load_shout_clips() -> void:
	# Reload each time in case you swap packs/folders while developing.
	shout_clips.clear()

	if voice_dir.is_empty():
		print("MSPVoice: voice_dir is empty")
		return

	var dir := DirAccess.open(voice_dir)
	if dir == null:
		print("MSPVoice: cannot open voice_dir:", voice_dir)
		return

	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var lower := f.to_lower()
			if lower.ends_with(".wav") or lower.ends_with(".ogg") or lower.ends_with(".mp3"):
				var full := voice_dir.path_join(f)
				if ResourceLoader.exists(full):
					var snd := load(full) as AudioStream
					if snd:
						shout_clips.append(snd)
		f = dir.get_next()
	dir.list_dir_end()

	if shout_clips.is_empty():
		print("MSPVoice: no voice clips found in:", voice_dir)
	else:
		print("MSPVoice: loaded", shout_clips.size(), "clips from", voice_dir)


func _schedule_shout() -> void:
	var d := randf_range(shout_delay_min, shout_delay_max)
	await get_tree().create_timer(d).timeout
	if frozen:
		return
	_play_random_shout()


func _play_random_shout() -> void:
	if frozen:
		return
	if shout_player == null:
		print("MSPVoice: ShoutPlayer node missing")
		return
	if shout_clips.is_empty():
		return

	var i := randi() % shout_clips.size()

	shout_player.stop()
	shout_player.stream = shout_clips[i]
	shout_player.volume_db = shout_volume_db
	shout_player.pitch_scale = randf_range(pitch_min, pitch_max)
	shout_player.play()

	if local_subtitles and shout_label:
		var line := ""
		if i < shout_texts.size():
			line = shout_texts[i]
		if line != "":
			_show_subtitle(line)


func _show_subtitle(text: String) -> void:
	if shout_label == null:
		return

	shout_label.text = text
	shout_label.visible = true
	shout_label.modulate.a = 1.0

	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(shout_label, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		if shout_label:
			shout_label.visible = false
			shout_label.modulate.a = 1.0
	)
