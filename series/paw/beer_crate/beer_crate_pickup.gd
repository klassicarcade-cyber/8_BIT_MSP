extends Node2D

# ============================================================
#  beer_crate_pickup.gd
#  Idle = frame 0 (clean crate)
#  On collect = plays clunk sound + 36 frame spill animation
# ============================================================

const CRATE_SCALE    := 0.5
const GROUND_Y       := 950.0
const MIN_X          := 200.0
const MAX_X          := 1100.0
const HFRAMES        := 6
const VFRAMES        := 6
const TOTAL_FRAMES   := 36
const ANIM_FPS       := 12.0
const COLLECT_DIST   := 120.0

# ---- path to bottle sfx — swap for a clunk later ----
const SFX_PATH := "res://series/paw/beer_crate/beer_crate_sound.wav"

var _sprite      : Sprite2D
var _sfx         : AudioStreamPlayer2D
var _collected   : bool = false
var _can_collect : bool = false
var _value_cents : int  = 100
var _animating   : bool = false
var _cur_frame   : int  = 0
var _anim_timer  : Timer = null

signal crate_collected(cents: int)

func _ready() -> void:
	_pick_random_value()
	_build_sprite()
	_build_sfx()
	z_index = 10
	var x := randf_range(MIN_X, MAX_X)
	global_position = Vector2(x, GROUND_Y)
	await get_tree().create_timer(0.5, true).timeout
	_can_collect = true
	print("🍺 Beer Crate READY — value: $%d at: %s" % [_value_cents / 100, global_position])

func _process(_delta: float) -> void:
	if _collected or not _can_collect or _animating:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= COLLECT_DIST:
		_collect()

func _collect() -> void:
	_collected = true
	_can_collect = false
	if _sfx:
		_sfx.play()
	score.add_pickup(_value_cents)
	print("🍺 Beer Crate collected! +$%d" % (_value_cents / 100))
	emit_signal("crate_collected", _value_cents)
	_play_spill_animation()

func _play_spill_animation() -> void:
	_animating = true
	_cur_frame = 0
	_anim_timer = Timer.new()
	add_child(_anim_timer)
	_anim_timer.wait_time = 1.0 / ANIM_FPS
	_anim_timer.timeout.connect(_advance_frame)
	_anim_timer.start()

func _advance_frame() -> void:
	_cur_frame += 1
	if _cur_frame >= TOTAL_FRAMES:
		_anim_timer.stop()
		_anim_timer.queue_free()
		queue_free()
		return
	_sprite.frame = _cur_frame

func _pick_random_value() -> void:
	_value_cents = randi_range(1, 10) * 100

func _build_sprite() -> void:
	var spr := Sprite2D.new()
	spr.name = "CrateSprite"
	spr.texture = load("res://series/paw/beer_crate/beer_crate_sheet.png")
	spr.hframes = HFRAMES
	spr.vframes = VFRAMES
	spr.frame   = 0
	spr.scale   = Vector2(CRATE_SCALE, CRATE_SCALE)
	spr.centered = true
	add_child(spr)
	_sprite = spr

func _build_sfx() -> void:
	if not ResourceLoader.exists(SFX_PATH):
		push_warning("BeerCrate: SFX not found at " + SFX_PATH)
		return
	_sfx = AudioStreamPlayer2D.new()
	_sfx.stream = load(SFX_PATH)
	_sfx.volume_db = 3.0   # slightly louder for the clunk effect
	add_child(_sfx)
