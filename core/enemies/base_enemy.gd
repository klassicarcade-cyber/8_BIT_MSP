# res://core/enemies/base_enemy.gd
extends CharacterBody2D
class_name BaseEnemy

@export var flip_enabled: bool = true
@export var flip_invert: bool = false          # ✅ NEW: fixes enemies whose art faces the "wrong" default way
@export var flip_deadzone: float = 1.0         # used for velocity checks
@export var position_deadzone_px: float = 0.5  # used for position-delta checks

# Optional: if you want to force a specific sprite node, set this in Inspector
@export var sprite_path: NodePath = NodePath("")

var _sprite2d: Sprite2D
var _anim_sprite2d: AnimatedSprite2D

var _last_x: float = 0.0
var _has_last_x: bool = false

func _ready() -> void:
	_cache_visual_node()
	_last_x = global_position.x
	_has_last_x = true

func _process(delta: float) -> void:
	_update_facing_from_motion()
	_last_x = global_position.x
	_has_last_x = true

func _cache_visual_node() -> void:
	_sprite2d = null
	_anim_sprite2d = null

	# 1) If sprite_path set, use it
	if sprite_path != NodePath("") and has_node(sprite_path):
		var n := get_node(sprite_path)
		_sprite2d = n as Sprite2D
		_anim_sprite2d = n as AnimatedSprite2D
		return

	# 2) Otherwise, find first Sprite2D or AnimatedSprite2D anywhere under this enemy (by TYPE)
	var found := _find_first_visual(self)
	if found is Sprite2D:
		_sprite2d = found
	elif found is AnimatedSprite2D:
		_anim_sprite2d = found

func _find_first_visual(node: Node) -> Node:
	for child in node.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			return child
		var deeper := _find_first_visual(child)
		if deeper != null:
			return deeper
	return null

func _set_flip(left: bool) -> void:
	# flip_h = true means face LEFT
	# flip_invert swaps the meaning for backwards-facing art
	var actual_left := left
	if flip_invert:
		actual_left = not left

	if _sprite2d != null:
		_sprite2d.flip_h = actual_left
	elif _anim_sprite2d != null:
		_anim_sprite2d.flip_h = actual_left

func _update_facing_from_motion() -> void:
	if not flip_enabled:
		return

	# If we somehow lost the visual node, try recaching (safe, cheap)
	if _sprite2d == null and _anim_sprite2d == null:
		_cache_visual_node()
		if _sprite2d == null and _anim_sprite2d == null:
			return

	# 1) Prefer velocity (works for proper CharacterBody2D motion)
	var vx := velocity.x
	if abs(vx) > flip_deadzone:
		_set_flip(vx < 0.0)
		return

	# 2) Fallback: infer direction from actual movement in world (works even if you change position directly)
	if _has_last_x:
		var dx := global_position.x - _last_x
		if abs(dx) > position_deadzone_px:
			_set_flip(dx < 0.0)
