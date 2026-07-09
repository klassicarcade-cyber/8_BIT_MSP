# star_twinkle.gd
# Draws twinkling, color-shifting stars inside the cockpit windows.
# All values are exported so you can tweak them live in the Godot Inspector.
#
# Save as: res://series/mars/star_twinkle.gd

extends Node2D

# ── Window regions — adjust in Inspector (x, y, width, height) ──
@export var window_left:        Rect2 = Rect2(195, 210, 200, 170)
@export var window_right:       Rect2 = Rect2(1590, 265, 90, 160)
@export var window_strip_left:  Rect2 = Rect2(600, 300, 175, 28)
@export var window_strip_right: Rect2 = Rect2(1175, 300, 175, 28)

# ── Star counts ──
@export var stars_per_window: int = 10
@export var stars_per_strip:  int = 6

# ── Twinkle feel ──
@export var min_radius: float = 1.5
@export var max_radius: float = 3.5
@export var min_period: float = 1.2
@export var max_period: float = 3.8
@export var min_alpha:  float = 0.15
@export var max_alpha:  float = 0.8

# ── Colours — yellow, blue, red ──
const COLOURS: Array = [
	Color(1.00, 1.00, 0.20),   # yellow
	Color(1.00, 0.85, 0.00),   # deep yellow
	Color(0.30, 0.60, 1.00),   # blue
	Color(0.15, 0.40, 1.00),   # deep blue
	Color(1.00, 0.15, 0.15),   # red
	Color(1.00, 0.40, 0.40),   # soft red
]

var _stars: Array = []


func _ready() -> void:
	z_index = 1
	_place_stars()


func _place_stars() -> void:
	_stars.clear()
	for window in [window_left, window_right]:
		for i in range(stars_per_window):
			_add_star(window)
	for strip in [window_strip_left, window_strip_right]:
		for i in range(stars_per_strip):
			_add_star(strip)


func _add_star(region: Rect2) -> void:
	var s := {
		"pos":    Vector2(
					region.position.x + randf() * region.size.x,
					region.position.y + randf() * region.size.y),
		"radius": randf_range(min_radius, max_radius),
		"color":  COLOURS[randi() % COLOURS.size()],
		"color2": COLOURS[randi() % COLOURS.size()],
		"period": randf_range(min_period, max_period),
		"phase":  randf() * TAU,
	}
	_stars.append(s)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for s in _stars:
		var cycle: float = (sin((t / s["period"]) * TAU + s["phase"]) + 1.0) * 0.5
		var alpha: float = lerp(min_alpha, max_alpha, cycle)

		var color_cycle: float = (sin((t / (s["period"] * 3.0)) * TAU + s["phase"]) + 1.0) * 0.5
		var col: Color = s["color"].lerp(s["color2"], color_cycle)
		col.a = alpha

		var r: float = s["radius"]
		draw_circle(s["pos"], r * 2.0, Color(col.r, col.g, col.b, alpha * 0.1))
		draw_circle(s["pos"], r, col)
