# fogger.gd
# Paw Paw enemy: Fogger
# Behavior: Positions between player and nearest pickup (Blocker).
# When player gets close, spawns an animated cloud that drifts across screen.

extends CharacterBody2D

@export var move_speed: float = 160.0
@export var block_offset: float = 120.0

# --- FOG ---
@export var fog_trigger_distance: float = 150.0
@export var fog_duration: float = 4.5
@export var fog_cooldown: float = 6.0
@export var fog_alpha: float = 0.78           # cloud transparency
@export var fog_scale: float = 1.4            # cloud size multiplier
@export var fog_drift_speed: float = 22.0     # px per second drift right

# --- CLAMP ---
@export var min_y: float = 120.0
@export var max_y: float = 900.0
@export var min_x: float = 120.0
@export var max_x: float = 1800.0

var frozen: bool = false
var player: Node2D = null
var _fog_timer: float = 0.0
var _fog_cooldown_timer: float = 0.0

# Cloud node — AnimatedSprite2D on a CanvasLayer above the game
var _cloud_canvas: CanvasLayer = null
var _cloud_anim: AnimatedSprite2D = null

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var sprite2d: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var steal_sfx: AudioStreamPlayer = get_node_or_null("StealSFX") as AudioStreamPlayer


func _ready() -> void:
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_play_anim("idle")
	_fog_timer = 0.0
	_fog_cooldown_timer = 0.0
	_build_cloud()
	# Clean up cloud when Fogger is removed from scene
	tree_exiting.connect(_cleanup_cloud)


func _cleanup_cloud() -> void:
	_hide_fog()
	if _cloud_canvas and is_instance_valid(_cloud_canvas):
		_cloud_canvas.queue_free()
	_cloud_canvas = null
	_cloud_anim = null


func _build_cloud() -> void:
	_cloud_canvas = CanvasLayer.new()
	_cloud_canvas.layer = 49
	get_tree().root.add_child(_cloud_canvas)

	_cloud_anim = AnimatedSprite2D.new()
	_cloud_anim.visible = false
	_cloud_anim.scale = Vector2(fog_scale, fog_scale)
	_cloud_anim.modulate = Color(1.0, 1.0, 1.0, fog_alpha)

	# Load the sprite sheet and build SpriteFrames
	var texture: Texture2D = load("res://series/paw/enemies/fogger/cloud_fogger.png")
	if texture:
		var frames := SpriteFrames.new()
		frames.add_animation("puff")
		frames.set_animation_loop("puff", true)
		frames.set_animation_speed("puff", 8.0)

		# 4 columns x 4 rows = 16 frames
		var hframes := 4
		var vframes := 4
		var frame_w := texture.get_width() / hframes
		var frame_h := texture.get_height() / vframes

		for row in range(vframes):
			for col in range(hframes):
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
				frames.add_frame("puff", atlas)

		_cloud_anim.sprite_frames = frames
		_cloud_anim.play("puff")
	else:
		push_warning("Fogger: cloud_fogger.png not found at res://series/paw/enemies/fogger/cloud_fogger.png")

	_cloud_canvas.add_child(_cloud_anim)


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_hide_fog()
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_fog_cooldown_timer = maxf(0.0, _fog_cooldown_timer - delta)

	# Update fog
	if _fog_timer > 0.0:
		_fog_timer -= delta
		if _fog_timer <= 0.0:
			_hide_fog()
		else:
			# Drift cloud slowly to the right
			if _cloud_anim and _cloud_anim.visible:
				_cloud_anim.position.x += fog_drift_speed * delta
			_show_fog()

	# Blocker: move between player and nearest pickup
	var target_pos := _get_block_position()
	if target_pos != Vector2.ZERO:
		var to_target := target_pos - global_position
		if to_target.length() > 8.0:
			velocity = to_target.normalized() * move_speed
			_play_anim("walk")
		else:
			velocity = Vector2.ZERO
			_play_anim("idle")
	else:
		velocity = Vector2.ZERO
		_play_anim("idle")

	move_and_slide()
	_clamp_to_play_area()
	_update_facing()

	# Fog trigger
	var dist_to_player := global_position.distance_to(player.global_position)
	if dist_to_player <= fog_trigger_distance and _fog_cooldown_timer <= 0.0 and _fog_timer <= 0.0:
		_trigger_fog()


func _get_block_position() -> Vector2:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not node.visible:
			continue
		var d: float = player.global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	if nearest == null:
		return Vector2.ZERO
	var to_player := (player.global_position - nearest.global_position).normalized()
	return nearest.global_position + to_player * block_offset


func _trigger_fog() -> void:
	_fog_timer = fog_duration
	_fog_cooldown_timer = fog_cooldown
	_play_anim("attack")
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	# Position cloud near player in screen space
	if _cloud_anim:
		var screen_pos := get_viewport().get_canvas_transform() * player.global_position
		_cloud_anim.position = screen_pos + Vector2(
			randf_range(-120.0, 120.0),
			randf_range(-80.0, 80.0)
		)
	_show_fog()


func _show_fog() -> void:
	if _cloud_anim:
		_cloud_anim.visible = true
		if not _cloud_anim.is_playing():
			_cloud_anim.play("puff")


func _hide_fog() -> void:
	if _cloud_anim:
		_cloud_anim.visible = false


func _clamp_to_play_area() -> void:
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, min_y, max_y)


func _update_facing() -> void:
	if abs(velocity.x) < 1.0:
		return
	var face_left := velocity.x < 0.0
	if sprite:
		sprite.flip_h = face_left
	if sprite2d:
		sprite2d.flip_h = face_left


func _play_anim(anim_name: String) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name:
			sprite.play(anim_name)
