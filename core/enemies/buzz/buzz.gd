extends BaseEnemy

@export var move_speed: float = 150.0
@export var steal_distance: float = 180.0
@export var steal_cooldown: float = 1.5
@export var steal_cents: int = 25

var can_steal: bool = true
var current_anim: String = ""

@onready var anim = get_node_or_null("AnimatedSprite2D")
@onready var sprite = get_node_or_null("Sprite2D")
@onready var steal_sfx = get_node_or_null("StealSFX")
@onready var chirp_sfx = get_node_or_null("BuzzChirp")
@onready var hum_sfx = get_node_or_null("BuzzHum")
@onready var tick_sfx = get_node_or_null("BuzzTick")
@onready var bed_sfx = get_node_or_null("BuzzBed")
@onready var dash_sfx = get_node_or_null("DashSFX")
@onready var hit_sfx = get_node_or_null("HitSFX")
@onready var shout_player = get_node_or_null("ShoutPlayer")

var frozen: bool = false


func _ready() -> void:
	add_to_group("enemy")

	# If animated sprite exists, prefer it.
	if anim:
		anim.visible = true
		play_anim("idle")
	elif sprite:
		sprite.visible = true


func _find_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(_delta: float) -> void:
	if frozen or get_tree().paused:
		velocity = Vector2.ZERO
		move_and_slide()
		play_anim("idle")
		return

	var player := _find_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		play_anim("idle")
		return

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()

	# Stop just in front of the player - never go behind them.
	# stop_distance: enemy idles here and steals.
	# too_close_distance: enemy backs off so it never overlaps/passes through.
	const STOP_DISTANCE: float = 120.0
	const TOO_CLOSE_DISTANCE: float = 180.0

	if dist <= TOO_CLOSE_DISTANCE:
		# Too close - push back along the same axis we approached on
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 2.0 * get_physics_process_delta_time())
	elif dist <= STOP_DISTANCE:
		# In the sweet spot - stop and wait to steal
		velocity = Vector2.ZERO
	elif dist > 0.001:
		velocity = to_player.normalized() * move_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	update_facing()

	if velocity.length() > 5.0:
		play_anim("walk")
	else:
		play_anim("idle")

	if can_steal and dist <= steal_distance:
		try_steal(player)


func try_steal(player: Node2D) -> void:
	if not can_steal:
		return

	can_steal = false

	# Try player hook first
	if player.has_method("add_score"):
		player.call("add_score", -steal_cents)
	elif has_node("/root/score"):
		var s = get_node("/root/score")
		if s and s.has_method("add_pickup"):
			s.add_pickup(-steal_cents)

	# Play steal sound
	if steal_sfx and steal_sfx.stream:
		steal_sfx.play()

	# Brief attack flash if attack animation exists
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("attack"):
		play_anim("attack")
		await get_tree().create_timer(0.20).timeout

	await get_tree().create_timer(steal_cooldown).timeout
	can_steal = true


func play_anim(anim_name: String) -> void:
	if current_anim == anim_name:
		return

	current_anim = anim_name

	if anim:
		anim.play(anim_name)


func update_facing() -> void:
	if anim and velocity.x != 0.0:
		anim.flip_h = velocity.x < 0.0
