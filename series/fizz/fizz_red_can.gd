# fizz_red_can.gd
# Red soda can — ONLY the Fizz pterodactyl can collect these.
# Worth $1 each. Fades out when the pterodactyl departs.
# Mirrors mars_gold_can.gd and bubba_gold_pickup.gd exactly in structure.

extends Area2D

@export var value_cents:   int     = 100
@export var screen_size:   Vector2 = Vector2(1920, 1080)
@export var padding:       Vector2 = Vector2(80, 160)
@export var fade_duration: float   = 0.5
@export var anim_fps:      float   = 6.0   # how fast the face animates

@onready var spr: Sprite2D           = get_node_or_null("Sprite2D") as Sprite2D
@onready var col: CollisionShape2D   = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var pickup_sfx: AudioStreamPlayer2D = get_node_or_null("PickupSFX") as AudioStreamPlayer2D

var _collected:    bool  = false
var _fading:       bool  = false
var _bob_offset:   float = 0.0
var _frame_timer:  float = 0.0
var _frame_index:  int   = 0

# 2x2 sheet: frames 0,1,2,3 left-to-right top-to-bottom
const FRAME_COUNT := 4


func _ready() -> void:
	add_to_group("fizz_red_can")
	_move_to_ground_spot()
	# Randomise start frame so cans don't all animate in sync
	_bob_offset   = randf() * TAU
	_frame_index  = randi() % FRAME_COUNT
	_frame_timer  = randf() / anim_fps


func _process(delta: float) -> void:
	if _fading or _collected:
		return

	# Gentle idle bob
	_bob_offset += delta * 2.0
	if spr:
		spr.position.y = sin(_bob_offset) * 4.0

	# Cycle through the 4 face frames
	_frame_timer += delta
	if _frame_timer >= 1.0 / anim_fps:
		_frame_timer = 0.0
		_frame_index = (_frame_index + 1) % FRAME_COUNT
		if spr:
			spr.frame = _frame_index


func _move_to_ground_spot() -> void:
	global_position = Vector2(
		randf_range(padding.x, screen_size.x - padding.x),
		randf_range(700.0, 850.0)
	)


# Called by the pterodactyl when it reaches this can
func collect() -> void:
	if _collected or _fading:
		return
	_collected = true
	remove_from_group("fizz_red_can")

	if pickup_sfx and pickup_sfx.stream:
		pickup_sfx.play()

	score.add_pickup(value_cents)

	if col:
		col.disabled = true

	_fade_and_free()


# Called by the pterodactyl on departure — removes uncollected cans
func fade_out() -> void:
	if _fading:
		return
	_fade_and_free()


func _fade_and_free() -> void:
	_fading     = true
	monitoring  = false
	monitorable = false

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)
	tw.tween_callback(queue_free)
