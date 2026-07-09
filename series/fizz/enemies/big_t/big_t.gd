# big_t.gd
# Fizz Age enemy: Big T — Bottle Hoarder
# Grabs the nearest bottle and carries it away from the player.
# Player must chase Big T to get the bottle back.
# When Big T reaches the edge of the screen he drops the bottle and resets.

extends CharacterBody2D

@export var wander_speed: float = 100.0
@export var carry_speed: float = 140.0          # faster when carrying a bottle
@export var grab_distance: float = 60.0         # how close to grab bottle
@export var drop_distance: float = 300.0        # how far from player before dropping
@export var edge_margin: float = 150.0          # distance from edge to drop bottle

@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var _target_bottle: Node2D = null
var _carrying: bool = false
var _wander_dir: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer
@onready var dash_sfx: AudioStreamPlayer = get_node_or_null("DashSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3)).normalized()
	_play_anim("idle")


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	_wander_timer -= delta

	if _carrying:
		_do_carry(delta)
	else:
		_do_hunt(delta)

	move_and_slide()
	_clamp_to_play_area()
	_update_facing()


func _do_hunt(delta: float) -> void:
	# Find nearest bottle
	_target_bottle = _find_nearest_bottle()

	if _target_bottle == null:
		# Wander
		if _wander_timer <= 0.0:
			_wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4)).normalized()
			_wander_timer = randf_range(1.5, 3.0)
		velocity = _wander_dir * wander_speed
		_play_anim("walk")
		return

	var to_bottle := _target_bottle.global_position - global_position
	var dist := to_bottle.length()

	if dist <= grab_distance:
		# GRAB IT
		_carrying = true
		_play_anim("attack")
		if steal_sfx and steal_sfx.stream:
			steal_sfx.play()
		print("BIG T GRABBED A BOTTLE!")
		# Run AWAY from player
		if player:
			_wander_dir = (global_position - player.global_position).normalized()
		return

	# Chase the bottle
	velocity = to_bottle.normalized() * wander_speed
	_play_anim("walk")


func _do_carry(delta: float) -> void:
	if _target_bottle == null or not is_instance_valid(_target_bottle):
		_carrying = false
		return

	# Drag bottle with Big T
	_target_bottle.global_position = global_position + Vector2(0, -40.0)

	# Run away from player
	if player:
		var to_player := player.global_position - global_position
		_wander_dir = -to_player.normalized()

	velocity = _wander_dir * carry_speed
	_play_anim("walk")

	# Drop bottle conditions
	var near_edge := (global_position.x < min_x + edge_margin or
		global_position.x > max_x - edge_margin or
		global_position.y < min_y + edge_margin or
		global_position.y > max_y - edge_margin)

	var player_far := player == null or global_position.distance_to(player.global_position) > drop_distance

	if near_edge or player_far:
		_drop_bottle()


func _drop_bottle() -> void:
	if _target_bottle and is_instance_valid(_target_bottle):
		if _target_bottle.has_method("reset_pickup"):
			_target_bottle.call("reset_pickup")
		print("BIG T DROPPED BOTTLE!")
	_carrying = false
	_target_bottle = null
	if dash_sfx and dash_sfx.stream:
		dash_sfx.play()


func _find_nearest_bottle() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not node.visible: continue
		var s = node.get_script()
		if s == null or not ("bottle" in s.resource_path.to_lower()): continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest


func _clamp_to_play_area() -> void:
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, min_y, max_y)


func _update_facing() -> void:
	if abs(velocity.x) < 1.0: return
	var face_left := velocity.x < 0.0
	if sprite: sprite.flip_h = face_left
	if sprite2d: sprite2d.flip_h = face_left


func _play_anim(anim_name: String) -> void:
	if sprite == null or sprite.sprite_frames == null: return
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name:
			sprite.play(anim_name)
