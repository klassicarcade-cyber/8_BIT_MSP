# fizz_pterodactyl.gd
# Fizz Age dive-bomber helper — triggered at $28.10 in the Fizz game.
#
# Behavior loop:
#   1. Fly in from LEFT
#   2. Dive to grab a can
#   3. Rise back to cruise altitude carrying the can
#   4. Fly OFF SCREEN to the RIGHT (exit with can)
#   5. Re-enter from LEFT
#   6. Repeat until no cans remain or active_duration expires
#   7. Final exit to the RIGHT

extends CharacterBody2D

# ── Tunable (all visible in Inspector) ───────────────────────────────────
@export var active_duration:  float = 30.0
@export var fly_speed:        float = 280.0
@export var dive_speed:       float = 460.0
@export var rise_speed:       float = 300.0
@export var exit_speed:       float = 500.0   # fast exit after grab
@export var reentry_speed:    float = 350.0   # speed coming back in
@export var detect_range:     float = 1200.0
@export var grab_distance:    float = 40.0
@export var min_x:            float = 200.0
@export var max_x:            float = 1720.0

# Can offset relative to bird after grab — tune in Inspector
@export var carry_offset_x:   float = 0.0
@export var carry_offset_y:   float = 70.0

# ── Red can waves ─────────────────────────────────────────────────────────
@export var red_can_scene:     PackedScene = null
@export var can_wave_1_count:  int   = 6
@export var can_wave_2_count:  int   = 4
@export var can_wave_2_delay:  float = 12.0

# ── Entry / exit positions ────────────────────────────────────────────────
@export var entry_x:    float = -140.0
@export var exit_x:     float = 2080.0
@export var cruise_y:   float = 160.0

# ── State ─────────────────────────────────────────────────────────────────
enum State {
	ENTERING,    # flying in from left
	DIVING,      # heading down toward a can
	RISING,      # pulling up after grab
	FLEEING,     # flying off screen right with can
	REENTERING,  # coming back from left for another run
	FINAL_EXIT   # all cans done or time up — leave forever
}

var _state:          int   = State.ENTERING
var _active_timer:   float = 0.0
var _wave_2_spawned: bool  = false
var _direction:      int   = 1
var _red_cans:       Array[Node] = []
var _target_can:     Node2D = null
var _carried_can:    Node2D = null
var _runs_done:      int   = 0

var frozen: bool = false

# ── Animation ─────────────────────────────────────────────────────────────
@export var anim_fps: float = 4.0
const FRAMES_FLY:   Array[int] = [0, 1, 2, 3]
const FRAMES_DIVE:  Array[int] = [4, 5, 6, 7]
const FRAMES_CARRY: Array[int] = [8, 9, 10, 11]

var _frame_timer:    float = 0.0
var _frame_cursor:   int   = 0
var _current_frames: Array[int] = FRAMES_FLY

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("fizz_pterodactyl")
	process_mode = Node.PROCESS_MODE_ALWAYS
	global_position = Vector2(entry_x, cruise_y)
	_direction = 1
	_apply_facing()
	_spawn_can_wave(can_wave_1_count)
	print("🦕 Fizz Pterodactyl — Run 1 incoming!")


func _physics_process(delta: float) -> void:
	_animate(delta)
	_active_timer += delta

	# Wave 2 spawns on a timer regardless of state
	if not _wave_2_spawned and _active_timer >= can_wave_2_delay:
		_wave_2_spawned = true
		_spawn_can_wave(can_wave_2_count)

	match _state:
		State.ENTERING:    _do_entering()
		State.DIVING:      _do_diving()
		State.RISING:      _do_rising(delta)
		State.FLEEING:     _do_fleeing()
		State.REENTERING:  _do_reentering()
		State.FINAL_EXIT:  _do_final_exit()

	_update_carried_can()
	move_and_slide()


# ── ENTERING — fly in from left, find a can to dive for ──────────────────
func _do_entering() -> void:
	velocity = Vector2(fly_speed, 0.0)
	_set_anim_frames(FRAMES_FLY)

	# Once far enough in, look for a can
	if global_position.x < 300.0:
		return

	var can := _find_nearest_can()
	if can != null:
		_target_can = can
		_state = State.DIVING
		print("🦕 Diving for can!")
	elif _active_timer >= active_duration:
		_state = State.FINAL_EXIT


# ── DIVING — head straight for the target can ─────────────────────────────
func _do_diving() -> void:
	if not is_instance_valid(_target_can):
		# Can disappeared — re-enter for another pass
		_start_reentry()
		return

	var to_can := _target_can.global_position - global_position
	if to_can.length() <= grab_distance:
		_grab_can()
		return

	var dir := to_can.normalized()
	velocity = dir * dive_speed
	_direction = 1 if dir.x >= 0.0 else -1
	_apply_facing()
	if sprite:
		sprite.rotation = clampf(dir.angle(), -PI / 3.0, PI / 3.0)
	_set_anim_frames(FRAMES_DIVE)


