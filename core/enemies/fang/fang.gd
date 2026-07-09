extends BaseEnemy

# --------------------------------------------------
# FANG (Option B): Ambusher + "Wipes" nearby pickups (TEMPORARY)
# Vanish -> Reappear near player -> Strike
# On strike, forces nearby pickups to run their own _collect_then_respawn()
# --------------------------------------------------

@export var stalk_speed: float = 90.0
@export var strike_speed: float = 720.0
@export var steering: float = 12.0
@export var max_speed: float = 540.0

@export var cooldown_time: float = 2.47
@export var vanish_time: float = 4.60
@export var strike_time: float = 0.55

@export var appear_distance: float = 260.0
@export var appear_min_distance: float = 140.0
@export var appear_tries: int = 10

@export var wipe_radius: float = 930.0
@export var wipe_cooldown: float = 2.0
@export var wipe_max_per_strike: int = 9

@export var shake_strength: float = 8.0
@export var shake_time: float = 0.15

@export var world_min: Vector2 = Vector2(40.0, 40.0)
@export var world_max: Vector2 = Vector2(1880.0, 1040.0)

# --- SCREEN/PLAYFIELD CLAMP ---
@export var min_y: float = 120.0
@export var max_y: float = 800.0
@export var foot_offset: float = 0.0

# -------------------------
# CHIRP (movement loop feel)
# -------------------------
@export var chirp_min_db: float = -18.0
@export var chirp_max_db: float = -6.0
@export var chirp_max_distance: float = 900.0
@export var chirp_fade_speed: float = 8.0
@export var chirp_start_distance: float = 800.0

var frozen: bool = false

enum State { STALK, VANISHED, STRIKE }
var _state: int = State.STALK
var _timer: float = 0.0
var _wipe_timer: float = 0.0
var _strike_dir: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = get_node_or_null("sprite2D")
@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var collider: CollisionShape2D = $CollisionShape2D

# Optional audio
@onready var vanish_sfx = get_node_or_null("VanishSFX")
@onready var appear_sfx = get_node_or_null("AppearSFX")
@onready var strike_sfx = get_node_or_null("StrikeSFX")

# Standard naming
@onready var chirp_sfx = get_node_or_null("ChirpSFX")
@onready var steal_sfx = get_node_or_null("StealSFX")


func _ready() -> void:
	add_to_group("enemy")
	frozen = false
	_set_visible_state(true)
	_state = State.STALK
	_timer = cooldown_time
	_wipe_timer = 0.0
	_force_audio_off()

	if sprite:
		sprite.visible = false

	if anim:
		anim.play("walk")


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_clamp_y()
		_stop_chirp()
		_update_animation()
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		_clamp_y()
		_stop_chirp()
		_update_animation()
		return

	_timer = maxf(0.0, _timer - delta)
	_wipe_timer = maxf(0.0, _wipe_timer - delta)

	var dist_to_player := (player.global_position - global_position).length()
	_update_chirp(dist_to_player, delta)

	match _state:
		State.STALK:
			_update_stalk(player, delta)
		State.VANISHED:
			_update_vanished(player)
		State.STRIKE:
			_update_strike(delta)

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

	move_and_slide()
	_clamp_y()
	_update_animation()


func _update_animation() -> void:
	if anim == null:
		return

	if _state == State.VANISHED:
		anim.visible = false
		return

	anim.visible = true

	match _state:
		State.STRIKE:
			if anim.animation != "strike":
				anim.play("strike")
		State.STALK:
			if velocity.length() > 20.0:
				if anim.animation != "walk":
					anim.play("walk")
			else:
				if anim.animation != "idle":
					anim.play("idle")

	if velocity.x != 0.0:
		anim.flip_h = velocity.x < 0.0


func _clamp_y() -> void:
	var p := global_position
	p.y = clamp(p.y, min_y, (max_y - foot_offset))
	global_position = p


func _update_stalk(player: Node2D, delta: float) -> void:
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var dir := to_player / maxf(dist, 0.001)

	var desired := dir * stalk_speed
	velocity = velocity.lerp(desired, steering * delta)

	if _timer <= 0.0:
		_state = State.VANISHED
		_timer = vanish_time
		_set_visible_state(false)
		velocity = Vector2.ZERO
		_stop_chirp()

		if vanish_sfx and vanish_sfx.stream:
			vanish_sfx.play()


