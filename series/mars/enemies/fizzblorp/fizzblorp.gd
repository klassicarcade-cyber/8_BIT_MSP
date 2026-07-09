# fizzblorp.gd
# Mars enemy: Fizzblorp — The Trash Ship
# Behavior: Floats around slowly. When near a can, activates tractor beam
# and pulls the can toward itself. Once it collects 3 cans it zooms
# off screen and returns empty. Very alien, very Mars.

extends CharacterBody2D

@export var float_speed: float = 80.0           # slow hover speed
@export var beam_range: float = 220.0           # range to start tractor beam
@export var collect_distance: float = 50.0      # distance to "collect" the can
@export var cans_to_collect: int = 3            # cans before zooming off
@export var zoom_speed: float = 800.0           # speed when zooming off screen
@export var return_delay: float = 3.0           # seconds off screen before returning
@export var beam_color: Color = Color(0.4, 0.8, 1.0, 0.7)  # blue tractor beam

# --- CLAMP ---
@export var min_x: float = 120.0
@export var max_x: float = 1800.0
@export var min_y: float = 120.0
@export var max_y: float = 900.0

var frozen: bool = false
var player: Node2D = null
var _cans_collected: int = 0
var _target_can: Node2D = null

enum State { FLOAT, BEAM, COLLECT, ZOOM_OUT, RETURNING }
var _state: State = State.FLOAT
var _zoom_dir: Vector2 = Vector2.UP
var _return_timer: float = 0.0

# Tractor beam visual
var _beam_canvas: CanvasLayer = null
var _beam_line: Line2D = null

# Can counter display
var _counter_canvas: CanvasLayer = null
var _counter_label: Label = null

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_play_anim("idle")
	_build_visuals()
	tree_exiting.connect(_cleanup)


func _build_visuals() -> void:
	# Tractor beam
	_beam_canvas = CanvasLayer.new()
	_beam_canvas.layer = 48
	get_tree().root.add_child(_beam_canvas)
	_beam_line = Line2D.new()
	_beam_line.width = 8.0
	_beam_line.default_color = beam_color
	_beam_line.visible = false
	_beam_canvas.add_child(_beam_line)

	# Can counter above ship
	_counter_canvas = CanvasLayer.new()
	_counter_canvas.layer = 51
	get_tree().root.add_child(_counter_canvas)
	_counter_label = Label.new()
	_counter_label.text = ""
	_counter_label.add_theme_font_size_override("font_size", 18)
	_counter_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_counter_label.visible = false
	_counter_canvas.add_child(_counter_label)


func _cleanup() -> void:
	for c in [_beam_canvas, _counter_canvas]:
		if c and is_instance_valid(c):
			c.queue_free()


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_hide_beam()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	# Update counter display
	_update_counter()

	match _state:
		State.FLOAT:
			_do_float(delta)
		State.BEAM:
			_do_beam(delta)
		State.COLLECT:
			_do_collect(delta)
		State.ZOOM_OUT:
			_do_zoom_out(delta)
		State.RETURNING:
			_do_return(delta)


func _do_float(delta: float) -> void:
	_hide_beam()

	# Gentle hover - slowly drift toward nearest can
	_target_can = _find_nearest_can()

	if _target_can:
		var to_can := _target_can.global_position - global_position
		var dist := to_can.length()

		if dist <= beam_range:
			_state = State.BEAM
			return

		# Move slowly toward can
		velocity = to_can.normalized() * float_speed
		_play_anim("walk")
	else:
		# No cans - hover in place with gentle drift
		velocity = velocity.move_toward(Vector2.ZERO, float_speed * delta)
		_play_anim("idle")

	move_and_slide()
	_clamp_to_play_area()


