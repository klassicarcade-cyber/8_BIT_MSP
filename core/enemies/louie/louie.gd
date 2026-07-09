extends CharacterBody2D

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var steal_sfx = get_node_or_null("StealSFX")

@export var speed: float = 100.0
@export var aggro_range: float = 420.0
@export var stop_distance: float = 12.0

@export var steal_range: float = 42.0
@export var steal_cents: int = 15
@export var steal_cooldown: float = 1.5

var player: Node2D = null
var current_anim: String = ""
var aggro_locked: bool = false
var can_steal: bool = true

func _ready() -> void:
	print("DEV LOUIE LOADED")
	call_deferred("_find_player")
	play_anim("idle")

func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	print("Louie player found: ", player)

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	if player == null:
		velocity = Vector2.ZERO
		play_anim("idle")
		move_and_slide()
		return

	# BOTTLE HUNT MODE: chase nearest bottle instead of player
	_bottle_hunt(delta)


func _bottle_hunt(delta: float) -> void:
	var nearest: Node2D = null
	var nearest_dist: float = INF

	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not node.visible:
			continue
		var node_script = node.get_script()
		if node_script == null:
			continue
		if not ("bottle" in node_script.resource_path.to_lower()):
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node

	if nearest == null:
		# No bottles visible - chase player as fallback
		var to_player: Vector2 = player.global_position - global_position
		var dist: float = to_player.length()
		if dist > stop_distance:
			velocity = to_player.normalized() * speed
			play_anim("walk")
		else:
			velocity = Vector2.ZERO
			play_anim("idle")
		move_and_slide()
		update_facing()
		return

	# Chase the bottle
	var to_bottle: Vector2 = nearest.global_position - global_position

	if nearest_dist <= steal_range and can_steal:
		# Grab it - knock bottle away and deduct score
		velocity = Vector2.ZERO
		play_anim("attack")
		if nearest.has_method("reset_pickup"):
			nearest.call("reset_pickup")
		# Deduct $0.10 from score
		var s := get_node_or_null("/root/score")
		if s:
			if s.has_method("steal"):
				s.steal(steal_cents)
			elif s.has_method("add_pickup"):
				s.add_pickup(-steal_cents)
		# Play steal sound
		if steal_sfx and steal_sfx.stream:
			steal_sfx.play()
		can_steal = false
		get_tree().create_timer(steal_cooldown).timeout.connect(func(): can_steal = true)
	elif nearest_dist <= steal_range:
		velocity = Vector2.ZERO
		play_anim("idle")
	else:
		velocity = to_bottle.normalized() * speed
		play_anim("walk")

	move_and_slide()
	update_facing()

func try_steal() -> void:
	can_steal = false

	print("LOUIE STOLE ", steal_cents, " cents!")

	if player and player.has_method("on_stolen_from"):
		player.on_stolen_from(steal_cents, "louie")
	else:
		var s := get_node_or_null("/root/score")
		if s:
			if s.has_method("steal"):
				s.steal(steal_cents)
			elif s.has_method("add_pickup"):
				s.add_pickup(-steal_cents)

	if anim.sprite_frames and anim.sprite_frames.has_animation("attack"):
		play_anim("attack")
		await get_tree().create_timer(0.20).timeout

	await get_tree().create_timer(steal_cooldown).timeout
	can_steal = true

func play_anim(anim_name: String) -> void:
	if current_anim == anim_name:
		return
	current_anim = anim_name
	anim.play(anim_name)

func update_facing() -> void:
	if velocity.x != 0:
		anim.flip_h = velocity.x > 0
