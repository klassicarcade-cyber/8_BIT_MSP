# chickenleg.gd
# Paw Paw enemy: Chicken Leg — THE FINALE
# Behavior: Gets faster as player's score rises.
# Teleports next to player periodically — completely unpredictable.
# Steals money and drains time on contact.

extends CharacterBody2D

# --- CHASE ---
@export var base_speed: float = 120.0          # starting chase speed
@export var max_speed: float = 420.0           # top speed at high score
@export var speed_per_dollar: float = 8.0      # extra speed per $1.00 scored

# --- TELEPORT ---
@export var teleport_interval_min: float = 5.0
@export var teleport_interval_max: float = 10.0
@export var teleport_warning_duration: float = 0.6  # flicker before teleport
@export var teleport_offset: float = 180.0          # how far from player he lands

# --- STEAL ---
@export var steal_cents: int = 25
@export var time_drain_seconds: float = 4.0
@export var contact_distance: float = 80.0
@export var steal_cooldown: float = 1.5

# --- CLAMP ---
@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var can_steal: bool = true

var _teleport_timer: float = 0.0
var _next_teleport_time: float = 0.0
var _is_flickering: bool = false
var _flicker_timer: float = 0.0
var _flicker_toggle: float = 0.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_next_teleport_time = randf_range(teleport_interval_min, teleport_interval_max)
	_teleport_timer = 0.0
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

	# --- TELEPORT TIMING ---
	if _is_flickering:
		_flicker_timer -= delta
		_flicker_toggle += delta * 18.0
		# Flicker effect — rapidly toggle visibility
		var show := fmod(_flicker_toggle, 1.0) > 0.5
		if sprite:
			sprite.visible = show
		if sprite2d:
			sprite2d.visible = show

		velocity = Vector2.ZERO
		move_and_slide()

		if _flicker_timer <= 0.0:
			_do_teleport()
		return

	_teleport_timer += delta
	if _teleport_timer >= _next_teleport_time:
		_teleport_timer = 0.0
		_next_teleport_time = randf_range(teleport_interval_min, teleport_interval_max)
		_start_flicker()
		return

	# --- SCORE-DRIVEN SPEED ---
	var current_cents := 0
	var s := get_node_or_null("/root/score")
	if s and "cents" in s:
		current_cents = s.cents
	var dollars := float(current_cents) / 100.0
	var current_speed := minf(base_speed + dollars * speed_per_dollar, max_speed)

	# --- CHASE ---
	var to_player := player.global_position - global_position
	var dist := to_player.length()

	if dist > contact_distance:
		velocity = to_player.normalized() * current_speed
		_play_anim("walk")
	else:
		velocity = Vector2.ZERO
		_play_anim("attack")

	move_and_slide()
	_clamp_to_play_area()
	_update_facing()

	# --- CONTACT ---
	if dist <= contact_distance and can_steal:
		_on_contact()


func _start_flicker() -> void:
	_is_flickering = true
	_flicker_timer = teleport_warning_duration
	_flicker_toggle = 0.0


func _do_teleport() -> void:
	_is_flickering = false

	# Restore visibility
	if sprite:
		sprite.visible = true
	if sprite2d:
		sprite2d.visible = true

	# Pick a random angle and land near the player
	var angle := randf() * TAU
	var offset := Vector2(cos(angle), sin(angle)) * teleport_offset
	var new_pos := player.global_position + offset

	# Clamp to play area
	new_pos.x = clampf(new_pos.x, min_x, max_x)
	new_pos.y = clampf(new_pos.y, min_y, max_y)
	global_position = new_pos

	# Spawn teleport flash at arrival point
	_spawn_teleport_flash(new_pos)
	_play_anim("attack")

	print("CHICKENLEG TELEPORTED!")


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
	get_tree().call_group("timer", "subtract_time", time_drain_seconds)

	# Sound
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	# Red flash
	_spawn_contact_flash()

	await get_tree().create_timer(steal_cooldown).timeout
	can_steal = true


func _spawn_teleport_flash(pos: Vector2) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)

	var screen_pos := get_viewport().get_canvas_transform() * pos

	# Ring of yellow particles at landing spot
	for i in range(10):
		var dot := ColorRect.new()
		dot.size = Vector2(8, 8)
		dot.color = Color(1.0, 0.9, 0.1, 1.0)
		dot.position = screen_pos
		canvas.add_child(dot)
		var angle := (TAU / 10.0) * i
		var target := screen_pos + Vector2(cos(angle), sin(angle)) * 80.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(dot, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN)

	get_tree().create_timer(0.4).timeout.connect(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
	)


func _spawn_contact_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)
	var flash := ColorRect.new()
	flash.color = Color(0.9, 0.1, 0.1, 0.3)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	# Use a timer instead of tween callback to avoid null reference
	var tw := flash.create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.25).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(0.3).timeout.connect(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
	)


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