func _update_vanished(player: Node2D) -> void:
	velocity = Vector2.ZERO
	_stop_chirp()

	if _timer <= 0.0:
		_reappear_near_player(player)
		_set_visible_state(true)

		get_tree().call_group("camera", "shake", shake_strength, shake_time)

		if appear_sfx and appear_sfx.stream:
			appear_sfx.play()

		_state = State.STRIKE
		_timer = strike_time

		var to_player := player.global_position - global_position
		var dist := to_player.length()
		_strike_dir = to_player / maxf(dist, 0.001)

		_try_wipe_pickups_near_player(player)

		if strike_sfx and strike_sfx.stream:
			strike_sfx.play()


func _update_strike(delta: float) -> void:
	var desired := _strike_dir * strike_speed
	velocity = velocity.lerp(desired, (steering * 1.8) * delta)

	if _timer <= 0.0:
		_state = State.STALK
		_timer = cooldown_time


func _set_visible_state(v: bool) -> void:
	if sprite:
		sprite.visible = false
	if anim:
		anim.visible = v
	if collider:
		collider.disabled = not v


func _reappear_near_player(player: Node2D) -> void:
	for i in range(appear_tries):
		var ang := randf() * TAU
		var dist := randf_range(appear_min_distance, appear_distance)
		var offset := Vector2(cos(ang), sin(ang)) * dist
		var candidate := player.global_position + offset

		candidate.x = clampf(candidate.x, world_min.x, world_max.x)
		candidate.y = clampf(candidate.y, world_min.y, world_max.y)
		candidate.y = clampf(candidate.y, min_y, (max_y - foot_offset))

		global_position = candidate
		return

	var fallback := player.global_position + Vector2(appear_min_distance, 0.0)
	fallback.x = clampf(fallback.x, world_min.x, world_max.x)
	fallback.y = clampf(fallback.y, min_y, (max_y - foot_offset))
	global_position = fallback


func _try_wipe_pickups_near_player(player: Node2D) -> void:
	if _wipe_timer > 0.0:
		return

	var wiped := 0
	var pickups := get_tree().get_nodes_in_group("pickup")

	for p in pickups:
		if wiped >= wipe_max_per_strike:
			break
		if not is_instance_valid(p):
			continue
		if not (p is Node2D):
			continue

		var n := p as Node2D
		if n.global_position.distance_to(player.global_position) <= wipe_radius:
			if p.has_method("_collect_then_respawn"):
				p.call("_collect_then_respawn")
				wiped += 1
			elif p.has_method("reset_pickup"):
				p.call("reset_pickup")

	if wiped > 0:
		get_tree().call_group("camera", "shake", shake_strength, shake_time)

		if steal_sfx and steal_sfx.stream:
			steal_sfx.play()

	_wipe_timer = wipe_cooldown


func _update_chirp(dist_to_player: float, delta: float) -> void:
	if _state == State.VANISHED:
		_stop_chirp()
		return

	if chirp_sfx == null or chirp_sfx.stream == null:
		return

	if chirp_sfx.stream_paused:
		chirp_sfx.stream_paused = false

	if dist_to_player <= chirp_start_distance:
		if not chirp_sfx.playing:
			chirp_sfx.volume_db = chirp_min_db
			chirp_sfx.play()
	else:
		var smooth_out: float = minf(chirp_fade_speed * delta, 1.0)
		chirp_sfx.volume_db = lerpf(float(chirp_sfx.volume_db), chirp_min_db, smooth_out)
		if chirp_sfx.playing and chirp_sfx.volume_db <= (chirp_min_db + 0.5):
			chirp_sfx.stop()
		return

	var t: float = 1.0 - clampf(dist_to_player / maxf(chirp_max_distance, 0.001), 0.0, 1.0)
	var target_db: float = lerpf(chirp_min_db, chirp_max_db, t)

	var smooth: float = minf(chirp_fade_speed * delta, 1.0)
	chirp_sfx.volume_db = lerpf(float(chirp_sfx.volume_db), target_db, smooth)


func _stop_chirp() -> void:
	if chirp_sfx and chirp_sfx.playing:
		chirp_sfx.stop()


func _force_audio_off() -> void:
	for p in [chirp_sfx, steal_sfx, vanish_sfx, appear_sfx, strike_sfx]:
		if p == null:
			continue
		p.autoplay = false
		p.stream_paused = false
		if p.playing:
			p.stop()
