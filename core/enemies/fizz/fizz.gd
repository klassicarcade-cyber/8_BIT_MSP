extends BaseEnemy

# Fizz: orbits the player, bursts on contact, charges occasionally
# Steals TIME only on burst. Orbit tightens and speeds up over time.
# Randomly reverses orbit direction. Occasionally charges straight at player.

@export var orbit_radius: float = 130.0        # tighter than before (was 170)
@export var orbit_speed: float = 200.0         # faster base orbit (was 180)
@export var pull_strength: float = 220.0
@export var steering: float = 10.0
@export var max_speed: float = 380.0           # higher cap for charge

@export var burst_distance: float = 80.0       #was 95.0
@export var burst_knockback: float = 260.0
@export var burst_cooldown: float = 1.1
@export var burst_anim_time: float = 0.18

@export var jitter: float = 40.0

@export var shake_strength: float = 5.0
@export var shake_time: float = 0.10

# --- SCREEN/PLAYFIELD CLAMP ---
@export var min_y: float = 120.0
@export var max_y: float = 850.0
@export var foot_offset: float = 0.0

# -------------------------
# TIME DRAIN
# -------------------------
@export var time_drain_seconds: float = 5.0
@export var time_drain_enabled: bool = true

# -------------------------
# SPEED RAMP (gets faster over time)
# -------------------------
@export var speed_ramp_rate: float = 8.0       # orbit_speed units gained per second
@export var speed_ramp_max: float = 380.0      # orbit speed cap

# -------------------------
# ORBIT TIGHTEN (radius shrinks over time)
# -------------------------
@export var radius_shrink_rate: float = 2.0    # px per second
@export var radius_min: float = 80.0           # tightest orbit allowed

# -------------------------
# ORBIT DIRECTION REVERSAL
# -------------------------
@export var reverse_interval_min: float = 3.0  # seconds before possible reversal
@export var reverse_interval_max: float = 7.0  # seconds before possible reversal

# -------------------------
# CHARGE ATTACK
# -------------------------
@export var charge_interval_min: float = 5.0   # seconds between charges
@export var charge_interval_max: float = 12.0
@export var charge_speed: float = 500.0
@export var charge_duration: float = 0.4       # how long the dash lasts
@export var charge_cooldown: float = 2.0       # pause after charge before orbit resumes

# -------------------------
# CHIRP
# -------------------------
@export var chirp_min_db: float = -22.0
@export var chirp_max_db: float = -8.0
@export var chirp_max_distance: float = 1100.0
@export var chirp_fade_speed: float = 8.0
@export var chirp_start_distance: float = 1000.0

var frozen: bool = false

var _burst_timer: float = 0.0
var _phase: float = 0.0
var _burst_anim_timer: float = 0.0

# Orbit direction: 1.0 = counterclockwise, -1.0 = clockwise
var _orbit_dir: float = 1.0
var _reverse_timer: float = 0.0

# Charge state
enum ChargeState { ORBIT, CHARGING, COOLDOWN }
var _charge_state: ChargeState = ChargeState.ORBIT
var _charge_timer: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _next_charge_time: float = 0.0

# Runtime orbit values (ramp up over time)
var _current_orbit_radius: float = 0.0
var _current_orbit_speed: float = 0.0

# Speed burst after time steal
@export var steal_speed_boost: float = 120.0   # extra orbit speed after stealing time
@export var steal_speed_boost_duration: float = 3.0  # how long the boost lasts
var _steal_boost_timer: float = 0.0

# Screen flash on burst
@export var flash_color: Color = Color(0.8, 0.2, 1.0, 0.35)  # purple-ish
@export var flash_duration: float = 0.12
var _flash_timer: float = 0.0
var _flash_overlay: ColorRect = null

@onready var chirp_sfx = get_node_or_null("FizzChirpSFX")
@onready var steal_sfx = get_node_or_null("FizzStealSFX")
@onready var burst_sfx = get_node_or_null("BurstSFX")
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemy")
	_burst_timer = 0.0
	_phase = randf() * 10.0
	_burst_anim_timer = 0.0
	_current_orbit_radius = orbit_radius
	_current_orbit_speed = orbit_speed
	_orbit_dir = 1.0 if randf() > 0.5 else -1.0
	_reverse_timer = randf_range(reverse_interval_min, reverse_interval_max)
	_next_charge_time = randf_range(charge_interval_min, charge_interval_max)
	_steal_boost_timer = 0.0
	_flash_timer = 0.0
	_force_audio_off()
	if anim:
		anim.play("walk")
	# Create fullscreen flash overlay
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = flash_color
	_flash_overlay.visible = false
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	canvas.add_child(_flash_overlay)
	get_tree().root.add_child(canvas)


