# wooly.gd
# Fizz Age enemy: Wooly — The Entangler
# Chases the player slowly. The longer the player stays near Wooly
# the stronger the entangle effect gets — slowing the player AND
# stealing both money AND time simultaneously when fully entangled.
# Entangle fades quickly once player escapes.

extends CharacterBody2D

@export var move_speed: float = 110.0
@export var entangle_range: float = 160.0       # range to start entangling
@export var entangle_ramp_time: float = 3.0     # seconds to reach full entangle
@export var slow_max: float = 0.35              # minimum speed multiplier when fully entangled
@export var steal_cents_max: int = 30           # max steal per tick at full entangle
@export var time_drain_max: float = 2.0         # max time drain per tick at full entangle
@export var steal_interval: float = 1.0         # steal every N seconds when entangled
@export var entangle_decay: float = 2.5         # how fast entangle fades when player escapes
@export var wool_color: Color = Color(0.9, 0.8, 0.6, 0.5)

@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var _entangle_level: float = 0.0               # 0.0 = free, 1.0 = fully entangled
var _steal_timer: float = 0.0
var _wool_canvas: CanvasLayer = null
var _wool_strands: Array = []

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer
@onready var chirp_sfx: AudioStreamPlayer = get_node_or_null("ChirpSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_steal_timer = steal_interval
	_build_wool_canvas()
	_play_anim("idle")
	tree_exiting.connect(_cleanup)


func _build_wool_canvas() -> void:
	_wool_canvas = CanvasLayer.new()
	_wool_canvas.layer = 48
	get_tree().root.add_child(_wool_canvas)


func _cleanup() -> void:
	if _wool_canvas and is_instance_valid(_wool_canvas):
		_wool_canvas.queue_free()
	# Remove player slow effect
	if player and is_instance_valid(player) and player is CharacterBody2D:
		if player.has_method("clear_slow"):
			player.call("clear_slow")


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_entangle_level = 0.0
		_clear_wool()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if player == null:
		return

	var dist := global_position.distance_to(player.global_position)

	# Update entangle level
	if dist <= entangle_range:
		_entangle_level = minf(_entangle_level + delta / entangle_ramp_time, 1.0)
	else:
		_entangle_level = maxf(_entangle_level - delta * entangle_decay, 0.0)

	# Apply slow to player when entangled
	if _entangle_level > 0.0 and player is CharacterBody2D:
		var slow_mult := lerpf(1.0, slow_max, _entangle_level)
		if player.has_method("apply_slow"):
			player.call("apply_slow", slow_mult, 0.2)
		elif "velocity" in player:
			# Direct velocity dampening as fallback
			(player as CharacterBody2D).velocity *= lerpf(1.0, 0.92, _entangle_level)

	# Steal when sufficiently entangled
	if _entangle_level > 0.3:
		_steal_timer -= delta
		if _steal_timer <= 0.0:
			_steal_timer = steal_interval
			_do_entangle_steal()

	# Chase player slowly
	var to_player := player.global_position - global_position
	if dist > 80.0:
		velocity = to_player.normalized() * move_speed * (1.0 - _entangle_level * 0.3)
		if _entangle_level < 0.3:
			_play_anim("walk")
		else:
			_play_anim("attack")
	else:
		velocity = Vector2.ZERO
		_play_anim("attack")

	move_and_slide()
	_clamp_to_play_area()
	_update_facing()

	# Draw wool strands connecting to player
	_update_wool_visual()

	# Modulate to show entangle level
	if sprite:
		sprite.modulate = Color(1.0, lerpf(1.0, 0.7, _entangle_level),
			lerpf(1.0, 0.5, _entangle_level))


func _do_entangle_steal() -> void:
	var cents := int(steal_cents_max * _entangle_level)
	var time_drain := time_drain_max * _entangle_level

	var s := get_node_or_null("/root/score")
	if s and s.has_method("add_pickup") and cents > 0:
		s.add_pickup(-cents)

	if time_drain > 0.5:
		get_tree().call_group("timer", "subtract_time", time_drain)

	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	print("WOOLY ENTANGLE: level=", _entangle_level, " stolen=", cents, "c + ", time_drain, "s")


func _update_wool_visual() -> void:
	if _wool_canvas == null or player == null: return

	# Clear old strands
	_clear_wool()

	if _entangle_level < 0.1:
		return

	# Draw wool strands from Wooly to player
	var screen_from := get_viewport().get_canvas_transform() * global_position
	var screen_to := get_viewport().get_canvas_transform() * player.global_position
	var strand_count := int(_entangle_level * 5.0) + 1

	for i in range(strand_count):
		var line := Line2D.new()
		var t := float(i) / float(max(strand_count - 1, 1))
		var wobble := Vector2(sin(Time.get_ticks_msec() * 0.003 + t * 5.0) * 20.0,
			cos(Time.get_ticks_msec() * 0.004 + t * 3.0) * 15.0)
		var mid := (screen_from + screen_to) * 0.5 + wobble
		line.add_point(screen_from)
		line.add_point(mid)
		line.add_point(screen_to)
		line.width = lerpf(1.0, 4.0, _entangle_level)
		line.default_color = Color(wool_color.r, wool_color.g, wool_color.b,
			wool_color.a * _entangle_level)
		_wool_canvas.add_child(line)
		_wool_strands.append(line)


func _clear_wool() -> void:
	for strand in _wool_strands:
		if is_instance_valid(strand):
			strand.queue_free()
	_wool_strands.clear()


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
