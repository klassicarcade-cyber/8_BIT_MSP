# dino.gd
# Fizz Age enemy: Dino — Rampage Charger
# Wanders slowly then builds up speed and charges across the screen.
# Any pickup caught in the charge path gets knocked away (reset).
# Steals money on contact with player during charge.

extends CharacterBody2D

@export var wander_speed: float = 70.0
@export var charge_speed: float = 520.0
@export var windup_duration: float = 1.2        # pause before charge
@export var charge_duration: float = 0.6        # how long the charge lasts
@export var cooldown_duration: float = 2.5      # rest after charge
@export var charge_steal_cents: int = 20        # steal on charge hit
@export var can_width: float = 80.0             # how wide the charge sweep is

@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var can_steal: bool = true

enum State { WANDER, WINDUP, CHARGE, COOLDOWN }
var _state: State = State.WANDER
var _state_timer: float = 0.0
var _charge_dir: Vector2 = Vector2.RIGHT
var _wander_dir: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.2, 0.2)).normalized()
	_state_timer = randf_range(2.0, 4.0)
	_play_anim("idle")


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	_state_timer -= delta

	match _state:
		State.WANDER:
			_do_wander(delta)
		State.WINDUP:
			_do_windup(delta)
		State.CHARGE:
			_do_charge(delta)
		State.COOLDOWN:
			_do_cooldown(delta)

	move_and_slide()
	_clamp_to_play_area()
	_update_facing()


func _do_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3)).normalized()
		_wander_timer = randf_range(1.0, 2.5)

	velocity = _wander_dir * wander_speed
	_play_anim("walk")

	if global_position.x <= min_x or global_position.x >= max_x: _wander_dir.x *= -1.0
	if global_position.y <= min_y or global_position.y >= max_y: _wander_dir.y *= -1.0

	if _state_timer <= 0.0:
		# Begin windup - aim at player
		_charge_dir = (player.global_position - global_position).normalized() if player else Vector2.RIGHT
		_state = State.WINDUP
		_state_timer = windup_duration
		velocity = Vector2.ZERO
		_play_anim("idle")
		_spawn_windup_warning()


func _do_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	_play_anim("attack")
	if _state_timer <= 0.0:
		_state = State.CHARGE
		_state_timer = charge_duration
		can_steal = true
		print("DINO CHARGES!")


func _do_charge(delta: float) -> void:
	velocity = _charge_dir * charge_speed
	_play_anim("walk")

	# Knock away any pickups in path
	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not node.visible or not node is Node2D: continue
		var pickup := node as Node2D
		var to_pickup := pickup.global_position - global_position
		# Check if pickup is roughly in charge direction and close
		var dot := to_pickup.normalized().dot(_charge_dir)
		if dot > 0.7 and to_pickup.length() < can_width:
			if pickup.has_method("reset_pickup"):
				pickup.call("reset_pickup")

	# Hit player during charge
	if player and can_steal:
		var dist := global_position.distance_to(player.global_position)
		if dist < 80.0:
			can_steal = false
			_do_steal()

	# Hit wall - stop charge
	if global_position.x <= min_x or global_position.x >= max_x or \
	   global_position.y <= min_y or global_position.y >= max_y:
		_state = State.COOLDOWN
		_state_timer = cooldown_duration

	if _state_timer <= 0.0:
		_state = State.COOLDOWN
		_state_timer = cooldown_duration


func _do_cooldown(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, charge_speed * delta * 3.0)
	_play_anim("idle")
	if _state_timer <= 0.0:
		_state = State.WANDER
		_state_timer = randf_range(3.0, 6.0)


func _do_steal() -> void:
	var s := get_node_or_null("/root/score")
	if s and s.has_method("add_pickup"):
		s.add_pickup(-charge_steal_cents)
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()
	get_tree().call_group("camera", "shake", 8.0, 0.3)
	_spawn_hit_flash()
	print("DINO HIT PLAYER for ", charge_steal_cents, " cents!")


func _spawn_windup_warning() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 48
	get_tree().root.add_child(canvas)
	var screen_pos := get_viewport().get_canvas_transform() * global_position
	var label := Label.new()
	label.text = "!!!"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.1))
	label.position = screen_pos + Vector2(-20, -80)
	canvas.add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 0.0, windup_duration)
	get_tree().create_timer(windup_duration + 0.1).timeout.connect(func():
		if is_instance_valid(canvas): canvas.queue_free()
	)


func _spawn_hit_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.4, 0.1, 0.35)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.3)
	get_tree().create_timer(0.35).timeout.connect(func():
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
