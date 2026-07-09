# arcade_sign.gd
# Animates the Klassic Arcade neon sign on bg_gob_ka (room index 1).
#
# Save as: res://series/gob/arcade_sign.gd

extends Node2D

# ── Sign region (world coordinates 1920×1080) ──
@export var sign_rect: Rect2 = Rect2(660, 175, 595, 240)
@export var border_radius: float = 18.0
@export var border_width: float = 8.0
@export var glow_width: float = 22.0

# ── Colour cycle ──
const COLOURS: Array = [
	Color(0.0,  0.8,  1.0),   # cyan/blue
	Color(1.0,  0.1,  0.4),   # hot pink
	Color(0.4,  1.0,  0.2),   # neon green
	Color(1.0,  0.6,  0.0),   # orange
	Color(0.7,  0.2,  1.0),   # purple
]

@export var cycle_speed: float  = 0.25
@export var flicker_chance: float = 0.004

var _colour_index:  int   = 0
var _next_index:    int   = 1
var _colour_t:      float = 0.0
var _flicker:       bool  = false
var _flicker_timer: float = 0.0
var _time:          float = 0.0


func _ready() -> void:
	z_index = -1
	# Debug: confirm the node is alive
	print("✅ ArcadeSign _ready() — position: ", global_position)


func _process(delta: float) -> void:
	_time += delta

	_colour_t += delta * cycle_speed
	if _colour_t >= 1.0:
		_colour_t    -= 1.0
		_colour_index = _next_index
		_next_index   = (_next_index + 1) % COLOURS.size()

	if _flicker:
		_flicker_timer -= delta
		if _flicker_timer <= 0.0:
			_flicker = false
	elif randf() < flicker_chance:
		_flicker       = true
		_flicker_timer = randf_range(0.04, 0.18)

	queue_redraw()


func _draw() -> void:
	var col: Color = COLOURS[_colour_index].lerp(COLOURS[_next_index], _colour_t)

	if _flicker:
		# During flicker draw very dim
		col.a = 0.05
	
	var r:  Rect2 = sign_rect
	var rr: float = border_radius

	# Outer glow
	_draw_rounded_border(r.grow(glow_width * 0.5), rr + glow_width * 0.5,
						glow_width * 2.0, Color(col.r, col.g, col.b, 0.15))
	# Mid glow
	_draw_rounded_border(r.grow(glow_width * 0.25), rr + glow_width * 0.25,
						glow_width, Color(col.r, col.g, col.b, 0.30))
	# Core neon tube
	_draw_rounded_border(r, rr, border_width, Color(col.r, col.g, col.b, 0.95))
	# Bright centre line
	_draw_rounded_border(r, rr, border_width * 0.35,
						Color(min(col.r+0.4,1.0), min(col.g+0.4,1.0), min(col.b+0.4,1.0), 0.9))


func _draw_rounded_border(r: Rect2, radius: float, width: float, col: Color) -> void:
	radius = min(radius, min(r.size.x, r.size.y) * 0.5)
	var pts: PackedVector2Array = PackedVector2Array()
	var segs: int = 12

	for i in range(segs + 1):
		var a: float = PI + (PI * 0.5) * (float(i) / segs)
		pts.append(Vector2(r.position.x + radius + cos(a) * radius,
						   r.position.y + radius + sin(a) * radius))
	for i in range(segs + 1):
		var a: float = PI * 1.5 + (PI * 0.5) * (float(i) / segs)
		pts.append(Vector2(r.position.x + r.size.x - radius + cos(a) * radius,
						   r.position.y + radius + sin(a) * radius))
	for i in range(segs + 1):
		var a: float = 0.0 + (PI * 0.5) * (float(i) / segs)
		pts.append(Vector2(r.position.x + r.size.x - radius + cos(a) * radius,
						   r.position.y + r.size.y - radius + sin(a) * radius))
	for i in range(segs + 1):
		var a: float = PI * 0.5 + (PI * 0.5) * (float(i) / segs)
		pts.append(Vector2(r.position.x + radius + cos(a) * radius,
						   r.position.y + r.size.y - radius + sin(a) * radius))

	pts.append(pts[0])
	draw_polyline(pts, col, width, true)
   
