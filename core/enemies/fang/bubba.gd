# bubba.gd
# Fang-level guest character — appears at $28, collects bottles for MSP,
# then gives a thumbs-up and walks off screen after 1 minute.
# Enters from the RIGHT, exits to the LEFT.
#
# Spawns gold pickups in two waves — only Bubba can collect them.

extends CharacterBody2D

# ── Timing ──
@export var active_duration: float   = 15.0
@export var collect_radius: float    = 80.0
@export var collect_value_cents: int = 10
@export var walk_speed: float        = 160.0
@export var exit_speed: float        = 200.0

# ── Gold pickup waves ──
@export var gold_pickup_scene: PackedScene = null  # assign bubba_gold_pickup.tscn
@export var gold_wave_1_count: int  = 6            # spawned immediately on entry
@export var gold_wave_2_count: int  = 0            # disabled — one wave only
@export var gold_wave_2_delay: float = 15.0        # adjustable in Inspector

# ── Hand position calibration ──
@export var collect_point_offset: Vector2 = Vector2(40.0, 60.0)

# ── Boot position (where the can snaps to during collect) ──
# Positive x = right, negative x = left. Positive y = down.
@export var boot_offset: Vector2 = Vector2(-70.0, 105.0)

# ── World bounds ──
@export var min_x: float = 80.0
@export var max_x: float = 1840.0
@export var min_y: float = 150.0
@export var max_y: float = 850.0

# ── Entry from RIGHT, exit to LEFT ──
@export var entry_x: float = 2040.0
@export var exit_x: float  = -120.0
@export var entry_y: float = 540.0

enum State { ENTERING, COLLECTING, THUMBSUP, EXITING }
var _state: int = State.ENTERING

var _active_timer: float = 0.0
var _wave_2_spawned: bool = false
var _target: Node2D = null
var _gold_pickups: Array[Node] = []
var _is_collecting: bool = false

# frozen property — gameplay_root sets this but Bubba ignores it intentionally
var frozen: bool = false

@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func _ready() -> void:
	add_to_group("bubba")
	process_mode = Node.PROCESS_MODE_ALWAYS

	global_position = Vector2(entry_x, entry_y)
	_play_anim("walk")
	# Defer spawn so scene tree is fully ready
	call_deferred("_spawn_gold_wave", gold_wave_1_count)


func _physics_process(delta: float) -> void:
	match _state:
		State.ENTERING:
			_update_entering()
		State.COLLECTING:
			_active_timer += delta

			# Wave 2 — spawn second batch after delay
			if not _wave_2_spawned and _active_timer >= gold_wave_2_delay:
				_wave_2_spawned = true
				_spawn_gold_wave(gold_wave_2_count)

			if _active_timer >= active_duration:
				_begin_exit()
			else:
				_update_collecting()
		State.THUMBSUP:
			velocity = Vector2.ZERO
		State.EXITING:
			_update_exiting()

	if anim and abs(velocity.x) > 5.0:
		anim.flip_h = velocity.x > 0.0

	move_and_slide()


func _update_entering() -> void:
	var target_x := max_x - 100.0
	if global_position.x > target_x:
		velocity = Vector2(-walk_speed, 0.0)
	else:
		velocity = Vector2.ZERO
		_state = State.COLLECTING
		_play_anim("walk")


func _update_collecting() -> void:
	if _is_collecting:
		velocity = Vector2.ZERO
		return

	# First priority — go straight for gold cans
	var gold := _find_nearest_gold()
	if gold != null:
		var to_gold := (gold.global_position - Vector2(-20, 80.0)) - global_position
		if to_gold.length() <= collect_radius:
			_collect_gold(gold)
			return
		velocity = to_gold.normalized() * walk_speed
		return

	# Second priority — only collect bottles if NO gold cans remain
	if _gold_pickups.size() > 0:
		velocity = Vector2.ZERO
		return

	_target = _find_nearest_bottle()

	if _target == null or not is_instance_valid(_target):
		velocity = velocity.lerp(Vector2(sin(Time.get_ticks_msec() * 0.001) * walk_speed * 0.4, 0.0), 0.03)
		return

	var to_target := _target.global_position - global_position
	if to_target.length() <= collect_radius:
		_collect_bottle(_target)
		_target = null
		velocity = Vector2.ZERO
	else:
		velocity = to_target.normalized() * walk_speed


