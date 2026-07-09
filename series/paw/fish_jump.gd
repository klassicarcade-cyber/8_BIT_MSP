# fish_jump.gd
# Decorative fish that leaps out of the Paw Paw lake (background2) twice.
# Uses a Sprite2D child node with fish.png texture.
# Save scene as: res://series/paw/fish_jump.tscn

extends Node2D

# ── Lake position (background2 — Maple Isle lake) ──
@export var lake_y: float          = 580.0   # water surface y position
@export var lake_min_x: float      = 900.0   # left edge of open water
@export var lake_max_x: float      = 1350.0  # right edge of open water

# ── Jump timing (within the 2 minute scene) ──
@export var first_jump_min: float  = 10.0
@export var first_jump_max: float  = 40.0
@export var second_jump_min: float = 70.0
@export var second_jump_max: float = 110.0

# ── Jump feel ──
@export var jump_height: float     = 160.0
@export var jump_duration: float   = 0.9
@export var fish_scale: Vector2    = Vector2(0.15, 0.15)
@export var splash_color: Color    = Color(0.4, 0.7, 1.0, 0.8)
@export var trout_texture: Texture2D = null  # assign trout.png in Inspector

var _timer_1: float = 0.0
var _timer_2: float = 0.0
var _timer_3: float = 0.0
var _jumped_1: bool = false
var _jumped_2: bool = false
var _jumped_3: bool = false

@onready var spr: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	_timer_1 = randf_range(first_jump_min, first_jump_max)
	_timer_2 = randf_range(second_jump_min, second_jump_max)
	_timer_3 = randf_range(second_jump_min + 20.0, 115.0)
	# Hide sprite until a jump happens
	if spr:
		spr.visible = false


func _process(delta: float) -> void:
	if not _jumped_1:
		_timer_1 -= delta
		if _timer_1 <= 0.0:
			_jumped_1 = true
			_do_jump()

	if not _jumped_2:
		_timer_2 -= delta
		if _timer_2 <= 0.0:
			_jumped_2 = true
			_do_jump()

	if not _jumped_3:
		_timer_3 -= delta
		if _timer_3 <= 0.0:
			_jumped_3 = true
			_do_jump()


func _do_jump() -> void:
	var jump_x := randf_range(lake_min_x, lake_max_x)
	var flip := randf() > 0.5

	# Create a fresh sprite instance for each jump so they can overlap
	var fish_spr: Sprite2D
	# Randomly pick fish or trout
	var use_trout := trout_texture != null and randf() > 0.5
	if spr and spr.texture:
		fish_spr = Sprite2D.new()
		fish_spr.texture = trout_texture if use_trout else spr.texture
		fish_spr.scale = fish_scale
		fish_spr.flip_h = flip
		fish_spr.z_index = 2
		fish_spr.global_position = Vector2(jump_x, lake_y)
		add_child(fish_spr)
	else:
		# Fallback to polygon if no sprite assigned
		fish_spr = null
		_do_jump_polygon(jump_x, flip)
		return

	_spawn_splash(jump_x)
	_animate_sprite(fish_spr, jump_x, flip)


func _animate_sprite(fish_spr: Sprite2D, jump_x: float, flip: bool) -> void:
	var steps := 20
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var delay := t * jump_duration
		var y := lake_y + (-jump_height) * 4.0 * t * (1.0 - t)
		var drift := 30.0 if not flip else -30.0
		var x := jump_x + drift * t
		# Rotate to follow arc
		var angle := PI * 0.4 - PI * 0.8 * t
		if flip:
			angle = -angle
		var target_pos := Vector2(x, y)
		var target_rot := angle
		var target_alpha := 1.0 if t < 0.7 else 1.0 - ((t - 0.7) / 0.3)

		var tw := get_tree().create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func():
			if is_instance_valid(fish_spr):
				fish_spr.global_position = target_pos
				fish_spr.rotation = target_rot
				fish_spr.modulate.a = target_alpha
		)

	# Splash and free after arc completes
	var end_tw := get_tree().create_tween()
	end_tw.tween_interval(jump_duration)
	end_tw.tween_callback(func():
		if is_instance_valid(fish_spr):
			_spawn_splash(fish_spr.global_position.x)
			fish_spr.queue_free()
	)


# ── Polygon fallback if no sprite assigned ──
func _do_jump_polygon(jump_x: float, flip: bool) -> void:
	var fish := Polygon2D.new()
	fish.polygon = _fish_shape()
	fish.color = Color(0.5, 0.8, 1.0, 1.0)
	fish.scale = Vector2(1.0 if not flip else -1.0, 1.0)
	fish.z_index = 2
	fish.global_position = Vector2(jump_x, lake_y)
	add_child(fish)
	_spawn_splash(jump_x)
	_animate_polygon(fish, jump_x, flip)


func _animate_polygon(fish: Polygon2D, jump_x: float, flip: bool) -> void:
	var steps := 20
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var delay := t * jump_duration
		var y := lake_y + (-jump_height) * 4.0 * t * (1.0 - t)
		var drift := 30.0 if not flip else -30.0
		var x := jump_x + drift * t
		var angle := -PI * 0.5 + PI * t
		if flip:
			angle = -angle
		var target_pos := Vector2(x, y)
		var target_rot := angle
		var target_alpha := 1.0 if t < 0.7 else 1.0 - ((t - 0.7) / 0.3)

		var tw := get_tree().create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func():
			if is_instance_valid(fish):
				fish.global_position = target_pos
				fish.rotation = target_rot
				fish.modulate.a = target_alpha
		)

	var end_tw := get_tree().create_tween()
	end_tw.tween_interval(jump_duration)
	end_tw.tween_callback(func():
		if is_instance_valid(fish):
			_spawn_splash(fish.global_position.x)
			fish.queue_free()
	)


func _spawn_splash(x: float) -> void:
	for i in range(6):
		var dot := Polygon2D.new()
		dot.polygon = _circle_shape(4.0)
		dot.color = splash_color
		dot.z_index = 2
		var start_pos := Vector2(x + randf_range(-15.0, 15.0), lake_y)
		dot.global_position = start_pos
		add_child(dot)

		var angle := randf() * TAU
		var dist := randf_range(15.0, 50.0)
		var target := start_pos + Vector2(cos(angle) * dist, sin(angle) * dist * 0.4)

		var tw := dot.create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "global_position", target, 0.35).set_ease(Tween.EASE_OUT)
		tw.tween_property(dot, "modulate:a", 0.0, 0.35)
		tw.chain().tween_callback(dot.queue_free)


func _fish_shape() -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(30, 0))
	pts.append(Vector2(10, -12))
	pts.append(Vector2(-10, -14))
	pts.append(Vector2(-25, -8))
	pts.append(Vector2(-40, -22))
	pts.append(Vector2(-35, 0))
	pts.append(Vector2(-40, 22))
	pts.append(Vector2(-25, 8))
	pts.append(Vector2(-10, 14))
	pts.append(Vector2(10, 12))
	return pts


func _circle_shape(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(8):
		var a := TAU * float(i) / 8.0
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts
	   
