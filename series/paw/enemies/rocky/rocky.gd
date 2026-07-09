# rocky.gd
# Paw Paw enemy: Rocky
# Behavior: Wanders slowly. Periodically stomps the ground causing screen shake
# and scrambling ALL pickup positions. Heavy and unpredictable.

extends CharacterBody2D

@export var move_speed: float = 90.0           # slow heavy wander
@export var stomp_interval_min: float = 4.0    # seconds between stomps
@export var stomp_interval_max: float = 8.0
@export var stomp_warning_duration: float = 1.2  # wind-up time before stomp
@export var shake_strength: float = 12.0       # camera shake intensity
@export var shake_duration: float = 0.4
@export var stomp_radius: float = 350.0        # scrambles pickups within this radius
@export var scramble_all: bool = true          # if true, scrambles ALL pickups not just nearby

@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var wander_dir: Vector2 = Vector2.RIGHT

var _stomp_timer: float = 0.0
var _next_stomp_time: float = 0.0
var _is_winding_up: bool = false
var _wind_up_timer: float = 0.0

# Warning ring drawn on screen before stomp
var _warning_canvas: CanvasLayer = null
var _warning_ring: Node2D = null

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4)).normalized()
	if wander_dir == Vector2.ZERO:
		wander_dir = Vector2.RIGHT
	_next_stomp_time = randf_range(stomp_interval_min, stomp_interval_max)
	_play_anim("idle")
	_build_warning_ring()
	tree_exiting.connect(_cleanup)


func _build_warning_ring() -> void:
	_warning_canvas = CanvasLayer.new()
	_warning_canvas.layer = 48
	get_tree().root.add_child(_warning_canvas)
	_warning_ring = Node2D.new()
	_warning_ring.visible = false
	_warning_canvas.add_child(_warning_ring)


func _cleanup() -> void:
	if _warning_canvas and is_instance_valid(_warning_canvas):
		_warning_canvas.queue_free()


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_hide_warning()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	# --- STOMP TIMING ---
	if _is_winding_up:
		_wind_up_timer -= delta
		velocity = Vector2.ZERO
		_play_anim("attack")

		# Pulse warning ring
		if _warning_ring:
			var pulse := 0.5 + 0.5 * sin(_wind_up_timer * 12.0)
			_warning_ring.modulate = Color(1.0, 0.4, 0.1, 0.4 + 0.4 * pulse)
			var screen_pos := get_viewport().get_canvas_transform() * global_position
			_warning_ring.position = screen_pos
			_warning_ring.visible = true

		if _wind_up_timer <= 0.0:
			_is_winding_up = false
			_do_stomp()
		move_and_slide()
		return

	_stomp_timer += delta
	_hide_warning()

	if _stomp_timer >= _next_stomp_time:
		_stomp_timer = 0.0
		_next_stomp_time = randf_range(stomp_interval_min, stomp_interval_max)
		_is_winding_up = true
		_wind_up_timer = stomp_warning_duration
		return

	# --- WANDER ---
	velocity = wander_dir * move_speed
	_play_anim("walk")

	move_and_slide()
	_clamp_to_play_area()
	_update_facing()

	# Bounce off walls
	if global_position.x <= min_x or global_position.x >= max_x:
		wander_dir.x *= -1.0
	if global_position.y <= min_y or global_position.y >= max_y:
		wander_dir.y *= -1.0

	# Occasionally change direction
	if randf() < 0.003:
		wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4)).normalized()


func _do_stomp() -> void:
	print("ROCKY STOMPS!")
	_play_anim("attack")
	_hide_warning()

	# Camera shake
	get_tree().call_group("camera", "shake", shake_strength, shake_duration)

	# Play stomp sound
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	# Screen flash
	_spawn_stomp_flash()

	# Scramble pickups
	var pickups := get_tree().get_nodes_in_group("pickup")
	for pickup in pickups:
		if pickup == null or not pickup.visible:
			continue
		if scramble_all:
			if pickup.has_method("reset_pickup"):
				pickup.call("reset_pickup")
		else:
			var d := global_position.distance_to(pickup.global_position)
			if d <= stomp_radius:
				if pickup.has_method("reset_pickup"):
					pickup.call("reset_pickup")

	# Spawn shockwave ring effect
	_spawn_shockwave()


func _spawn_stomp_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 51
	get_tree().root.add_child(canvas)

	var flash := ColorRect.new()
	flash.color = Color(0.9, 0.6, 0.1, 0.35)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)

	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
	)


func _spawn_shockwave() -> void:
	# Expanding ring of particles from Rocky's feet
	var canvas := CanvasLayer.new()
	canvas.layer = 49
	get_tree().root.add_child(canvas)

	var screen_pos := get_viewport().get_canvas_transform() * global_position

	var particle_count := 12
	for i in range(particle_count):
		var dot := ColorRect.new()
		dot.size = Vector2(10, 10)
		dot.color = Color(0.9, 0.6, 0.1, 0.9)
		dot.position = screen_pos
		canvas.add_child(dot)

		var angle := (TAU / particle_count) * i
		var target := screen_pos + Vector2(cos(angle), sin(angle)) * 200.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "position", target, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(dot, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)

	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
	)


func _hide_warning() -> void:
	if _warning_ring:
		_warning_ring.visible = false


func _clamp_to_play_area() -> void:
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, min_y, max_y)


func _update_facing() -> void:
	if abs(velocity.x) < 1.0:
		return
	var face_left := velocity.x < 0.0
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
