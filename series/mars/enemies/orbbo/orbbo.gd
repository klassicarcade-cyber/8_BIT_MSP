# orbbo.gd
# Mars enemy: Orbbo — Ray Gun Shooter
# Behavior: Keeps distance from player, aims at nearest can,
# charges up ray gun, then fires — destroying (resetting) the can.
# Does NOT chase the player directly.

extends CharacterBody2D

@export var move_speed: float = 110.0
@export var preferred_distance: float = 280.0   # distance Orbbo likes to keep from player
@export var aim_distance: float = 600.0         # max range to target a can

# --- RAY GUN ---
@export var charge_duration: float = 1.8        # wind-up before firing
@export var fire_cooldown: float = 3.0          # pause after firing
@export var beam_duration: float = 0.25         # how long beam is visible
@export var beam_color: Color = Color(0.2, 1.0, 0.4, 0.9)  # alien green beam

# --- CLAMP ---
@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null

enum State { ROAM, AIM, CHARGE, FIRE, COOLDOWN }
var _state: State = State.ROAM
var _target_can: Node2D = null
var _charge_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _beam_timer: float = 0.0

# Beam visual
var _beam_canvas: CanvasLayer = null
var _beam_line: Line2D = null

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_play_anim("idle")
	_build_beam()
	tree_exiting.connect(_cleanup)


func _build_beam() -> void:
	_beam_canvas = CanvasLayer.new()
	_beam_canvas.layer = 50
	get_tree().root.add_child(_beam_canvas)
	_beam_line = Line2D.new()
	_beam_line.width = 4.0
	_beam_line.default_color = beam_color
	# Gradient: bright at origin, dim in middle, bright energy ball at tip
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 0.0))
	gradient.add_point(0.04, Color(1.0, 1.0, 0.7, 1.0))          # white-hot at finger
	gradient.add_point(0.15, beam_color)                           # beam color
	gradient.add_point(0.45, Color(beam_color.r, beam_color.g, beam_color.b, 0.5))  # dim middle
	gradient.add_point(0.70, Color(beam_color.r, beam_color.g, beam_color.b, 0.8))  # building up
	gradient.add_point(0.88, Color(1.0, 1.0, 0.8, 1.0))          # white-hot energy ball
	gradient.add_point(1.0, Color(beam_color.r, beam_color.g, beam_color.b, 0.0))   # fade out
	_beam_line.gradient = gradient
	_beam_line.width_curve = _make_width_curve()
	_beam_line.visible = false
	_beam_canvas.add_child(_beam_line)


func _make_width_curve() -> Curve:
	var c := Curve.new()
	# Fat burst at finger, narrows in middle, big energy ball at tip
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.04, 1.0))   # big spike at finger origin
	c.add_point(Vector2(0.15, 0.5))   # settle down
	c.add_point(Vector2(0.35, 0.15))  # narrow beam in middle
	c.add_point(Vector2(0.55, 0.1))   # thin travel beam
	c.add_point(Vector2(0.75, 0.6))   # swell into energy ball
	c.add_point(Vector2(0.88, 1.0))   # peak of energy ball at tip
	c.add_point(Vector2(1.0, 0.0))    # explode out to nothing
	return c


func _cleanup() -> void:
	if _beam_canvas and is_instance_valid(_beam_canvas):
		_beam_canvas.queue_free()


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_hide_beam()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	match _state:
		State.ROAM:
			_do_roam(delta)
		State.AIM:
			_do_aim(delta)
		State.CHARGE:
			_do_charge(delta)
		State.FIRE:
			_do_fire(delta)
		State.COOLDOWN:
			_do_cooldown(delta)


func _do_roam(delta: float) -> void:
	# Keep preferred distance from player
	var to_player := player.global_position - global_position
	var dist := to_player.length()

	if dist < preferred_distance - 40.0:
		# Too close - back away
		velocity = -to_player.normalized() * move_speed
		_play_anim("walk")
	elif dist > preferred_distance + 40.0:
		# Too far - move closer
		velocity = to_player.normalized() * move_speed * 0.6
		_play_anim("walk")
	else:
		velocity = Vector2.ZERO
		_play_anim("idle")

	move_and_slide()
	_clamp_to_play_area()
	_update_facing()

	# Look for a can to target
	_target_can = _find_nearest_can()
	if _target_can != null:
		var can_dist := global_position.distance_to(_target_can.global_position)
		if can_dist <= aim_distance:
			_state = State.AIM


