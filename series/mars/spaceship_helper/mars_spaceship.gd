# mars_spaceship.gd
# Mars Madness spaceship helper — mirrors bubba.gd in architecture.
#
# • Enters from the LEFT, exits to the RIGHT (opposite of Bubba).
# • Spawns GOLD CANS in two waves — only the spaceship can collect them.
# • Flies for ACTIVE_DURATION seconds collecting gold cans.
# • On exit: fades all remaining gold cans and queue_frees itself.
# • Triggered by gameplay_root at $20 in Mars game only (any room).
#
# Spawns gold cans via mars_gold_can.tscn.

extends CharacterBody2D

# ── Timing ──────────────────────────────────────────────────────────────
@export var active_duration:    float = 15.0
@export var collect_radius:     float = 90.0
@export var fly_speed:          float = 220.0
@export var exit_speed:         float = 300.0

# ── Gold can waves (mirrors Bubba's two-wave system) ─────────────────────
@export var gold_can_scene:     PackedScene = null   # assign mars_gold_can.tscn
@export var gold_wave_1_count:  int   = 10           # spawned on entry
@export var gold_wave_2_count:  int   = 8            # spawned mid-run
@export var gold_wave_2_delay:  float = 7.0          # seconds after entry

# ── Entry / exit positions ───────────────────────────────────────────────
@export var entry_x:  float = -120.0
@export var exit_x:   float = 2040.0
@export var entry_y:  float = 200.0

# ── World bounds for patrol ──────────────────────────────────────────────
@export var min_x: float = 100.0
@export var max_x: float = 1820.0
@export var min_y: float = 80.0
@export var max_y: float = 700.0

# ── Internal state ───────────────────────────────────────────────────────
enum State { ENTERING, COLLECTING, BEAMING, EXITING }
var _state:           int   = State.ENTERING
var _active_timer:    float = 0.0
var _wave_2_spawned:  bool  = false
var _target:          Node2D = null
var _gold_cans:       Array[Node] = []
var _is_collecting:   bool  = false
var _beam_alpha:      float = 0.0   # visual tractor-beam effect

# frozen is set by gameplay_root but spaceship keeps flying (same as Bubba)
var frozen: bool = false

# ── Visual: drawn in _draw() — no external texture needed ───────────────
var _draw_t: float = 0.0   # animation clock


func _ready() -> void:
	add_to_group("mars_spaceship")
	process_mode = Node.PROCESS_MODE_ALWAYS
	global_position = Vector2(entry_x, entry_y)
	# Spawn wave 1 immediately so cans exist before ship starts hunting
	_spawn_gold_wave(gold_wave_1_count)
	print("🚀 Mars Spaceship Helper entering!")


func _physics_process(delta: float) -> void:
	_draw_t += delta
	match _state:
		State.ENTERING:
			_update_entering()
		State.COLLECTING:
			_active_timer += delta

			if not _wave_2_spawned and _active_timer >= gold_wave_2_delay:
				_wave_2_spawned = true
				_spawn_gold_wave(gold_wave_2_count)

			if _active_timer >= active_duration:
				_begin_exit()
			else:
				_update_collecting(delta)
		State.BEAMING:
			velocity = Vector2.ZERO
		State.EXITING:
			_update_exiting()

	move_and_slide()
	queue_redraw()


# ── State: ENTERING ──────────────────────────────────────────────────────
func _update_entering() -> void:
	var target_x : float = min_x + 80.0
	if global_position.x < target_x:
		velocity = Vector2(fly_speed, 0.0)
	else:
		velocity = Vector2.ZERO
		_state = State.COLLECTING


# ── State: COLLECTING ────────────────────────────────────────────────────
func _update_collecting(delta: float) -> void:
	if _is_collecting:
		velocity = Vector2.ZERO
		return

	# Find the nearest gold can
	var gold := _find_nearest_gold()
	if gold != null:
		# Fly to a spot directly ABOVE the can (beam length = 160)
		var above_can := Vector2(gold.global_position.x +30.0,gold.global_position.y - 160.0)
		var to_above := above_can - global_position
		if to_above.length() <= 24.0:
			# Lined up above it — fire beam and pull it up
			_collect_gold(gold)
			return
		velocity = to_above.normalized() * fly_speed
		return

	# No gold left — patrol gently
	_patrol(delta)


func _patrol(delta: float) -> void:
	var t := _draw_t
	var tx : float = min_x + (max_x - min_x) * (0.5 + 0.4 * sin(t * 0.4))
	var ty : float = min_y + (max_y - min_y) * (0.3 + 0.2 * sin(t * 0.7))
	var to := Vector2(tx, ty) - global_position
	velocity = velocity.lerp(to.normalized() * fly_speed * 0.5, delta * 2.0)


# ── State: EXITING ───────────────────────────────────────────────────────
func _begin_exit() -> void:
	_state = State.EXITING
	_fade_remaining_gold()
	print("🚀 Mars Spaceship departing — fading gold cans!")


func _update_exiting() -> void:
	velocity = Vector2(exit_speed, 0.0)
	if global_position.x > exit_x:
		queue_free()


