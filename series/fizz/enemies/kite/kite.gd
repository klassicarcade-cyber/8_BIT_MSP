# kite.gd
# Fizz Age enemy: Kite — Wind Gust
# Floats around the screen. When near the player, creates a wind push
# force that blows the player AWAY from nearby pickups.
# Has a visible wind cone showing push direction.

extends CharacterBody2D

@export var float_speed: float = 90.0
@export var push_range: float = 200.0           # range of wind push effect
@export var push_strength: float = 320.0        # force applied to player
@export var push_interval: float = 2.5          # seconds between gusts
@export var gust_duration: float = 0.4          # how long each gust lasts
@export var steal_cents: int = 10               # steal on gust contact
@export var wind_color: Color = Color(0.7, 0.9, 1.0, 0.5)

@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var _float_dir: Vector2 = Vector2.RIGHT
var _float_timer: float = 0.0
var _gust_timer: float = 0.0
var _next_gust: float = 0.0
var _is_gusting: bool = false
var _gust_dir: Vector2 = Vector2.ZERO

var _wind_canvas: CanvasLayer = null

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer
@onready var aura_sfx: AudioStreamPlayer2D = get_node_or_null("AuraSFX") as AudioStreamPlayer2D


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_float_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)).normalized()
	_next_gust = randf_range(push_interval * 0.5, push_interval)
	_build_wind_canvas()
	_play_anim("idle")
	tree_exiting.connect(_cleanup)


func _build_wind_canvas() -> void:
	_wind_canvas = CanvasLayer.new()
	_wind_canvas.layer = 48
	get_tree().root.add_child(_wind_canvas)


func _cleanup() -> void:
	if _wind_canvas and is_instance_valid(_wind_canvas):
		_wind_canvas.queue_free()


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	_float_timer -= delta

	# Gentle floating movement
	if _float_timer <= 0.0:
		_float_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)).normalized()
		_float_timer = randf_range(1.5, 3.0)

	velocity = _float_dir * float_speed
	_play_anim("walk")
	move_and_slide()
	_clamp_to_play_area()

	if global_position.x <= min_x or global_position.x >= max_x: _float_dir.x *= -1.0
	if global_position.y <= min_y or global_position.y >= max_y: _float_dir.y *= -1.0

	_update_facing()

	# Gust timing
	if _is_gusting:
		_gust_timer -= delta
		_do_gust(delta)
		if _gust_timer <= 0.0:
			_is_gusting = false
		return

	_next_gust -= delta
	if _next_gust <= 0.0 and player:
		var dist := global_position.distance_to(player.global_position)
		if dist <= push_range:
			_trigger_gust()


func _trigger_gust() -> void:
	if player == null: return
	_is_gusting = true
	_gust_timer = gust_duration
	_next_gust = push_interval
	# Push direction: away from Kite
	_gust_dir = (player.global_position - global_position).normalized()
	_play_anim("attack")
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()
	_spawn_wind_particles()
	print("KITE WIND GUST!")


func _do_gust(delta: float) -> void:
	if player == null: return
	# Apply push force to player via velocity if it has one
	if player is CharacterBody2D:
		var pb := player as CharacterBody2D
		pb.velocity += _gust_dir * push_strength * delta

	# Steal on close contact
	var dist := global_position.distance_to(player.global_position)
	if dist <= 80.0:
		var s := get_node_or_null("/root/score")
		if s and s.has_method("add_pickup"):
			s.add_pickup(-steal_cents)


func _spawn_wind_particles() -> void:
	if _wind_canvas == null: return
	var screen_pos := get_viewport().get_canvas_transform() * global_position
	var screen_dir := _gust_dir

	for i in range(12):
		var dot := ColorRect.new()
		var w := randf_range(8.0, 20.0)
		var h := randf_range(3.0, 6.0)
		dot.size = Vector2(w, h)
		dot.color = wind_color
		var perp := Vector2(-screen_dir.y, screen_dir.x)
		var spread := perp * randf_range(-60.0, 60.0)
		dot.position = screen_pos + spread
		_wind_canvas.add_child(dot)

		var dist := randf_range(150.0, 350.0)
		var target := screen_pos + screen_dir * dist + spread
		var duration := randf_range(0.3, 0.6)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "position", target, duration).set_ease(Tween.EASE_OUT)
		tw.tween_property(dot, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)

	get_tree().create_timer(0.7).timeout.connect(func():
		# Clean up wind particles from canvas
		for child in _wind_canvas.get_children():
			if is_instance_valid(child):
				child.queue_free()
	)


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
