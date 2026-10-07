# res://series/gob/arcade_sign.gd
# Animates the Klassic Arcade sign border on bg_gob_ka (room index 1).
# Draws a chasing incandescent-bulb marquee border around sign_rect.
#
# Save as: res://series/gob/arcade_sign.gd

extends Node2D

# ── Sign region (world coordinates 1920×1080) ──
# Measured directly from bg_gob_ka.png: the painted yellow tube ring
# runs roughly x 627–1301, y 187–457, so this is that ring's centerline.
# If it's still off by a few pixels once you see it in-game, turn on
# show_debug_outline below and nudge these four numbers to match.
@export var sign_rect: Rect2 = Rect2(630, 190, 670, 265)
@export var border_radius: float = 32.0

# ── Debug helper ──
# While true, draws a thin bright outline of sign_rect with no bulbs,
# so you can see exactly where the rect sits against the background.
@export var show_debug_outline: bool = false

# ── Bulb appearance ──
@export var bulb_radius: float = 7.0
@export var bulb_spacing: float = 26.0          # target distance between bulb centers
@export var glow_radius_mult: float = 2.4        # glow halo size relative to bulb_radius
@export var bulb_color_lit: Color = Color(1.0, 0.82, 0.45)
@export var bulb_color_dim: Color = Color(0.30, 0.20, 0.10)
@export var socket_color: Color = Color(0.08, 0.07, 0.07, 0.9)  # small base under each bulb

# ── Chase animation ──
@export var chase_speed: float = 5.0             # bulbs advanced per second
@export var chase_lit_run: int = 3                # consecutive lit bulbs per group
@export var chase_gap_run: int = 3                # consecutive dark bulbs per group

# ── Random incandescent flicker (subtle, per-bulb) ──
@export var flicker_chance: float = 0.01          # chance per bulb per second to flicker
@export var flicker_dim_amount: float = 0.5       # how much brightness drops during flicker

var _bulb_positions: PackedVector2Array = PackedVector2Array()
var _bulb_flicker_timer: PackedFloat32Array = PackedFloat32Array()
var _chase_phase: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	z_index = -1
	_rebuild_bulbs()


func _rebuild_bulbs() -> void:
	var perimeter_pts: PackedVector2Array = _rounded_rect_points(sign_rect, border_radius, 12)

	# total perimeter length
	var total_len: float = 0.0
	for i in range(perimeter_pts.size() - 1):
		total_len += perimeter_pts[i].distance_to(perimeter_pts[i + 1])

	var bulb_count: int = max(int(round(total_len / bulb_spacing)), 4)
	var actual_spacing: float = total_len / float(bulb_count)

	_bulb_positions.clear()
	_bulb_flicker_timer.resize(bulb_count)
	for i in range(bulb_count):
		_bulb_flicker_timer[i] = 0.0

	var target_dist: float = 0.0
	var walked: float = 0.0
	var seg_index: int = 0
	_bulb_positions.append(perimeter_pts[0])

	for i in range(1, bulb_count):
		target_dist = i * actual_spacing
		while seg_index < perimeter_pts.size() - 1:
			var seg_start: Vector2 = perimeter_pts[seg_index]
			var seg_end: Vector2 = perimeter_pts[seg_index + 1]
			var seg_len: float = seg_start.distance_to(seg_end)
			if walked + seg_len >= target_dist:
				var t: float = 0.0
				if seg_len > 0.0:
					t = (target_dist - walked) / seg_len
				_bulb_positions.append(seg_start.lerp(seg_end, t))
				break
			else:
				walked += seg_len
				seg_index += 1
		if seg_index >= perimeter_pts.size() - 1 and _bulb_positions.size() <= i:
			_bulb_positions.append(perimeter_pts[perimeter_pts.size() - 1])


func _process(delta: float) -> void:
	_time += delta
	_chase_phase += delta * chase_speed
	var cycle_len: float = float(chase_lit_run + chase_gap_run)
	if _chase_phase >= cycle_len:
		_chase_phase = fmod(_chase_phase, cycle_len)

	for i in range(_bulb_flicker_timer.size()):
		if _bulb_flicker_timer[i] > 0.0:
			_bulb_flicker_timer[i] -= delta
		elif randf() < flicker_chance * delta * 60.0:
			_bulb_flicker_timer[i] = randf_range(0.05, 0.2)

	queue_redraw()


func _draw() -> void:
	if show_debug_outline:
		draw_rect(sign_rect, Color(1, 0, 1, 0.9), false, 3.0)
		return

	var count: int = _bulb_positions.size()
	if count == 0:
		return

	var cycle_len: int = chase_lit_run + chase_gap_run

	for i in range(count):
		var pos: Vector2 = _bulb_positions[i]

		var slot: int = int(floor(fmod(float(i) - _chase_phase + float(count) * 1000.0, float(cycle_len))))
		var is_lit: bool = slot < chase_lit_run

		var col: Color = bulb_color_lit if is_lit else bulb_color_dim

		if _bulb_flicker_timer[i] > 0.0:
			col = col.darkened(flicker_dim_amount)

		# glow halo (only meaningful when lit)
		if is_lit:
			var glow_col: Color = Color(col.r, col.g, col.b, 0.35)
			draw_circle(pos, bulb_radius * glow_radius_mult, glow_col)
			var glow_col2: Color = Color(col.r, col.g, col.b, 0.15)
			draw_circle(pos, bulb_radius * glow_radius_mult * 1.6, glow_col2)

		# socket base, then bulb on top
		draw_circle(pos, bulb_radius * 1.25, socket_color)
		draw_circle(pos, bulb_radius, col)

		# small bright highlight for a glassy look
		if is_lit:
			draw_circle(pos + Vector2(-bulb_radius * 0.3, -bulb_radius * 0.3),
						bulb_radius * 0.35, Color(1, 1, 1, 0.6))


func _rounded_rect_points(r: Rect2, radius: float, segs: int) -> PackedVector2Array:
	var rr: float = min(radius, min(r.size.x, r.size.y) * 0.5)
	var pts: PackedVector2Array = PackedVector2Array()

	for i in range(segs + 1):
		var a: float = PI + (PI * 0.5) * (float(i) / segs)
		pts.append(Vector2(r.position.x + rr + cos(a) * rr,
						   r.position.y + rr + sin(a) * rr))
	for i in range(segs + 1):
		var a: float = PI * 1.5 + (PI * 0.5) * (float(i) / segs)
		pts.append(Vector2(r.position.x + r.size.x - rr + cos(a) * rr,
						   r.position.y + rr + sin(a) * rr))
	for i in range(segs + 1):
		var a: float = 0.0 + (PI * 0.5) * (float(i) / segs)
		pts.append(Vector2(r.position.x + r.size.x - rr + cos(a) * rr,
						   r.position.y + r.size.y - rr + sin(a) * rr))
	for i in range(segs + 1):
		var a: float = PI * 0.5 + (PI * 0.5) * (float(i) / segs)
		pts.append(Vector2(r.position.x + rr + cos(a) * rr,
						   r.position.y + r.size.y - rr + sin(a) * rr))

	pts.append(pts[0])
	return pts
