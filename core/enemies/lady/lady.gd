extends BaseEnemy

@export var move_speed: float = 160.0
@export var steering: float = 8.0
@export var max_speed: float = 240.0

@export var slow_radius: float = 240.0
@export var slow_mult: float = 0.40
@export var slow_refresh: float = 0.15
@export var stop_distance: float = 90.0

@export var attach_duration: float = 11.0
@export var release_cooldown: float = 4.0

@export var slow_shake_strength: float = 2.5
@export var slow_shake_time: float = 0.06

@export var min_y: float = 120.0
@export var max_y: float = 880.0

@export var chirp_min_db: float = -18.0
@export var chirp_max_db: float = -6.0
@export var chirp_fade_speed: float = 10.0

@export var steal_sfx_db: float = -6.0

var frozen: bool = false
var _slow_timer: float = 0.0

var _attached: bool = false
var _attach_timer: float = 0.0
var _cooldown_timer: float = 0.0

@onready var chirp_sfx = get_node_or_null("ChirpSFX")
@onready var steal_sfx = get_node_or_null("StealSFX")
@onready var aura_sfx = get_node_or_null("AuraSFX")

# ✅ NEW: Animation
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemy")
	_slow_timer = 0.0
	_force_audio_off()


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_clamp_y()
		_stop_all_audio()
		_update_animation()
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		_clamp_y()
		_stop_all_audio()
		_update_animation()
		return

	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
		_move_toward_player(player, delta)
		move_and_slide()
		_clamp_y()
		_stop_chirp_only()
		_update_animation()
		return

	if _attached:
		_attach_timer -= delta
		_move_toward_player(player, delta)
		move_and_slide()
		_clamp_y()
		_update_chirp_attached(delta)
		_update_animation()

		if _attach_timer <= 0.0:
			_release(player)
		return

	_slow_timer = maxf(0.0, _slow_timer - delta)

	_move_toward_player(player, delta)
	move_and_slide()
	_clamp_y()
	_stop_chirp_only()

	var dist: float = (player.global_position - global_position).length()
	if dist <= slow_radius:
		_attach(player)

	_update_animation()


func _update_animation() -> void:
	if anim == null:
		return

	# Attach animation has priority
	if _attached:
		anim.play("attach")
	elif velocity.length() > 20:
		anim.play("walk")
	else:
		anim.play("idle")

	if velocity.x != 0:
		anim.flip_h = velocity.x < 0


func _clamp_y() -> void:
	var p := global_position
	p.y = clamp(p.y, min_y, max_y)
	global_position = p


func _move_toward_player(player: Node2D, delta: float) -> void:
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	var dir: Vector2 = to_player / maxf(dist, 0.001)

	var target_speed: float = move_speed
	if dist < stop_distance:
		var t: float = clampf(dist / maxf(stop_distance, 0.001), 0.0, 1.0)
		target_speed = lerpf(0.0, move_speed, t)

	var desired: Vector2 = dir * target_speed
	velocity = velocity.lerp(desired, steering * delta)

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed


func _attach(player: Node2D) -> void:
	if _attached:
		return

	_attached = true
	_attach_timer = attach_duration

	_play_steal_sfx()

	if player.has_method("apply_slow"):
		player.call("apply_slow", slow_mult, attach_duration)

	get_tree().call_group("camera", "shake", slow_shake_strength, slow_shake_time)

	if aura_sfx and aura_sfx.stream:
		aura_sfx.play()

	_start_chirp()


func _release(player: Node2D) -> void:
	if not _attached:
		return

	_attached = false
	_attach_timer = 0.0
	_cooldown_timer = release_cooldown

	_play_steal_sfx()

	if player.has_method("clear_slow"):
		player.call("clear_slow")

	_stop_chirp_only()


func _start_chirp() -> void:
	if chirp_sfx == null or chirp_sfx.stream == null:
		return
	chirp_sfx.stream_paused = false
	chirp_sfx.volume_db = chirp_min_db
	if not chirp_sfx.playing:
		chirp_sfx.play()


func _update_chirp_attached(delta: float) -> void:
	if chirp_sfx == null or chirp_sfx.stream == null:
		return

	var smooth := minf(chirp_fade_speed * delta, 1.0)
	chirp_sfx.volume_db = lerpf(float(chirp_sfx.volume_db), chirp_max_db, smooth)

	if not chirp_sfx.playing:
		chirp_sfx.play()


func _stop_chirp_only() -> void:
	if chirp_sfx and chirp_sfx.playing:
		chirp_sfx.stop()


func _play_steal_sfx() -> void:
	if steal_sfx == null or steal_sfx.stream == null:
		return
	steal_sfx.volume_db = steal_sfx_db
	steal_sfx.play()


func _stop_all_audio() -> void:
	for p in [chirp_sfx, steal_sfx, aura_sfx]:
		if p and p.playing:
			p.stop()


func _force_audio_off() -> void:
	for p in [chirp_sfx, steal_sfx, aura_sfx]:
		if p == null:
			continue
		p.autoplay = false
		p.stream_paused = false
		if p.playing:
			p.stop()
