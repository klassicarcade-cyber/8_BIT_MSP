# res://core/autoloads/marquee_window.gd
# ─────────────────────────────────────────────────────────────────────
# MarqueeWindow — Autoload
#
# Opens a borderless fullscreen window on monitor 2 and displays
# the current game's marquee image.
#
# SETUP:
#   1. Copy this file to  res://core/autoloads/marquee_window.gd
#   2. In Godot: Project → Project Settings → Autoload
#      Name: MarqueeWindow
#      Path: res://core/autoloads/marquee_window.gd
#   3. Place your 4 marquee images in  res://ui/marquee/:
#      gobles.png  |  pawpaw.png  |  mars.png  |  fizz.png
#
# HOW IT WORKS:
#   • On startup it opens a second window on monitor 2
#   • While on the game select screen it cycles through all 4 marquees
#     every 5 seconds
#   • When a game starts it immediately shows that game's marquee
#   • When the player returns to select screen the cycle resumes
#
# SIGNALS TO CALL FROM YOUR GAME:
#   MarqueeWindow.show_game_marquee("Gobles")   # or Paw Paw / mars / Fizz
#   MarqueeWindow.show_idle_cycle()              # call when returning to select
# ─────────────────────────────────────────────────────────────────────
extends Node

# ╔══════════════════════════════════════════════════════╗
# ║  CONFIG — adjust these if needed                     ║
# ╚══════════════════════════════════════════════════════╝
const MARQUEE_DIR      := "res://ui/marquee/"
const CYCLE_SECONDS    := 5.0
const MONITOR_INDEX    := 1          # 0 = primary, 1 = second monitor
const MARQUEE_W        := 1920
const MARQUEE_H        := 1080
const FADE_DURATION    := 0.4        # crossfade time in seconds

# Maps game_id (as used in your .tres files) → image filename
const GAME_MARQUEES := {
	"Gobles"  : "gobles.png",
	"Paw Paw" : "pawpaw.png",
	"mars"    : "mars.png",
	"Fizz"    : "fizz.png",
}

const CYCLE_ORDER := ["Gobles", "Paw Paw", "mars", "Fizz"]

# ─────────────────────────────────────────────────────────────────────
var _window:      Window       = null
var _bg:          ColorRect    = null   # black background
var _img_a:       TextureRect  = null   # current visible image
var _img_b:       TextureRect  = null   # image fading in
var _timer:       float        = 0.0
var _cycle_index: int          = 0
var _is_idle:     bool         = true
var _textures:    Dictionary   = {}     # preloaded Texture2D per game_id


func _ready() -> void:
	_preload_textures()
	_open_marquee_window()


func _process(delta: float) -> void:
	if not _is_idle:
		return
	_timer -= delta
	if _timer <= 0.0:
		_cycle_index = (_cycle_index + 1) % CYCLE_ORDER.size()
		_show_texture(_textures.get(CYCLE_ORDER[_cycle_index]))
		_timer = CYCLE_SECONDS


# ─────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────

## Call this when a game starts playing.
## game_id must match a key in GAME_MARQUEES exactly.
func show_game_marquee(game_id: String) -> void:
	_is_idle = false
	_timer   = 0.0
	var tex: Texture2D = _textures.get(game_id)
	if tex == null:
		push_warning("MarqueeWindow: no marquee found for game_id '%s'" % game_id)
		return
	_show_texture(tex)


## Call this when returning to the game select screen.
func show_idle_cycle() -> void:
	_is_idle     = true
	_cycle_index = 0
	_timer       = CYCLE_SECONDS
	_show_texture(_textures.get(CYCLE_ORDER[0]))


# ─────────────────────────────────────────────────────────────────────
# Window setup
# ─────────────────────────────────────────────────────────────────────
func _open_marquee_window() -> void:
	var screen_count := DisplayServer.get_screen_count()
	if screen_count < 2:
		push_warning("MarqueeWindow: only one monitor detected — marquee window skipped.")
		push_warning("MarqueeWindow: connect a second monitor and restart.")
		return

	_window = Window.new()
	_window.title            = "MSP Marquee"
	_window.size             = Vector2i(MARQUEE_W, MARQUEE_H)
	_window.borderless       = true
	_window.always_on_top    = true
	_window.transparent      = false
	_window.unresizable      = true
	_window.unfocusable      = true       # keeps focus on the game window

	# Position on the second monitor
	var monitor_pos  := DisplayServer.screen_get_position(MONITOR_INDEX)
	_window.position  = monitor_pos

	get_tree().root.add_child(_window)
	_window.show()

	# Black background so there's no flash before first image loads
	_bg            = ColorRect.new()
	_bg.color      = Color.BLACK
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.add_child(_bg)

	# Two TextureRects for crossfading
	_img_a = _make_image_rect()
	_img_b = _make_image_rect()
	_img_b.modulate.a = 0.0   # start invisible
	_window.add_child(_img_a)
	_window.add_child(_img_b)

	# Start idle cycle immediately
	show_idle_cycle()


func _make_image_rect() -> TextureRect:
	var tr          := TextureRect.new()
	tr.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	return tr


# ─────────────────────────────────────────────────────────────────────
# Display helpers
# ─────────────────────────────────────────────────────────────────────
func _show_texture(tex: Texture2D) -> void:
	if _img_a == null or _img_b == null:
		return
	if tex == null:
		return

	# Load new image into the hidden layer and fade it in
	_img_b.texture    = tex
	_img_b.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_img_b, "modulate:a", 1.0, FADE_DURATION)
	tween.tween_property(_img_a, "modulate:a", 0.0, FADE_DURATION)
	tween.chain().tween_callback(func() -> void:
		# Swap: b becomes the visible layer, a becomes the hidden one
		_img_a.texture    = _img_b.texture
		_img_a.modulate.a = 1.0
		_img_b.modulate.a = 0.0
	)


func _preload_textures() -> void:
	for game_id in GAME_MARQUEES:
		var path: String = MARQUEE_DIR + GAME_MARQUEES[game_id]
		if ResourceLoader.exists(path):
			_textures[game_id] = load(path)
		else:
			push_warning("MarqueeWindow: missing marquee image at '%s'" % path)
