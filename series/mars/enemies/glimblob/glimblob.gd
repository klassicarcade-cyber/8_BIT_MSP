# glimblob.gd
# Mars enemy: Glimblob — THE FINALE
# Starts small and slow. Gets BIGGER and FASTER as the timer counts down.
# When huge, steals more money and has a larger steal radius.
# The closer to game over, the more dangerous it becomes.

extends CharacterBody2D

@export var base_speed: float = 100.0
@export var max_speed: float = 380.0
@export var base_scale: float = 0.6            # starts small
@export var max_scale: float = 2.2             # grows huge as time runs out
@export var base_steal_cents: int = 10
@export var max_steal_cents: int = 50          # steals much more when huge
@export var base_steal_distance: float = 60.0
@export var max_steal_distance: float = 180.0  # huge reach when big
@export var steal_cooldown: float = 1.2
@export var game_time: float = 120.0           # total game time for scaling

@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var can_steal: bool = true
var _time_remaining: float = 120.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer
@onready var chirp_sfx: AudioStreamPlayer = get_node_or_null("ChirpSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	scale = Vector2(base_scale, base_scale)
	_play_anim("idle")


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	# Get current time remaining from timer group
	var timer_nodes := get_tree().get_nodes_in_group("timer")
	if timer_nodes.size() > 0:
		var t := timer_nodes[0]
		if "time_left" in t:
			_time_remaining = float(t.time_left)

	# Calculate growth factor (0.0 = full time, 1.0 = time almost up)
	var growth := 1.0 - clampf(_time_remaining / game_time, 0.0, 1.0)

	# Apply scaling - grows as time runs out
	var current_scale := lerpf(base_scale, max_scale, growth)
	scale = scale.move_toward(Vector2(current_scale, current_scale), delta * 0.8)

	# Current stats based on growth
	var current_speed := lerpf(base_speed, max_speed, growth)
	var current_steal := int(lerpf(base_steal_cents, max_steal_cents, growth))
	var current_reach := lerpf(base_steal_distance, max_steal_distance, growth)

	# Chase player
	if player:
		var to_player := player.global_position - global_position
		var dist := to_player.length()

		if dist > current_reach:
			velocity = to_player.normalized() * current_speed
			_play_anim("walk")
		else:
			velocity = Vector2.ZERO
			_play_anim("attack")
			if can_steal:
				_do_steal(current_steal)

	move_and_slide()
	_clamp_to_play_area()
	_update_facing()

	# Pulse red tint as Glimblob grows
	if sprite and growth > 0.5:
		var red_amount := (growth - 0.5) * 2.0
		sprite.modulate = Color(1.0, 1.0 - red_amount * 0.4, 1.0 - red_amount * 0.4)


func _do_steal(cents: int) -> void:
	can_steal = false

	var s := get_node_or_null("/root/score")
	if s:
		if s.has_method("add_pickup"):
			s.add_pickup(-cents)

	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	_spawn_steal_flash()
	print("GLIMBLOB STOLE ", cents, " cents! (size=", scale.x, ")")

	await get_tree().create_timer(steal_cooldown).timeout
	can_steal = true


func _spawn_steal_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)
	var flash := ColorRect.new()
	# Flash gets more red as Glimblob grows
	var growth := 1.0 - clampf(_time_remaining / game_time, 0.0, 1.0)
	flash.color = Color(0.8, 0.2 * (1.0 - growth), 0.2 * (1.0 - growth), 0.3)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.25)
	get_tree().create_timer(0.3).timeout.connect(func():
		if is_instance_valid(canvas): canvas.queue_free()
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
