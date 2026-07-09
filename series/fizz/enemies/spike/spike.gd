# spike.gd
# Fizz Age enemy: Spike — Spike Trap
# Plants himself and launches spike projectiles in 4 directions periodically.
# Any pickup hit by a spike gets reset. Player hit by spike loses time.
# Occasionally repositions to a new spot.

extends CharacterBody2D

@export var move_speed: float = 130.0
@export var fire_interval: float = 2.5          # seconds between spike volleys
@export var spike_speed: float = 400.0          # projectile speed
@export var spike_range: float = 600.0          # how far spikes travel
@export var time_drain_seconds: float = 3.0     # time lost if player hit
@export var reposition_interval: float = 8.0    # move to new spot every N seconds
@export var spike_color: Color = Color(1.0, 0.5, 0.1, 1.0)

@export var min_x: float = 200.0
@export var max_x: float = 1720.0
@export var min_y: float = 150.0
@export var max_y: float = 850.0

var frozen: bool = false
var player: Node2D = null
var _planted: bool = false
var _fire_timer: float = 0.0
var _reposition_timer: float = 0.0
var _move_target: Vector2 = Vector2.ZERO
var _is_moving: bool = false

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("FizzStealSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_move_target = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
	_is_moving = true
	_fire_timer = fire_interval
	_reposition_timer = reposition_interval
	_play_anim("walk")


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if _is_moving:
		_do_move(delta)
		return

	# Planted - fire spikes
	velocity = Vector2.ZERO
	move_and_slide()
	_play_anim("idle")

	_fire_timer -= delta
	_reposition_timer -= delta

	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_fire_spikes()

	if _reposition_timer <= 0.0:
		_reposition_timer = reposition_interval
		_pick_new_position()


func _do_move(delta: float) -> void:
	var to_target := _move_target - global_position
	var dist := to_target.length()
	if dist <= 10.0:
		_is_moving = false
		_planted = true
		velocity = Vector2.ZERO
		_play_anim("idle")
		return
	velocity = to_target.normalized() * move_speed
	_play_anim("walk")
	move_and_slide()
	_clamp_to_play_area()
	_update_facing()


func _pick_new_position() -> void:
	_move_target = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
	_is_moving = true
	_play_anim("walk")


func _fire_spikes() -> void:
	_play_anim("attack")
	print("SPIKE FIRES!")

	# Fire in 4 directions + 4 diagonals = 8 spikes
	var directions := [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()
	]

	for dir in directions:
		_launch_spike(dir)


func _launch_spike(dir: Vector2) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 49
	get_tree().root.add_child(canvas)

	var spike := ColorRect.new()
	spike.size = Vector2(16, 6)
	spike.color = spike_color
	var start_screen := get_viewport().get_canvas_transform() * global_position
	spike.position = start_screen
	canvas.add_child(spike)

	# Rotate spike visual to match direction
	spike.pivot_offset = spike.size * 0.5
	spike.rotation = dir.angle()

	var end_screen := start_screen + dir * spike_range
	var duration := spike_range / spike_speed

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spike, "position", end_screen, duration).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(spike, "modulate:a", 0.0, duration * 0.8).set_ease(Tween.EASE_IN)

	# Check hits during travel using a separate process
	_check_spike_hits(dir, start_screen, duration)

	get_tree().create_timer(duration + 0.1).timeout.connect(func():
		if is_instance_valid(canvas): canvas.queue_free()
	)


func _check_spike_hits(dir: Vector2, start_screen: Vector2, duration: float) -> void:
	var elapsed := 0.0
	var check_interval := 0.05

	while elapsed < duration:
		await get_tree().create_timer(check_interval).timeout
		elapsed += check_interval

		var current_screen := start_screen + dir * spike_speed * elapsed
		var world_pos := get_viewport().get_canvas_transform().affine_inverse() * current_screen

		# Check pickups
		for node in get_tree().get_nodes_in_group("pickup"):
			if node == null or not node.visible or not node is Node2D: continue
			if world_pos.distance_to((node as Node2D).global_position) < 40.0:
				if node.has_method("reset_pickup"):
					node.call("reset_pickup")

		# Check player
		if player and world_pos.distance_to(player.global_position) < 50.0:
			get_tree().call_group("timer", "subtract_time", time_drain_seconds)
			if steal_sfx and steal_sfx.stream:
				steal_sfx.play()
			_spawn_hit_flash(current_screen)
			return


func _spawn_hit_flash(screen_pos: Vector2) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 51
	get_tree().root.add_child(canvas)
	for i in range(6):
		var dot := ColorRect.new()
		dot.size = Vector2(8, 8)
		dot.color = spike_color
		dot.position = screen_pos
		canvas.add_child(dot)
		var angle := (TAU / 6.0) * i
		var target := screen_pos + Vector2(cos(angle), sin(angle)) * 50.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "position", target, 0.25).set_ease(Tween.EASE_OUT)
		tw.tween_property(dot, "modulate:a", 0.0, 0.25)
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
