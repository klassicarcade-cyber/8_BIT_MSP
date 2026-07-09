# butch.gd
# Paw Paw enemy: Butch
# Behavior: Copycat — mirrors the player's movement from the opposite side
# of the screen. Steals money and drains time on contact.
# Gets closer over time, cornering the player.

extends CharacterBody2D

@export var mirror_speed: float = 220.0        # how fast Butch tracks the mirror position
@export var steal_cents: int = 20
@export var time_drain_seconds: float = 3.0
@export var drain_cooldown: float = 1.8
@export var contact_distance: float = 90.0     # how close before he steals

# Mirror offset — starts far away, shrinks over time (closing in)
@export var mirror_offset_start: float = 900.0  # initial distance from mirror point
@export var mirror_offset_min: float = 200.0    # closest he gets
@export var creep_rate: float = 15.0            # px per second he closes in

@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var can_steal: bool = true
var _mirror_offset: float = 0.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer
@onready var drain_sfx: AudioStreamPlayer = get_node_or_null("DrainSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_mirror_offset = mirror_offset_start
	_play_anim("idle")


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if player == null:
		velocity = Vector2.ZERO
		_play_anim("idle")
		move_and_slide()
		return

	# Slowly close in over time
	_mirror_offset = maxf(_mirror_offset - creep_rate * delta, mirror_offset_min)

	# Calculate mirror position — opposite side of screen from player
	var screen_center := Vector2(
		(min_x + max_x) * 0.5,
		(min_y + max_y) * 0.5
	)

	# Mirror point: reflect player position through screen center
	var mirror_point := screen_center + (screen_center - player.global_position)

	# Clamp mirror point to play area
	mirror_point.x = clampf(mirror_point.x, min_x + 60.0, max_x - 60.0)
	mirror_point.y = clampf(mirror_point.y, min_y + 60.0, max_y - 60.0)

	# Move toward mirror point
	var to_target := mirror_point - global_position
	var dist_to_target := to_target.length()

	if dist_to_target > 8.0:
		velocity = to_target.normalized() * minf(mirror_speed, dist_to_target / delta)
		_play_anim("walk")
	else:
		velocity = Vector2.ZERO
		_play_anim("idle")

	move_and_slide()
	_clamp_to_play_area()
	_update_facing_toward(player.global_position)

	# Contact check
	var dist_to_player := global_position.distance_to(player.global_position)
	if dist_to_player <= contact_distance and can_steal:
		_on_contact()


func _on_contact() -> void:
	can_steal = false
	_play_anim("attack")

	# Steal money
	var s := get_node_or_null("/root/score")
	if s:
		if s.has_method("steal"):
			s.steal(steal_cents)
		elif s.has_method("add_pickup"):
			s.add_pickup(-steal_cents)

	# Drain time
	if time_drain_seconds > 0.0:
		get_tree().call_group("timer", "subtract_time", time_drain_seconds)

	# Sound
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()
	elif drain_sfx and drain_sfx.stream:
		drain_sfx.play()

	# Flash effect
	_spawn_contact_flash()

	await get_tree().create_timer(drain_cooldown).timeout
	can_steal = true


func _spawn_contact_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)
	var flash := ColorRect.new()
	flash.color = Color(0.8, 0.1, 0.1, 0.3)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
	)


func _clamp_to_play_area() -> void:
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, min_y, max_y)


func _update_facing_toward(target: Vector2) -> void:
	# Always face toward the player (eerie effect)
	var dir_to_player := target - global_position
	if abs(dir_to_player.x) < 1.0:
		return
	var face_left := dir_to_player.x < 0.0
	if sprite:
		sprite.flip_h = face_left
	if sprite2d:
		sprite2d.flip_h = face_left


func _play_anim(anim_name: String) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name:
			sprite.play(anim_name)
