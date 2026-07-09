extends CharacterBody2D

# --------------------------------------------------
# NOTE:
# This project uses AutoLoad `score` (res://core/systems/score.gd).
# Do NOT replace with scene-based score nodes unless refactoring globally.
# --------------------------------------------------

@export var speed: float = 420.0

const ANIM_IDLE := "idle"
const ANIM_WALK := "walk"
const MOVE_EPS := 0.1
const FLIP_EPS := 0.01

const WORLD_W := 1920.0
const WORLD_H := 1080.0

# --------------------------------------------------
# LANE CLAMP (optional): keeps player inside your "playfield lane"
# Turn on if you want the player to match enemy lane limits (Buzz/Fang).
# --------------------------------------------------
@export var lane_enabled: bool = true
@export var lane_min_x: float = 40.0
@export var lane_max_x: float = 1880.0
@export var lane_min_y: float = 20.0
@export var lane_max_y: float = 1040.0
@export var lane_foot_offset: float = 0.0   # set 20-80 if sprite looks too low

# --- Visual options (either system can exist per series) ---
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var anim: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var move_sound: AudioStreamPlayer2D = get_node_or_null("MoveSound") as AudioStreamPlayer2D

# Score system (autoload)
var score_sys: Node = null

# Freeze flag (controlled by GameplayRoot)
var frozen: bool = false

# Slow effect (Lady)
var _speed_mult: float = 1.0
var _slow_timer: float = 0.0

# Move SFX state
var _was_moving: bool = false

# Steal-hit tween safety
var _steal_tween: Tween = null

# Visual node we actually manipulate (Sprite2D OR AnimatedSprite2D)
var _visual: Node2D = null

# We respect whatever visual scale you set in the editor (ex: 0.22)
var _base_visual_scale: Vector2 = Vector2.ONE


# --------------------------------------------------
# Visual selection rules:
# We ONLY use AnimatedSprite2D if it's explicitly "ready":
# - anim_sprite exists
# - anim_sprite.visible is true (so you can disable it per series)
# - SpriteFrames exist
# - has animations "idle" and "walk"
# Otherwise we fall back to Sprite2D + AnimationPlayer.
# --------------------------------------------------
func _can_use_sprite_sheet() -> bool:
	if anim_sprite == null:
		return false
	if not anim_sprite.visible:
		return false
	if anim_sprite.sprite_frames == null:
		return false

	var sf := anim_sprite.sprite_frames
	return sf.has_animation(ANIM_IDLE) and sf.has_animation(ANIM_WALK)


func _choose_visual() -> void:
	var use_sheet := _can_use_sprite_sheet()

	if use_sheet:
		_visual = anim_sprite
		if sprite: sprite.visible = false
	else:
		_visual = sprite
		if anim_sprite: anim_sprite.visible = false
		if sprite: sprite.visible = true


func _ready() -> void:
	# HARD LOCK: Player node scale never changes (fixes “tiny then grows”)
	scale = Vector2.ONE

	add_to_group("player")
	_resolve_score_autoload()

	_choose_visual()

	if _visual:
		_base_visual_scale = _visual.scale

	velocity = Vector2.ZERO
	_stop_move_sound()
	_play_idle()


# GameplayRoot calls this
func set_frozen(v: bool) -> void:
	frozen = v
	if frozen:
		velocity = Vector2.ZERO
		_stop_move_sound()
		_play_idle()


func _physics_process(delta: float) -> void:
	# ✅ ABSOLUTE NO-MOVE STATE:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_apply_clamps()
		_stop_move_sound()
		_play_idle()
		return

	# Tick slow timer (Lady)
	if _slow_timer > 0.0:
		_slow_timer = maxf(0.0, _slow_timer - delta)
		if _slow_timer == 0.0:
			_speed_mult = 1.0

	# Input
	var input_dir := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		velocity = input_dir * (speed * _speed_mult)
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	_apply_clamps()
	_update_animation()
	_flip_sprite()
	_update_move_sound()


func _apply_clamps() -> void:
	# World clamp first (keeps physics sane)
	_clamp_to_world()
	# Then lane clamp (your “arcade lane” limits)
	_clamp_to_lane()


func _resolve_score_autoload() -> void:
	score_sys = get_node_or_null("/root/score")
	if score_sys == null:
		var scores := get_tree().get_nodes_in_group("score")
		if scores.size() > 0:
			score_sys = scores[0]


