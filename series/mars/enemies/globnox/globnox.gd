# globnox.gd
# Mars enemy: Globnox — Gravity Well
# So massive it creates a gravity field that slowly pulls ALL pickups toward it.
# Player must grab pickups before they drift into Globnox's reach.
# Also drains time when player gets too close.

extends CharacterBody2D

@export var move_speed: float = 60.0            # very slow, lumbering
@export var gravity_range: float = 500.0        # pickup pull range
@export var gravity_strength: float = 80.0      # pull speed px/sec
@export var danger_distance: float = 100.0      # player distance for time drain
@export var time_drain_seconds: float = 4.0
@export var drain_cooldown: float = 2.0
@export var absorb_distance: float = 55.0       # pickup gets reset when this close
@export var pulse_interval: float = 3.0         # seconds between gravity pulses

@export var min_x: float = 200.0
@export var max_x: float = 1720.0
@export var min_y: float = 150.0
@export var max_y: float = 850.0

var frozen: bool = false
var player: Node2D = null
var can_drain: bool = true
var _wander_dir: Vector2 = Vector2.RIGHT
var _pulse_timer: float = 0.0
var _gravity_canvas: CanvasLayer = null

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("FizzStealSFX") as AudioStreamPlayer
@onready var chirp_sfx: AudioStreamPlayer = get_node_or_null("FizzChirpSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3)).normalized()
	_pulse_timer = pulse_interval
	_play_anim("idle")
	_build_gravity_visual()
	tree_exiting.connect(_cleanup)


func _build_gravity_visual() -> void:
	_gravity_canvas = CanvasLayer.new()
	_gravity_canvas.layer = 47
	get_tree().root.add_child(_gravity_canvas)


func _cleanup() -> void:
	if _gravity_canvas and is_instance_valid(_gravity_canvas):
		_gravity_canvas.queue_free()


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	# Slow lumbering wander
	velocity = _wander_dir * move_speed
	_play_anim("walk")
	move_and_slide()
	_clamp_to_play_area()

	# Bounce off walls
	if global_position.x <= min_x or global_position.x >= max_x:
		_wander_dir.x *= -1.0
	if global_position.y <= min_y or global_position.y >= max_y:
		_wander_dir.y *= -1.0

	# Update facing
	if abs(velocity.x) > 1.0:
		if sprite: sprite.flip_h = velocity.x > 0.0
		if sprite2d: sprite2d.flip_h = velocity.x > 0.0

	# Gravity pulse visual
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_pulse_timer = pulse_interval
		_spawn_gravity_pulse()

	# Pull all nearby pickups toward Globnox
	_pull_pickups(delta)

	# Time drain when player too close
	if player:
		var dist := global_position.distance_to(player.global_position)
		if dist <= danger_distance and can_drain:
			_drain_time()


func _pull_pickups(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not node.visible:
			continue
		if not node is Node2D:
			continue
		var pickup := node as Node2D
		var to_self := global_position - pickup.global_position
		var dist := to_self.length()

		if dist > gravity_range:
			continue

		# Pull strength increases as pickup gets closer
		var strength := gravity_strength * (1.0 - dist / gravity_range) * delta
		pickup.global_position += to_self.normalized() * strength * 2.5

		# Absorb (reset) if too close
		if dist <= absorb_distance:
			if pickup.has_method("reset_pickup"):
				pickup.call("reset_pickup")
			if steal_sfx and steal_sfx.stream:
				steal_sfx.play()
			_spawn_absorb_flash(pickup.global_position)


func _drain_time() -> void:
	can_drain = false
	get_tree().call_group("timer", "subtract_time", time_drain_seconds)
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()
	_play_anim("attack")
	print("GLOBNOX TIME DRAIN!")
	get_tree().create_timer(drain_cooldown).timeout.connect(func(): can_drain = true)


func _spawn_gravity_pulse() -> void:
	# Expanding ring showing gravity field
	var canvas := CanvasLayer.new()
	canvas.layer = 47
	get_tree().root.add_child(canvas)
	var screen_pos := get_viewport().get_canvas_transform() * global_position
	var screen_radius := gravity_range * get_viewport().get_canvas_transform().get_scale().x

	var ring := Node2D.new()
	canvas.add_child(ring)

	# Draw ring as many small dots
	var dot_count := 24
	for i in range(dot_count):
		var angle := (TAU / dot_count) * i
		var dot := ColorRect.new()
		dot.size = Vector2(5, 5)
		dot.color = Color(0.4, 0.8, 1.0, 0.6)
		dot.position = screen_pos + Vector2(cos(angle), sin(angle)) * 20.0
		canvas.add_child(dot)
		var target := screen_pos + Vector2(cos(angle), sin(angle)) * screen_radius
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "position", target, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(dot, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)

	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(canvas): canvas.queue_free()
	)


func _spawn_absorb_flash(pos: Vector2) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 51
	get_tree().root.add_child(canvas)
	var screen_pos := get_viewport().get_canvas_transform() * pos
	for i in range(6):
		var dot := ColorRect.new()
		dot.size = Vector2(7, 7)
		dot.color = Color(0.4, 0.8, 1.0, 1.0)
		dot.position = screen_pos
		canvas.add_child(dot)
		var angle := (TAU / 6.0) * i
		var target := screen_pos + Vector2(cos(angle), sin(angle)) * 40.0
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


func _play_anim(anim_name: String) -> void:
	if sprite == null or sprite.sprite_frames == null: return
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name:
			sprite.play(anim_name)