func _find_nearest_gold() -> Node2D:
	var golds := get_tree().get_nodes_in_group("bubba_pickup")
	var nearest: Node2D = null
	var nearest_dist := INF

	for g in golds:
		if not is_instance_valid(g):
			continue
		if not (g is Node2D):
			continue
		if not (g as Node2D).visible:
			continue
		var d := (g as Node2D).global_position.distance_to(global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = g as Node2D

	return nearest


func _find_nearest_bottle() -> Node2D:
	var pickups := get_tree().get_nodes_in_group("pickup")
	var nearest: Node2D = null
	var nearest_dist := INF

	for p in pickups:
		if not is_instance_valid(p):
			continue
		if not (p is Node2D):
			continue
		var n := p as Node2D
		if not n.visible:
			continue
		if "_respawning" in n and bool(n.get("_respawning")):
			continue
		var d := n.global_position.distance_to(global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = n

	return nearest


func _collect_gold(gold: Node2D) -> void:
	_is_collecting = true
	_play_anim("collect")

	# Hold the collect animation
	await get_tree().create_timer(.6).timeout

	# Can fades out where it sits — no teleporting or sliding
	if is_instance_valid(gold) and gold.has_method("collect"):
		gold.call("collect")
		_gold_pickups.erase(gold)

	await get_tree().create_timer(0.2).timeout
	_is_collecting = false
	if _state == State.COLLECTING:
		_play_anim("walk")


func _collect_bottle(bottle: Node2D) -> void:
	_is_collecting = true
	_play_anim("collect")

	await get_tree().create_timer(0.6).timeout

	if is_instance_valid(bottle):
		var s := get_node_or_null("/root/score")
		if s and s.has_method("add_pickup"):
			s.add_pickup(collect_value_cents)
		if bottle.has_method("_collect_then_respawn"):
			bottle.call("_collect_then_respawn")
		elif bottle.has_method("reset_pickup"):
			bottle.call("reset_pickup")

	await get_tree().create_timer(0.2).timeout
	_is_collecting = false
	if _state == State.COLLECTING:
		_play_anim("walk")


func _begin_exit() -> void:
	_state = State.THUMBSUP
	velocity = Vector2.ZERO
	_play_anim("thumbsup")

	# Hold thumbs up for 3 seconds then exit
	await get_tree().create_timer(3.0).timeout

	_state = State.EXITING
	_play_anim("walk")

	# Fade out any remaining gold pickups
	_fade_remaining_gold()


func _update_exiting() -> void:
	velocity = Vector2(-exit_speed, 0.0)
	if global_position.x < exit_x:
		queue_free()


# ── Gold pickup spawning ──
func _spawn_gold_wave(count: int) -> void:
	print("BUBBA: _spawn_gold_wave called, count=", count, " scene=", gold_pickup_scene)
	if gold_pickup_scene == null:
		print("BUBBA: gold_pickup_scene is NULL — assign bubba_gold_pickup.tscn in Inspector!")
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		print("BUBBA: current_scene is NULL!")
		return

	print("BUBBA: spawning ", count, " gold pickups into ", scene_root.name)
	for i in range(count):
		var g := gold_pickup_scene.instantiate() as Node2D
		if g == null:
			print("BUBBA: instantiate failed for gold pickup ", i)
			continue
		scene_root.add_child(g)
		_gold_pickups.append(g)
		print("BUBBA: gold pickup ", i, " spawned at ", g.global_position)


func _fade_remaining_gold() -> void:
	for g in _gold_pickups:
		if is_instance_valid(g) and g.has_method("fade_out"):
			g.call("fade_out")
	_gold_pickups.clear()


func _play_anim(anim_name: String) -> void:
	if anim == null or anim.sprite_frames == null:
		return
	if not anim.sprite_frames.has_animation(anim_name):
		return
	if anim_name == "collect":
		anim.sprite_frames.set_animation_loop("collect", false)
		# Always restart collect from frame 0 so it never double-plays
		anim.stop()
		anim.play(anim_name)
	elif anim.animation != anim_name:
		anim.play(anim_name)