# ── Gold can search ──────────────────────────────────────────────────────
func _find_nearest_gold() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for g in get_tree().get_nodes_in_group("mars_gold_can"):
		if not is_instance_valid(g): continue
		if not (g is Node2D):        continue
		var n := g as Node2D
		if not n.visible:            continue
		var d := n.global_position.distance_to(global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest      = n
	return nearest


# ── Collection: beam fires DOWN, can rises UP to ship ────────────────────
func _collect_gold(gold: Node2D) -> void:
	_is_collecting = true
	_beam_alpha    = 1.0

	# Animate the can rising up through the beam to the ship
	if is_instance_valid(gold):
		var tween := create_tween()
		tween.tween_property(gold, "global_position",
			global_position + Vector2(0.0, 40.0), 0.45)\
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	await get_tree().create_timer(0.5).timeout

	if is_instance_valid(gold) and gold.has_method("collect"):
		gold.call("collect")
		_gold_cans.erase(gold)

	await get_tree().create_timer(0.1).timeout

	_beam_alpha    = 0.0
	_is_collecting = false


# ── Gold wave spawning (mirrors Bubba's _spawn_gold_wave) ────────────────
func _spawn_gold_wave(count: int) -> void:
	if gold_can_scene == null:
		push_error("MarsSpaceship: gold_can_scene is NULL — assign mars_gold_can.tscn in Inspector!")
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	for i in range(count):
		var g := gold_can_scene.instantiate() as Node2D
		if g == null:
			continue
		scene_root.add_child(g)
		_gold_cans.append(g)

	print("🚀 Mars Spaceship spawned ", count, " gold cans!")


func _fade_remaining_gold() -> void:
	for g in _gold_cans:
		if is_instance_valid(g) and g.has_method("fade_out"):
			g.call("fade_out")
	_gold_cans.clear()


# ── Drawn spaceship — no texture needed ──────────────────────────────────
func _draw() -> void:
	var t := _draw_t

	# Tractor beam — layered cone with animated scanlines
	if _beam_alpha > 0.01:
		var a := _beam_alpha

		# Outer beam cone (wide, dim)
		var outer_pts := PackedVector2Array([
			Vector2(-14, 44), Vector2(14, 44),
			Vector2(48, 160),  Vector2(-48, 160)
		])
		draw_colored_polygon(outer_pts, Color(0.2, 0.9, 1.0, a * 0.18))

		# Inner beam cone (narrower, brighter)
		var inner_pts := PackedVector2Array([
			Vector2(-7, 44), Vector2(7, 44),
			Vector2(22, 160), Vector2(-22, 160)
		])
		draw_colored_polygon(inner_pts, Color(0.5, 1.0, 1.0, a * 0.35))

		# Bright core line down the center
		draw_line(Vector2(0, 44), Vector2(0, 160),
			Color(1.0, 1.0, 1.0, a * 0.7), 2.0)

		# Animated horizontal scanlines travelling down the beam
		for i in range(5):
			var scan_y : float = 44.0 + fmod((t * 90.0 + i * 28.0), 116.0)
			var scan_w : float = (scan_y - 44.0) / 116.0 * 46.0
			var scan_a : float = (1.0 - abs(scan_y - 102.0) / 58.0) * a * 0.6
			draw_line(Vector2(-scan_w, scan_y), Vector2(scan_w, scan_y),
				Color(0.4, 1.0, 1.0, scan_a), 1.5)

		# Glow ring at beam mouth (under ship)
		draw_arc(Vector2(0, 44), 14.0, 0.0, TAU, 20,
			Color(0.3, 1.0, 1.0, a * 0.8), 2.0)

		# Glow ring at beam end (collection point)
		var pulse : float = 0.6 + 0.4 * sin(t * 8.0)
		draw_arc(Vector2(0, 160), 22.0, 0.0, TAU, 24,
			Color(0.2, 1.0, 0.8, a * pulse), 2.5)

	# Engine glow (bottom)
	var glow_r : float = 12.0 + sin(t * 8.0) * 3.0
	draw_circle(Vector2(0, 38), glow_r, Color(0.2, 0.8, 1.0, 0.45))

	# Main saucer body
	_draw_ellipse(Vector2(0, 0),   Vector2(52, 18), Color(0.30, 0.35, 0.70))
	_draw_ellipse(Vector2(0, -4),  Vector2(36, 14), Color(0.45, 0.50, 0.85))

	# Dome
	_draw_ellipse(Vector2(0, -18), Vector2(22, 16), Color(0.65, 0.80, 1.00, 0.85))

	# Rim lights (3 blinking dots)
	for i in range(3):
		var ang := t * 1.8 + i * TAU / 3.0
		var lx  : float = cos(ang) * 34.0
		var bright : float = 0.5 + 0.5 * sin(t * 4.0 + i * 2.1)
		draw_circle(Vector2(lx, 2), 4.0, Color(1.0, bright, 0.2, 0.9))


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(28):
		var a := TAU * i / 28.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)