func _do_beam(delta: float) -> void:
	if _target_can == null or not is_instance_valid(_target_can) or not _target_can.visible:
		_target_can = _find_nearest_can()
		if _target_can == null:
			_state = State.FLOAT
			_hide_beam()
			return

	var to_can := _target_can.global_position - global_position
	var dist := to_can.length()

	if dist > beam_range + 50.0:
		_state = State.FLOAT
		_hide_beam()
		return

	# Hold position while beaming
	velocity = Vector2.ZERO
	move_and_slide()
	_play_anim("attack")

	# Draw tractor beam
	if _beam_line:
		var screen_from := get_viewport().get_canvas_transform() * global_position
		var screen_to := get_viewport().get_canvas_transform() * _target_can.global_position
		_beam_line.clear_points()
		# Wavy beam - add midpoints
		var mid := (screen_from + screen_to) * 0.5
		mid += Vector2(sin(Time.get_ticks_msec() * 0.01) * 20.0, cos(Time.get_ticks_msec() * 0.008) * 20.0)
		_beam_line.add_point(screen_from)
		_beam_line.add_point(mid)
		_beam_line.add_point(screen_to)
		_beam_line.width = 6.0 + sin(Time.get_ticks_msec() * 0.015) * 2.0
		_beam_line.default_color = beam_color
		_beam_line.visible = true

	# Pull can toward Fizzblorp
	if _target_can is Node2D:
		var pull_dir := (global_position - _target_can.global_position).normalized()
		(_target_can as Node2D).global_position += pull_dir * 120.0 * delta

	# Check if collected
	if dist <= collect_distance:
		_state = State.COLLECT


func _do_collect(delta: float) -> void:
	_hide_beam()
	_cans_collected += 1
	_play_anim("attack")

	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	# Reset the can (it's been "collected")
	if _target_can and is_instance_valid(_target_can):
		_target_can.call("reset_pickup")
	_target_can = null

	print("FIZZBLORP collected can ", _cans_collected, "/", cans_to_collect)

	if _cans_collected >= cans_to_collect:
		# ZOOM OFF SCREEN!
		_zoom_dir = Vector2(randf_range(-0.5, 0.5), -1.0).normalized()
		_state = State.ZOOM_OUT
		print("FIZZBLORP ZOOMING OFF!")
	else:
		_state = State.FLOAT


func _do_zoom_out(delta: float) -> void:
	velocity = _zoom_dir * zoom_speed
	move_and_slide()
	_play_anim("walk")

	# Check if off screen
	var vp_size := get_viewport().get_visible_rect().size
	var screen_pos := get_viewport().get_canvas_transform() * global_position
	if screen_pos.x < -200 or screen_pos.x > vp_size.x + 200 or \
	   screen_pos.y < -200 or screen_pos.y > vp_size.y + 200:
		_return_timer = return_delay
		_state = State.RETURNING
		_cans_collected = 0


func _do_return(delta: float) -> void:
	_return_timer -= delta
	if _return_timer <= 0.0:
		# Reappear at random edge of screen
		var vp_size := get_viewport().get_visible_rect().size
		var side := randi() % 4
		match side:
			0: global_position = Vector2(randf_range(min_x, max_x), min_y - 100)
			1: global_position = Vector2(randf_range(min_x, max_x), max_y + 100)
			2: global_position = Vector2(min_x - 100, randf_range(min_y, max_y))
			3: global_position = Vector2(max_x + 100, randf_range(min_y, max_y))
		_state = State.FLOAT
		print("FIZZBLORP RETURNED!")


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


func _update_counter() -> void:
	if _counter_label == null:
		return
	if _cans_collected > 0 and _state != State.ZOOM_OUT and _state != State.RETURNING:
		var screen_pos := get_viewport().get_canvas_transform() * global_position
		_counter_label.position = screen_pos + Vector2(-20, -60)
		_counter_label.text = "🛸 %d/%d" % [_cans_collected, cans_to_collect]
		_counter_label.visible = true
	else:
		_counter_label.visible = false


func _hide_beam() -> void:
	if _beam_line:
		_beam_line.visible = false


func _clamp_to_play_area() -> void:
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, min_y, max_y)


func _play_anim(anim_name: String) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name:
			sprite.play(anim_name)