# ── GRAB ──────────────────────────────────────────────────────────────────
func _grab_can() -> void:
	if not is_instance_valid(_target_can):
		_start_reentry()
		return

	_carried_can = _target_can
	_target_can  = null
	_red_cans.erase(_carried_can)

	# Reparent can as child (Eagle/Owl pattern)
	var old_pos := _carried_can.global_position
	if _carried_can.get_parent():
		_carried_can.get_parent().remove_child(_carried_can)
	add_child(_carried_can)
	_carried_can.global_position = old_pos

	if _carried_can is CollisionObject2D:
		_carried_can.set_deferred("collision_layer", 0)
		_carried_can.set_deferred("collision_mask", 0)

	# Score directly — do NOT call collect() as that fades and frees the can
	score.add_pickup(100)

	_runs_done += 1
	_state = State.RISING
	_set_anim_frames(FRAMES_CARRY)
	if sprite:
		sprite.rotation = 0.0
	print("🦕 Grabbed can #", _runs_done, " — fleeing right!")


# ── RISING — pull up to cruise altitude, then flee in grab direction ──────
func _do_rising(delta: float) -> void:
	_apply_facing()
	velocity.x = fly_speed * _direction  # keep the direction he grabbed from

	var dy := cruise_y - global_position.y
	if abs(dy) <= rise_speed * delta:
		global_position.y = cruise_y
		velocity.y = 0.0
		_state = State.FLEEING
	else:
		velocity.y = sign(dy) * rise_speed

	_set_anim_frames(FRAMES_CARRY)


# ── FLEEING — carry the can fully off screen, same direction as grab ──────
func _do_fleeing() -> void:
	velocity = Vector2(exit_speed * _direction, 0.0)
	_apply_facing()
	_set_anim_frames(FRAMES_CARRY)

	var off_screen := global_position.x > exit_x if _direction == 1 else global_position.x < entry_x
	if off_screen:
		_drop_carried_can()
		var cans_left := get_tree().get_nodes_in_group("fizz_red_can").size()
		if cans_left > 0 and _active_timer < active_duration:
			_start_reentry()
		else:
			_state = State.FINAL_EXIT
			print("🦕 No more cans — final exit!")


# ── RE-ENTERING — re-enter from the SAME side he just exited ─────────────
func _start_reentry() -> void:
	_state = State.REENTERING
	# Snap to the same side he just left from, facing inward
	if _direction == 1:
		# Exited right → re-enter from right, fly left
		global_position = Vector2(exit_x, cruise_y)
		_direction = -1
	else:
		# Exited left → re-enter from left, fly right
		global_position = Vector2(entry_x, cruise_y)
		_direction = 1
	_apply_facing()
	print("🦕 Coming back from the same side — direction now ", _direction)


func _do_reentering() -> void:
	velocity = Vector2(reentry_speed * _direction, 0.0)
	_set_anim_frames(FRAMES_FLY)

	# Wait until we're meaningfully on screen before diving
	var on_screen := global_position.x < max_x - 200.0 if _direction == -1 else global_position.x > min_x + 200.0
	if not on_screen:
		return

	var can := _find_nearest_can()
	if can != null:
		_target_can = can
		_state = State.DIVING
		print("🦕 Diving for next can!")
	elif _active_timer >= active_duration:
		_state = State.FINAL_EXIT


# ── FINAL EXIT — fly off screen in current direction for good ────────────
func _do_final_exit() -> void:
	_apply_facing()
	velocity = Vector2(exit_speed * _direction, 0.0)
	_set_anim_frames(FRAMES_FLY)
	if sprite:
		sprite.rotation = move_toward(sprite.rotation, 0.0, 0.1)
	var off_screen := global_position.x > exit_x if _direction == 1 else global_position.x < entry_x
	if off_screen:
		_fade_remaining_cans()
		queue_free()


# ── HELPERS ───────────────────────────────────────────────────────────────
func _update_carried_can() -> void:
	if not is_instance_valid(_carried_can):
		return
	var x_off := carry_offset_x if _direction == 1 else -carry_offset_x
	_carried_can.position = Vector2(x_off, carry_offset_y)


func _drop_carried_can() -> void:
	if is_instance_valid(_carried_can):
		_carried_can.queue_free()
	_carried_can = null


func _find_nearest_can() -> Node2D:
	var nearest:   Node2D = null
	var best_dist: float  = detect_range
	for node in get_tree().get_nodes_in_group("fizz_red_can"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var n := node as Node2D
		if not n.visible:
			continue
		var dist := n.global_position.distance_to(global_position)
		if dist < best_dist:
			best_dist = dist
			nearest = n
	return nearest


func _apply_facing() -> void:
	if sprite:
		sprite.flip_h = _direction < 0


func _spawn_can_wave(count: int) -> void:
	if red_can_scene == null:
		push_error("FizzPterodactyl: red_can_scene is null — assign fizz_red_can.tscn in Inspector!")
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in range(count):
		var can := red_can_scene.instantiate() as Node2D
		if can == null:
			continue
		scene_root.add_child(can)
		_red_cans.append(can)
	print("🦕 Spawned ", count, " red cans (total: ", _red_cans.size(), ")")


func _fade_remaining_cans() -> void:
	for can in _red_cans:
		if is_instance_valid(can) and can.has_method("fade_out"):
			can.call("fade_out")
	_red_cans.clear()


# ── ANIMATION ─────────────────────────────────────────────────────────────
func _set_anim_frames(frames: Array[int]) -> void:
	if _current_frames != frames:
		_current_frames = frames
		_frame_cursor   = 0
		_frame_timer    = 0.0


func _animate(delta: float) -> void:
	_frame_timer += delta
	if _frame_timer < 1.0 / anim_fps:
		return
	_frame_timer  = 0.0
	_frame_cursor = (_frame_cursor + 1) % _current_frames.size()
	if sprite:
		sprite.frame = _current_frames[_frame_cursor]
