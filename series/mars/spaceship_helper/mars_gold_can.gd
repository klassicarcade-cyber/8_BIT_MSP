# mars_gold_can.gd
# Gold can — ONLY the spaceship helper can collect these.
# Worth $1 each. Fades out when the spaceship departs.
# Mirrors bubba_gold_pickup.gd exactly in structure.

extends Area2D

@export var value_cents:     int     = 100          # $1.00
@export var screen_size:     Vector2 = Vector2(1920, 1080)
@export var padding:         Vector2 = Vector2(80, 160)
@export var gold_color:      Color   = Color(1.0, 0.82, 0.0, 1.0)
@export var fade_duration:   float   = 0.5
@export var can_scale:       Vector2 = Vector2(0.1, 0.1)   # tune this in Inspector (~80px on screen)

@onready var spr: Sprite2D           = get_node_or_null("Sprite2D") as Sprite2D
@onready var col: CollisionShape2D   = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var pickup_sfx: AudioStreamPlayer2D = get_node_or_null("PickupSFX") as AudioStreamPlayer2D

var _collected: bool = false
var _fading:    bool = false

# Bob animation state
var _bob_offset: float = 0.0
var _bob_origin: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("mars_gold_can")
	if spr:
		spr.modulate = gold_color
		spr.scale    = can_scale
	_move_to_random_spot()
	_bob_offset = randf() * TAU
	_bob_origin = global_position


func _process(delta: float) -> void:
	if _fading or _collected:
		return
	# Gentle hover bob
	_bob_offset += delta * 2.2
	if spr:
		spr.position.y = sin(_bob_offset) * 5.0


func _move_to_random_spot() -> void:
	global_position = Vector2(
		randf_range(padding.x, screen_size.x - padding.x),
		randf_range(padding.y, screen_size.y - padding.y)
	)


# Called by the spaceship when it reaches this can
func collect() -> void:
	if _collected or _fading:
		return
	_collected = true

	if pickup_sfx and pickup_sfx.stream:
		pickup_sfx.play()

	# Use the same score autoload as the rest of the game
	score.add_pickup(value_cents)

	if col:
		col.disabled = true

	_fade_and_free()


# Called by the spaceship on departure — removes uncollected gold cans
func fade_out() -> void:
	if _fading:
		return
	_fade_and_free()


func _fade_and_free() -> void:
	_fading    = true
	monitoring = false
	monitorable = false

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)
	tw.tween_callback(queue_free)