# --------------------------------------------------
# Louie/Buzz steal hook
# Player handles score decrement + hit feedback only.
# --------------------------------------------------
func on_stolen_from(steal_cents: int, thief_id: String = "") -> void:
	if score_sys == null or not is_instance_valid(score_sys):
		_resolve_score_autoload()

	if score_sys and score_sys.has_method("steal"):
		score_sys.steal(steal_cents)
	elif score_sys and score_sys.has_method("add_pickup"):
		score_sys.add_pickup(-steal_cents)

	_play_steal_anim(thief_id)


func _play_steal_anim(thief_id: String) -> void:
	if _visual == null:
		return

	var punch := 1.10
	if thief_id == "buzz":
		punch = 1.16

	if _steal_tween and is_instance_valid(_steal_tween):
		_steal_tween.kill()

	_visual.scale = _base_visual_scale

	_steal_tween = create_tween()
	_steal_tween.set_trans(Tween.TRANS_BACK)
	_steal_tween.set_ease(Tween.EASE_OUT)
	_steal_tween.tween_property(_visual, "scale", _base_visual_scale * punch, 0.06)
	_steal_tween.tween_property(_visual, "scale", _base_visual_scale, 0.10)


func apply_slow(mult: float, seconds: float) -> void:
	_speed_mult = clampf(mult, 0.1, 1.0)
	_slow_timer = maxf(_slow_timer, seconds)

func clear_slow() -> void:
	_speed_mult = 1.0
	_slow_timer = 0.0


func _update_move_sound() -> void:
	if move_sound == null:
		return

	var is_moving := velocity.length() > 10.0

	if is_moving and not _was_moving:
		move_sound.pitch_scale = randf_range(0.96, 1.04)
		# move_sound.play()
	elif (not is_moving) and _was_moving:
		_stop_move_sound()

	_was_moving = is_moving


func _stop_move_sound() -> void:
	if move_sound and move_sound.playing:
		move_sound.stop()
	_was_moving = false


# --------------------------------------------------
# Clamp helpers
# --------------------------------------------------
func _get_collision_half_extents() -> Vector2:
	var half_w := 48.0
	var half_h := 48.0

	if collision and collision.shape:
		if collision.shape is RectangleShape2D:
			var s := collision.shape as RectangleShape2D
			half_w = s.size.x * 0.5
			half_h = s.size.y * 0.5
		elif collision.shape is CapsuleShape2D:
			var c := collision.shape as CapsuleShape2D
			half_w = c.radius
			half_h = (c.height * 0.5) + c.radius
		elif collision.shape is CircleShape2D:
			var cir := collision.shape as CircleShape2D
			half_w = cir.radius
			half_h = cir.radius

	var pad := 6.0
	return Vector2(half_w + pad, half_h + pad)


# --------------------------------------------------
# World clamp (collision-aware)
# --------------------------------------------------
func _clamp_to_world() -> void:
	var half := _get_collision_half_extents()
	global_position.x = clampf(global_position.x, half.x, WORLD_W - half.x)
	global_position.y = clampf(global_position.y, half.y, WORLD_H - half.y)


# --------------------------------------------------
# Lane clamp (collision-aware too, matches enemy lane feel)
# --------------------------------------------------
func _clamp_to_lane() -> void:
	if not lane_enabled:
		return

	var half := _get_collision_half_extents()
	var p := global_position

	p.x = clampf(p.x, lane_min_x + half.x, lane_max_x - half.x)

	# Top uses half.y, bottom uses foot offset too (optional)
	var top := lane_min_y + half.y
	var bottom := (lane_max_y - lane_foot_offset) - half.y
	p.y = clampf(p.y, top, bottom)

	global_position = p


func _update_animation() -> void:
	# Sprite sheet path (only when explicitly enabled/valid)
	if _can_use_sprite_sheet():
		if velocity.length() >= MOVE_EPS:
			if anim_sprite.animation != ANIM_WALK:
				anim_sprite.play(ANIM_WALK)
		else:
			_play_idle()
		return

	# Classic AnimationPlayer path (other series)
	if anim == null:
		return

	if velocity.length() >= MOVE_EPS:
		if anim.current_animation != ANIM_WALK:
			anim.play(ANIM_WALK)
	else:
		_play_idle()


func _play_idle() -> void:
	if _can_use_sprite_sheet():
		if anim_sprite.animation != ANIM_IDLE:
			anim_sprite.play(ANIM_IDLE)
		return

	if anim and anim.current_animation != ANIM_IDLE:
		anim.play(ANIM_IDLE)


func _flip_sprite() -> void:
	if _visual == null:
		return
	if absf(velocity.x) <= FLIP_EPS:
		return

	# Both Sprite2D and AnimatedSprite2D support flip_h
	if _visual.has_method("set_flip_h"):
		_visual.set_flip_h(velocity.x < 0)
	elif "flip_h" in _visual:
		_visual.flip_h = velocity.x < 0
