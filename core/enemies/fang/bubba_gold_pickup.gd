# bubba_gold_pickup.gd
# Gold pickup — only Bubba can collect these.
# Worth $1 each. Fades out when Bubba exits.
# Attach to an Area2D with a Sprite2D child.

extends Area2D

@export var value_cents: int = 100  # $1.00
@export var screen_size: Vector2 = Vector2(1920, 1080)
@export var padding: Vector2 = Vector2(80, 120)
@export var gold_color: Color = Color(1.0, 0.85, 0.0, 1.0)
@export var fade_duration: float = 0.6

@onready var spr: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var col: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var pickup_sfx: AudioStreamPlayer2D = get_node_or_null("PickupSFX") as AudioStreamPlayer2D

var _collected: bool = false
var _fading: bool = false


func _ready() -> void:
	add_to_group("bubba_pickup")
	# Apply gold tint
	if spr:
		spr.modulate = gold_color
	# Place randomly on screen
	_move_to_random_spot()


func _move_to_random_spot() -> void:
	global_position = Vector2(
		randf_range(padding.x, screen_size.x - padding.x),
		randf_range(600.0, 700.0)   # lowered to match Bubba's hand level
	)


# Called by Bubba when he reaches this pickup
func collect() -> void:
	if _collected or _fading:
		return
	_collected = true

	# Leave the group immediately so Bubba stops targeting this can
	remove_from_group("bubba_pickup")

	if pickup_sfx and pickup_sfx.stream:
		pickup_sfx.play()

	var s := get_node_or_null("/root/score")
	if s and s.has_method("add_pickup"):
		s.add_pickup(value_cents)

	if col:
		col.disabled = true

	_fade_and_free()


# Called by Bubba on exit to remove uncollected gold pickups
func fade_out() -> void:
	if _fading:
		return
	_fade_and_free()


func _fade_and_free() -> void:
	_fading = true
	monitoring = false
	monitorable = false

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)
	tw.tween_callback(queue_free)
