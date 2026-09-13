extends Area2D

@export var value_cents: int = 190
@export var respawn_seconds: float = 1.0

# Keep pickups from spawning partly off-screen
@export var screen_size: Vector2 = Vector2(1920, 1080)
@export var padding: Vector2 = Vector2(80, 120)

# Prevent instant pickup on start/reset
@export var collect_grace_seconds: float = 0.25

@onready var col: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var spr: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

# Bottle pickup SFX (AudioStreamPlayer2D child named "BottlePickupSFX")
@onready var pickup_sfx: AudioStreamPlayer2D = get_node_or_null("BottlePickupSFX") as AudioStreamPlayer2D

var _respawning: bool = false
var _can_collect: bool = false
var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	add_to_group("pickup")

	if spr:
		_base_scale = spr.scale

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	_apply_game_appearance()
	reset_pickup()


func _apply_game_appearance() -> void:
	if spr == null:
		return
	if CurrentGame == null or not CurrentGame.has_method("has_game") or not CurrentGame.has_game():
		return

	var gd: GameDef = CurrentGame.get_game() as GameDef
	if gd == null:
		return

	if gd.bottle_texture:
		spr.texture = gd.bottle_texture

	# Optional per-game bottle scale
	if "bottle_scale" in gd:
		spr.scale = _base_scale * gd.bottle_scale
	else:
		spr.scale = _base_scale


func _on_body_entered(body: Node2D) -> void:
	if _respawning:
		return
	if not _can_collect:
		return

	if body.is_in_group("player"):
		if pickup_sfx:
			pickup_sfx.play()

		score.add_pickup(value_cents)
		_collect_then_respawn()


func _collect_then_respawn() -> void:
	_respawning = true
	_can_collect = false

	visible = false
	monitoring = false
	monitorable = false
	if col:
		col.disabled = true

	await get_tree().create_timer(respawn_seconds, true).timeout

	_move_to_random_spot()

	reset_pickup()
	_respawning = false


func reset_pickup() -> void:
	_move_to_random_spot()

	# Keep refreshed if you ever hot-swap GameDefs
	_apply_game_appearance()

	visible = true
	monitoring = true
	monitorable = true
	if col:
		col.disabled = false

	_can_collect = false
	_start_grace_timer()


func _move_to_random_spot() -> void:
	var x := randf_range(padding.x, screen_size.x - padding.x)
	var y := randf_range(padding.y, screen_size.y - padding.y)
	global_position = Vector2(x, y)


func _start_grace_timer() -> void:
	await get_tree().create_timer(collect_grace_seconds, true).timeout
	_can_collect = true
