# paw_baseball_player.gd
# Paw Paw baseball helper — triggered at $28.20 in Paw Paw game.
# Uses AnimatedSprite2D with animations: walk, default, collect, thumbsup

extends Node2D

# ── Tunable ───────────────────────────────────────────────────────────────
@export var active_duration:  float = 25.0
@export var walk_speed:       float = 180.0
@export var stand_x:          float = 1400.0
@export var stand_y:          float = 720.0
@export var exit_x:           float = 2000.0

@export var can_scene:        PackedScene = null
@export var first_can_delay:  float = 2.0
@export var can_interval:     float = 4.0
@export var max_cans:         int   = 5
@export var mitt_offset_x:    float = -60.0   # left/right of stand_x — tune in Inspector
@export var mitt_offset_y:    float = -200.0  # up from stand_y — tune in Inspector

# ── State ─────────────────────────────────────────────────────────────────
enum State { WALKING, WAITING, CATCHING, EXITING }
var _state:          int   = State.WALKING
var _active_timer:   float = 0.0
var _can_timer:      float = 0.0
var _cans_thrown:    int   = 0

var frozen: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("paw_baseball_player")
	process_mode = Node.PROCESS_MODE_ALWAYS
	global_position = Vector2(-120.0, stand_y)
	sprite.play("walk")
	print("⚾ Baseball player walking on!")


func _physics_process(delta: float) -> void:
	match _state:
		State.WALKING:  _do_walking(delta)
		State.WAITING:  _do_waiting(delta)
		State.CATCHING: pass
		State.EXITING:  _do_exiting(delta)


# ── WALKING ───────────────────────────────────────────────────────────────
func _do_walking(delta: float) -> void:
	global_position.x += walk_speed * delta
	if global_position.x >= stand_x:
		global_position.x = stand_x
		global_position.y = stand_y
		_state = State.WAITING
		_can_timer = first_can_delay
		# Freeze on glove-up frame instead of animating
		sprite.stop()
		sprite.set_frame_and_progress(0, 0.0)
		print("⚾ Baseball player in position!")


# ── WAITING ───────────────────────────────────────────────────────────────
func _do_waiting(delta: float) -> void:
	_active_timer += delta
	_can_timer -= delta

	if _can_timer <= 0.0 and _cans_thrown < max_cans:
		_throw_can()
		_can_timer = can_interval

	if _active_timer >= active_duration:
		_state = State.EXITING
		sprite.flip_h = true
		sprite.play("walk")
		print("⚾ Baseball player exiting!")


# ── DROP A CAN ────────────────────────────────────────────────────────────
func _throw_can() -> void:
	if can_scene == null:
		push_error("PawBaseballPlayer: can_scene not assigned!")
		return

	_cans_thrown += 1

	var can := can_scene.instantiate() as Node2D
	if can == null:
		return

	# Mitt position — where the can lands (right side of player, at glove height)
	var mitt_pos := Vector2(stand_x + mitt_offset_x, stand_y + mitt_offset_y)

	# Can starts directly above the mitt so it falls straight down
	can.global_position = Vector2(mitt_pos.x, 80.0)
	get_tree().current_scene.add_child(can)

	var tw := can.create_tween()
	tw.tween_property(can, "global_position", mitt_pos, 0.8)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): _on_can_caught(can))

	print("⚾ Can #", _cans_thrown, " dropping!")


# ── CATCH ─────────────────────────────────────────────────────────────────
func _on_can_caught(can: Node2D) -> void:
	score.add_pickup(100)

	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(func():
		if is_instance_valid(can):
			can.queue_free()
		if _cans_thrown < max_cans and _active_timer < active_duration:
			_state = State.WAITING
			sprite.stop()
			sprite.set_frame_and_progress(0, 0.0)
		elif _state != State.EXITING:
			_state = State.EXITING
			sprite.flip_h = true
			sprite.play("walk")
	)


# ── EXITING ───────────────────────────────────────────────────────────────
func _do_exiting(delta: float) -> void:
	global_position.x += walk_speed * delta
	if global_position.x > exit_x:
		print("⚾ Baseball player gone!")
		queue_free()