func _physics_process(delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		_clamp_y()
		_stop_all_audio()
		_update_animation(delta)
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		_clamp_y()
		_stop_all_audio()
		_update_animation(delta)
		return

	_burst_timer = maxf(0.0, _burst_timer - delta)
	_burst_anim_timer = maxf(0.0, _burst_anim_timer - delta)
	_steal_boost_timer = maxf(0.0, _steal_boost_timer - delta)
	_phase += delta

	# --- FLASH TIMER ---
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_overlay:
			_flash_overlay.visible = _flash_timer > 0.0

	# --- SPEED RAMP over time ---
	_current_orbit_speed = minf(_current_orbit_speed + speed_ramp_rate * delta, speed_ramp_max)

	# --- ORBIT TIGHTEN over time ---
	_current_orbit_radius = maxf(_current_orbit_radius - radius_shrink_rate * delta, radius_min)

	# --- ORBIT DIRECTION REVERSAL ---
	_reverse_timer -= delta
	if _reverse_timer <= 0.0:
		_orbit_dir *= -1.0
		_reverse_timer = randf_range(reverse_interval_min, reverse_interval_max)
		print("Fizz reversed orbit direction: ", _orbit_dir)

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var dir := to_player / maxf(dist, 0.001)

	_update_chirp(dist, delta)

	# --- CHARGE ATTACK ---
	_next_charge_time -= delta
	match _charge_state:
		ChargeState.ORBIT:
			if _next_charge_time <= 0.0:
				# Launch charge
				_charge_state = ChargeState.CHARGING
				_charge_dir = dir
				_charge_timer = charge_duration
				print("Fizz CHARGING!")
				if anim:
					anim.play("burst")
				if burst_sfx and burst_sfx.stream:
					burst_sfx.play()

		ChargeState.CHARGING:
			velocity = _charge_dir * charge_speed
			_charge_timer -= delta
			move_and_slide()
			_clamp_y()

			# Check if we hit the player during charge
			to_player = player.global_position - global_position
			dist = to_player.length()
			if dist <= burst_distance and _burst_timer <= 0.0:
				_try_burst(player)

			if _charge_timer <= 0.0:
				_charge_state = ChargeState.COOLDOWN
				_charge_timer = charge_cooldown
				_next_charge_time = randf_range(charge_interval_min, charge_interval_max)
				velocity = Vector2.ZERO

			_update_animation(delta)
			return

		ChargeState.COOLDOWN:
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_charge_state = ChargeState.ORBIT
			# Drift to a stop during cooldown
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			move_and_slide()
			_clamp_y()
			_update_animation(delta)
			return

	# --- NORMAL ORBIT ---
	var tangent := Vector2(-dir.y, dir.x) * _orbit_dir
	var radial_error := dist - _current_orbit_radius
	var radial := dir * clampf(radial_error, -1.0, 1.0) * pull_strength
	var wobble := Vector2(sin(_phase * 3.1), cos(_phase * 2.6)) * jitter
	# Apply speed boost if active
	var active_speed := _current_orbit_speed + (steal_speed_boost if _steal_boost_timer > 0.0 else 0.0)
	var desired := (tangent * active_speed) + radial + wobble
	velocity = velocity.lerp(desired, steering * delta)

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

	move_and_slide()
	_clamp_y()

	# Recompute after clamp
	to_player = player.global_position - global_position
	dist = to_player.length()

	if dist <= burst_distance:
		_try_burst(player)

	_update_animation(delta)


func _update_animation(_delta: float) -> void:
	if anim == null:
		return
	if _burst_anim_timer > 0.0 or _charge_state == ChargeState.CHARGING:
		if anim.animation != "burst":
			anim.play("burst")
	elif velocity.length() > 20.0:
		if anim.animation != "walk":
			anim.play("walk")
	else:
		if anim.animation != "idle":
			anim.play("idle")
	if velocity.x != 0.0:
		anim.flip_h = velocity.x > 0.0


func _clamp_y() -> void:
	var p := global_position
	p.y = clamp(p.y, min_y, max_y - foot_offset)
	global_position = p


func _try_burst(player: Node2D) -> void:
	if _burst_timer > 0.0:
		return
	var away := (global_position - player.global_position).normalized()
	velocity += away * burst_knockback
	get_tree().call_group("camera", "shake", shake_strength, shake_time)
	_burst_anim_timer = burst_anim_time
	if anim:
		anim.play("burst")
	if burst_sfx and burst_sfx.stream:
		burst_sfx.play()

	# TIME DRAIN + steal sound + speed boost + screen flash
	if time_drain_enabled and time_drain_seconds > 0.0:
		if player.has_method("on_time_stolen"):
			player.call("on_time_stolen", time_drain_seconds, "fizz")
		else:
			get_tree().call_group("timer", "subtract_time", time_drain_seconds)
		# Sound only on successful time steal
		if steal_sfx and steal_sfx.stream:
			steal_sfx.play()
		# Speed boost
		_steal_boost_timer = steal_speed_boost_duration
		# Screen flash
		_flash_timer = flash_duration
		if _flash_overlay:
			_flash_overlay.color = flash_color
			_flash_overlay.visible = true

	_burst_timer = burst_cooldown


func _update_chirp(dist_to_player: float, delta: float) -> void:
	if chirp_sfx == null or chirp_sfx.stream == null:
		return
	if chirp_sfx.stream_paused:
		chirp_sfx.stream_paused = false
	if dist_to_player <= chirp_start_distance:
		if not chirp_sfx.playing:
			chirp_sfx.volume_db = chirp_min_db
			chirp_sfx.play()
	else:
		var out_smooth: float = minf(chirp_fade_speed * delta, 1.0)
		chirp_sfx.volume_db = lerpf(float(chirp_sfx.volume_db), chirp_min_db, out_smooth)
		if chirp_sfx.playing and chirp_sfx.volume_db <= (chirp_min_db + 0.5):
			chirp_sfx.stop()
		return
	var t: float = 1.0 - clampf(dist_to_player / maxf(chirp_max_distance, 0.001), 0.0, 1.0)
	var target_db: float = lerpf(chirp_min_db, chirp_max_db, t)
	var smooth: float = minf(chirp_fade_speed * delta, 1.0)
	chirp_sfx.volume_db = lerpf(float(chirp_sfx.volume_db), target_db, smooth)


func _stop_all_audio() -> void:
	for p in [chirp_sfx, steal_sfx]:
		if p and p.playing:
			p.stop()


func _force_audio_off() -> void:
	for p in [chirp_sfx, steal_sfx]:
		if p == null:
			continue
		p.autoplay = false
		p.stream_paused = false
		if p.playing:
			p.stop()


func _delta_unused(value: float) -> float:
	return value