func _do_aim(delta: float) -> void:
	# Hold position, face the can
	velocity = Vector2.ZERO
	move_and_slide()

	if _target_can == null or not is_instance_valid(_target_can) or not _target_can.visible:
		_target_can = null
		_state = State.ROAM
		return

	# Face the can
	var to_can := _target_can.global_position - global_position
	if sprite:
		sprite.flip_h = to_can.x < 0.0
	if sprite2d:
		sprite2d.flip_h = to_can.x < 0.0

	_play_anim("attack")

	# Brief aim pause then charge
	_charge_timer = charge_duration
	_state = State.CHARGE


func _do_charge(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_charge_timer -= delta
	_play_anim("attack")

	if _target_can == null or not is_instance_valid(_target_can) or not _target_can.visible:
		_target_can = null
		_state = State.ROAM
		_charge_timer = 0.0
		return

	# Pulse the beam line during charge (dotted/flickering)
	if _beam_line:
		var finger_pos := _get_finger_pos()
		var screen_to := get_viewport().get_canvas_transform() * _target_can.global_position
		_beam_line.clear_points()
		_beam_line.add_point(finger_pos)
		_beam_line.add_point(screen_to)
		var pulse := fmod(_charge_timer * 8.0, 1.0) > 0.5
		_beam_line.width = 3.0 if pulse else 1.5
		_beam_line.visible = pulse

	if _charge_timer <= 0.0:
		_state = State.FIRE


func _do_fire(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	# Fire the beam!
	if _target_can and is_instance_valid(_target_can) and _target_can.visible:
		# Full energy pulse beam from finger tip
		if _beam_line:
			var finger_pos := _get_finger_pos()
			var screen_to := get_viewport().get_canvas_transform() * _target_can.global_position
			var dir := (screen_to - finger_pos).normalized()
			var beam_len := finger_pos.distance_to(screen_to)
			_beam_line.clear_points()
			var steps := 20
			for i in range(steps + 1):
				var t := float(i) / float(steps)
				_beam_line.add_point(finger_pos + dir * beam_len * t)
			_beam_line.width = 28.0
			_beam_line.visible = true

		# Destroy the can
		if _target_can.has_method("reset_pickup"):
			_target_can.call("reset_pickup")

		# Spawn hit flash at can position
		_spawn_hit_flash(_target_can.global_position)

		# Sound
		if steal_sfx and steal_sfx.stream:
			steal_sfx.play()

		print("ORBBO FIRED RAY GUN!")

	_target_can = null
	_beam_timer = beam_duration
	_state = State.COOLDOWN
	_cooldown_timer = fire_cooldown


func _do_cooldown(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_play_anim("idle")

	_beam_timer -= delta
	_cooldown_timer -= delta

	if _beam_timer <= 0.0:
		_hide_beam()

	if _cooldown_timer <= 0.0:
		_state = State.ROAM


func _find_nearest_can() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not node.visible:
			continue
		var node_script = node.get_script()
		if node_script == null:
			continue
		if not ("can" in node_script.resource_path.to_lower()):
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest


func _spawn_hit_flash(pos: Vector2) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 51
	get_tree().root.add_child(canvas)
	var screen_pos := get_viewport().get_canvas_transform() * pos
	for i in range(8):
		var dot := ColorRect.new()
		dot.size = Vector2(8, 8)
		dot.color = beam_color
		dot.position = screen_pos
		canvas.add_child(dot)
		var angle := (TAU / 8.0) * i
		var target := screen_pos + Vector2(cos(angle), sin(angle)) * randf_range(40.0, 90.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "position", target, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(dot, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	get_tree().create_timer(0.35).timeout.connect(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
	)


func _get_finger_pos() -> Vector2:
	# Offset from center to finger tip based on facing direction
	var canvas_tf := get_viewport().get_canvas_transform()
	var center := canvas_tf * global_position
	var facing_right := false
	if sprite:
		facing_right = not sprite.flip_h
	elif sprite2d:
		facing_right = not sprite2d.flip_h
	var offset_x := 45.0 if facing_right else -45.0
	return center + Vector2(offset_x, -10.0)


func _hide_beam() -> void:
	if _beam_line:
		_beam_line.visible = false


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
