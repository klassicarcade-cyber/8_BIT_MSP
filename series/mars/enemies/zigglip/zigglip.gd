# zigglip.gd
# Mars enemy: Zigglip — Teleport Stealer
# Blinks around the screen randomly. When landing near player steals money.
# Uses DashSFX on teleport, HitSFX on steal.
#
# Place exactly 2 of these in your scene. Each one picks a random starting
# position on _ready and teleports independently from that point on.

extends CharacterBody2D

@export var teleport_interval_min: float = 1.5
@export var teleport_interval_max: float = 3.5
@export var teleport_warning: float = 0.4
@export var steal_distance: float = 130.0
@export var steal_cents: int = 15
@export var steal_cooldown: float = 1.2
@export var blink_color: Color = Color(0.5, 1.0, 0.5, 0.8)

@export var min_x: float = 200.0
@export var max_x: float = 1720.0
@export var min_y: float = 150.0
@export var max_y: float = 850.0

var frozen: bool = false
var player: Node2D = null
var can_steal: bool = true

var _teleport_timer: float = 0.0
var _next_teleport: float = 0.0
var _is_blinking: bool = false
var _blink_timer: float = 0.0
var _blink_toggle: float = 0.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var dash_sfx: AudioStreamPlayer = get_node_or_null("DashSFX") as AudioStreamPlayer
@onready var hit_sfx: AudioStreamPlayer = get_node_or_null("HitSFX") as AudioStreamPlayer
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D

	# Random starting position each time the scene loads
	global_position = Vector2(
		randf_range(min_x, max_x),
		randf_range(min_y, max_y)
	)

	# Stagger teleport timers so the two Zigglips don't sync up
	_next_teleport = randf_range(teleport_interval_min, teleport_interval_max)
	_teleport_timer = randf_range(0.0, _next_teleport)

	_play_anim("idle")


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if player == null:
		return

	# Blink warning before teleport
	if _is_blinking:
		_blink_timer -= delta
		_blink_toggle += delta * 20.0
		var show := fmod(_blink_toggle, 1.0) > 0.5
		if sprite: sprite.visible = show
		if sprite2d: sprite2d.visible = show
		velocity = Vector2.ZERO
		move_and_slide()
		if _blink_timer <= 0.0:
			_do_teleport()
		return

	# Idle float in place
	velocity = Vector2.ZERO
	_play_anim("idle")
	move_and_slide()

	# Teleport timing
	_teleport_timer += delta
	if _teleport_timer >= _next_teleport:
		_teleport_timer = 0.0
		_next_teleport = randf_range(teleport_interval_min, teleport_interval_max)
		_is_blinking = true
		_blink_timer = teleport_warning
		_blink_toggle = 0.0

	# Steal check after landing near player
	if can_steal:
		var dist := global_position.distance_to(player.global_position)
		if dist <= steal_distance:
			_do_steal()


func _do_teleport() -> void:
	_is_blinking = false
	if sprite: sprite.visible = true
	if sprite2d: sprite2d.visible = true

	# Always land at a fully independent random position
	var new_pos := Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))

	new_pos.x = clampf(new_pos.x, min_x, max_x)
	new_pos.y = clampf(new_pos.y, min_y, max_y)

	# Flash at old position
	_spawn_blink_flash(global_position)
	global_position = new_pos
	# Flash at new position
	_spawn_blink_flash(global_position)

	_play_anim("attack")
	if dash_sfx and dash_sfx.stream:
		dash_sfx.play()


func _do_steal() -> void:
	can_steal = false
	_play_anim("attack")

	var s := get_node_or_null("/root/score")
	if s:
		if s.has_method("add_pickup"):
			s.add_pickup(-steal_cents)

	if hit_sfx and hit_sfx.stream:
		hit_sfx.play()
	elif steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	_spawn_steal_flash()
	print("ZIGGLIP STOLE ", steal_cents, " cents!")

	await get_tree().create_timer(steal_cooldown).timeout
	can_steal = true


func _spawn_blink_flash(pos: Vector2) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)
	var screen_pos := get_viewport().get_canvas_transform() * pos
	for i in range(6):
		var dot := ColorRect.new()
		dot.size = Vector2(6, 6)
		dot.color = blink_color
		dot.position = screen_pos
		canvas.add_child(dot)
		var angle := (TAU / 6.0) * i
		var target := screen_pos + Vector2(cos(angle), sin(angle)) * randf_range(20.0, 60.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "position", target, 0.2).set_ease(Tween.EASE_OUT)
		tw.tween_property(dot, "modulate:a", 0.0, 0.2)
	get_tree().create_timer(0.25).timeout.connect(func():
		if is_instance_valid(canvas): canvas.queue_free()
	)


func _spawn_steal_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)
	var flash := ColorRect.new()
	flash.color = Color(blink_color.r, blink_color.g, blink_color.b, 0.25)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.2)
	get_tree().create_timer(0.25).timeout.connect(func():
		if is_instance_valid(canvas): canvas.queue_free()
	)


func _play_anim(anim_name: String) -> void:
	if sprite == null or sprite.sprite_frames == null: return
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name:
			sprite.play(anim_name)
