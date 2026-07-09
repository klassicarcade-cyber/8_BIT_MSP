# redwolf.gd
# Paw Paw enemy: Red Wolf
# Behavior: Hunts the nearest bottle and shatters it with his spear.
# Does NOT steal money - bottle destruction is his threat.

extends CharacterBody2D

@export var speed: float = 180.0
@export var charge_speed: float = 340.0       # speed when lunging at bottle
@export var aggro_range: float = 600.0
@export var stop_distance: float = 12.0

@export var spear_range: float = 60.0         # how close to bottle before he strikes
@export var strike_cooldown: float = 2.0      # pause after each strike
@export var shard_count: int = 8              # number of shatter particles

var player: Node2D = null
var aggro_locked: bool = false
var can_strike: bool = true
var frozen: bool = false

enum State { IDLE, HUNT, CHARGE, STRIKE, COOLDOWN }
var _state: State = State.IDLE
var _target_bottle: Node2D = null
var _cooldown_timer: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _charge_timer: float = 0.0

@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer
@onready var chirp_sfx: AudioStreamPlayer = get_node_or_null("ChirpSFX") as AudioStreamPlayer


func _ready() -> void:
	print("REDWOLF LOADED")
	add_to_group("enemy")
	call_deferred("_find_player")
	if anim:
		anim.visible = true
		play_anim("idle")
	elif sprite:
		sprite.visible = true


func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	print("Redwolf player found: ", player)


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		play_anim("idle")
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if player == null:
		velocity = Vector2.ZERO
		play_anim("idle")
		move_and_slide()
		return

	# Aggro trigger
	var dist_to_player := global_position.distance_to(player.global_position)
	if not aggro_locked and dist_to_player <= aggro_range:
		aggro_locked = true
		print("REDWOLF aggro LOCKED")

	if not aggro_locked:
		velocity = Vector2.ZERO
		play_anim("idle")
		move_and_slide()
		return

	match _state:
		State.IDLE, State.HUNT:
			_do_hunt(delta)

		State.CHARGE:
			_do_charge(delta)

		State.STRIKE:
			velocity = Vector2.ZERO
			move_and_slide()

		State.COOLDOWN:
			_cooldown_timer -= delta
			velocity = Vector2.ZERO
			play_anim("idle")
			move_and_slide()
			if _cooldown_timer <= 0.0:
				_state = State.HUNT


func _do_hunt(delta: float) -> void:
	# Find nearest visible bottle
	_target_bottle = _find_nearest_bottle()

	if _target_bottle == null:
		# No bottles — wander toward player
		var to_player := player.global_position - global_position
		if to_player.length() > stop_distance:
			velocity = to_player.normalized() * speed
			play_anim("walk")
		else:
			velocity = Vector2.ZERO
			play_anim("idle")
		move_and_slide()
		update_facing()
		return

	var to_bottle := _target_bottle.global_position - global_position
	var dist := to_bottle.length()

	if dist <= spear_range and can_strike:
		# Close enough — initiate charge/strike
		_charge_dir = to_bottle.normalized()
		_charge_timer = 0.15
		_state = State.CHARGE
		play_anim("attack")
		return

	# Move toward bottle
	velocity = to_bottle.normalized() * speed
	play_anim("walk")
	move_and_slide()
	update_facing()


func _do_charge(delta: float) -> void:
	# Quick lunge toward bottle
	_charge_timer -= delta
	velocity = _charge_dir * charge_speed
	move_and_slide()
	update_facing()

	# Check if we hit the bottle
	if _target_bottle and is_instance_valid(_target_bottle):
		var dist := global_position.distance_to(_target_bottle.global_position)
		if dist <= spear_range:
			_shatter_bottle(_target_bottle)
			_target_bottle = null
			_state = State.COOLDOWN
			_cooldown_timer = strike_cooldown
			can_strike = false
			get_tree().create_timer(strike_cooldown).timeout.connect(func(): can_strike = true)
			return

	if _charge_timer <= 0.0:
		_state = State.HUNT


func _find_nearest_bottle() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not node.visible:
			continue
		var node_script = node.get_script()
		if node_script == null:
			continue
		if not ("bottle" in node_script.resource_path.to_lower()):
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest


func _shatter_bottle(bottle: Node2D) -> void:
	print("REDWOLF SHATTERED bottle!")
	play_anim("attack")

	# Play sound
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	# Spawn shard particles
	_spawn_shards(bottle.global_position)

	# Reset the bottle (teleport to new spot)
	if bottle.has_method("reset_pickup"):
		bottle.call("reset_pickup")


func _spawn_shards(pos: Vector2) -> void:
	# Create flying shard pieces using small ColorRects on a CanvasLayer
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)

	# Clean up canvas after shards finish
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
	)

	for i in range(shard_count):
		var shard := ColorRect.new()
		shard.size = Vector2(randf_range(6, 14), randf_range(3, 8))
		shard.color = Color(0.7, 0.9, 1.0, 0.9)  # glass-blue tint
		shard.position = pos + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		canvas.add_child(shard)

		# Animate each shard flying outward
		var angle := (TAU / shard_count) * i + randf_range(-0.4, 0.4)
		var dist := randf_range(60.0, 160.0)
		var target := pos + Vector2(cos(angle), sin(angle)) * dist
		var duration := randf_range(0.3, 0.55)

		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "position", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)


func play_anim(anim_name: String) -> void:
	if anim == null or anim.sprite_frames == null:
		return
	if not anim.sprite_frames.has_animation(anim_name):
		return
	if anim.animation == anim_name:
		return
	anim.play(anim_name)


func update_facing() -> void:
	if anim and velocity.x != 0.0:
		anim.flip_h = velocity.x > 0.0
	if sprite and velocity.x != 0.0:
		sprite.flip_h = velocity.x > 0.0
