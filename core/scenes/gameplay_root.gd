# res://gameplay_root.gd
extends Node2D

const WORLD_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const WORLD_CENTER: Vector2 = WORLD_SIZE * 0.5

# -------------------------
# ENEMIES (fallback)
# -------------------------
const BUZZ_SCENE: PackedScene = preload("res://core/enemies/buzz/buzz.tscn")
const LOUIE_SCENE: PackedScene = preload("res://core/enemies/louie/louie.tscn")
const LADY_SCENE: PackedScene = preload("res://core/enemies/lady/lady.tscn")
const FIZZ_SCENE: PackedScene = preload("res://core/enemies/fizz/fizz.tscn")
const FANG_SCENE: PackedScene = preload("res://core/enemies/fang/fang.tscn")

# -------------------------
# BUBBA — $28 guest helper (Gobles/Fang room only)
# -------------------------
const BUBBA_SCENE: PackedScene = preload("res://core/enemies/fang/bubba.tscn")
var _bubba_spawned: bool = false

# ── FISH JUMP — Paw Paw background2 lake decoration ──
const FISH_JUMP_SCENE: PackedScene = preload("res://series/paw/fish_jump.tscn")
var _fish_spawned: bool = false

# ── PAW BASEBALL PLAYER — appears at $28.20 in Paw Paw game ──
const PAW_BASEBALL_SCENE: PackedScene = preload("res://series/paw/paw_baseball_player.tscn")
var _paw_baseball_spawned: bool = false

# ── BEER CRATE — random time + position, Paw Paw game only ──
const BEER_CRATE_SCENE: PackedScene = preload("res://series/paw/beer_crate/BeerCrate.tscn")
var _beer_crate_spawned: bool = false
var _beer_crate_timer: float = 0.0
var _beer_crate_delay: float = -1.0

# ── MARS SPACESHIP HELPER — appears at $27.10 in Mars game ──
const MARS_SPACESHIP_SCENE: PackedScene = preload("res://series/mars/spaceship_helper/mars_spaceship.tscn")
var _mars_ship_spawned: bool = false

# ── FIZZ PTERODACTYL — dive bomber appears at $28.10 in Fizz game ──
const FIZZ_PTERODACTYL_SCENE: PackedScene = preload("res://series/fizz/fizz_pterodactyl.tscn")
var _fizz_ptero_spawned: bool = false

# ── MARS ROBOT CAMEO — appears 20s after round starts in Mars game ──
const MARS_ROBOT_SCENE: PackedScene = preload("res://series/mars/robot_cameo/RobotCameo.tscn")
var _mars_robot_spawned: bool = false
var _mars_robot_timer: float = 0.0

# ── STAR TWINKLE — Mars cockpit windows (background1, room index 0) ──
const STAR_TWINKLE_SCENE: PackedScene = preload("res://series/mars/star_twinkle.tscn")
var _star_twinkle_node: Node2D = null

# ── ARCADE SIGN — Gobles Klassic Arcade (bg_gob_ka, room index 1) ──
const ARCADE_SIGN_SCENE: PackedScene = preload("res://series/gob/arcade_sign.tscn")
var _arcade_sign_node: Node2D = null

# -------------------------
# TIMER
# -------------------------
const START_TIME_SECONDS: float = 120.0

const TIME_BONUS_STEPS := [
	{ "cents": 500,  "seconds": 60 },
	{ "cents": 1000, "seconds": 60 },
	{ "cents": 1500, "seconds": 60 },
	{ "cents": 2000, "seconds": 60 },
	{ "cents": 2500, "seconds": 30 },
	{ "cents": 3000, "seconds": 10 },
	{ "cents": 3500, "seconds": 10 },
	{ "cents": 4000, "seconds": 5 }
]

var time_left: float = START_TIME_SECONDS
var game_over: bool = false
var time_bonus_index: int = 0

# -------------------------
# START / ATTRACT MODE
# -------------------------
var waiting_for_start: bool = true
var game_over_triggered: bool = false
var _world_frozen: bool = true

# -------------------------
# ATTRACT IDLE TIMEOUT — press-start screen returns to game select
# -------------------------
# If a game is selected but nobody presses Start within this many
# seconds, the cabinet returns to the game select screen, which runs
# its own idle/screensaver cycle like normal.
const ATTRACT_IDLE_SECONDS: float = 45.0
var _attract_idle_time: float = 0.0
var _attract_idle_fired: bool = false

# -------------------------
# HIGH SCORE RESET (hidden cabinet button)
# -------------------------
var _reset_hold_time: float = 0.0
var _reset_holding: bool = false
const RESET_HOLD_SECONDS := 1.0

# -------------------------
# GAME / ROOMS
# -------------------------
@export var default_game_def: GameDef

@export var room_backgrounds: Array[Texture2D] = []
@export var start_room_index: int = 0

var room_index: int = -1
var player_instance: Node2D = null
var max_room_reached: int = 0

var _game_def: GameDef = null
var _room_backgrounds: Array[Texture2D] = []
var _room_enemy_scenes: Array[PackedScene] = []

# -------------------------
# MULTICART: return to game select after game over
# -------------------------
@export var return_to_game_select_on_game_over: bool = true
@export var game_select_scene_path: String = "res://core/game_select.tscn"

# -------------------------
# NODES
# -------------------------
@onready var player_spawn: Marker2D = get_node_or_null("PlayerSpawn") as Marker2D
@onready var background: Sprite2D = get_node_or_null("Background") as Sprite2D
@onready var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
@onready var score_label: Label = get_node_or_null("UI_Text/ScoreLabel") as Label
@onready var timer_label: Label = get_node_or_null("UI_Text/TimerLabel") as Label
@onready var ui_text: CanvasItem = get_node_or_null("UI_Text") as CanvasItem
@onready var enemy_container: Node2D = get_node_or_null("EnemyContainer") as Node2D
@onready var game_over_ui: Control = get_node_or_null("UI_Overlay/GameOverUI") as Control

@onready var press_start_ui: CanvasItem = (
	get_node_or_null("UI_Dim") as CanvasItem
	if get_node_or_null("UI_Dim") != null
	else (find_child("PressStart", true, false) as CanvasItem)
)

@onready var start_sfx: AudioStreamPlayer = get_node_or_null("StartSFX") as AudioStreamPlayer

@onready var music_player: AudioStreamPlayer = get_node_or_null("MusicPlayer") as AudioStreamPlayer
@onready var music_legacy: AudioStreamPlayer = get_node_or_null("Music") as AudioStreamPlayer


func _get_music_player() -> AudioStreamPlayer:
	if music_player:
		return music_player
	return music_legacy


func _configure_music_nodes() -> void:
	var target_bus := "Music"
	if AudioServer.get_bus_index(target_bus) == -1:
		target_bus = "Master"

	var master_i := AudioServer.get_bus_index("Master")
	if master_i != -1:
		AudioServer.set_bus_mute(master_i, false)
		AudioServer.set_bus_volume_db(master_i, 0.0)
	var t_i := AudioServer.get_bus_index(target_bus)
	if t_i != -1:
		AudioServer.set_bus_mute(t_i, false)
		AudioServer.set_bus_volume_db(t_i, 0.0)

	for n in [music_player, music_legacy]:
		if n == null:
			continue
		n.process_mode = Node.PROCESS_MODE_ALWAYS
		n.bus = target_bus
		n.autoplay = false
		n.stream_paused = false


func _music_debug_dump(tag: String) -> void:
	var mp := _get_music_player()
	if mp == null:
		print("MUSIC DEBUG [", tag, "] -> no music player node found")
		return
	print("MUSIC DEBUG [", tag, "] -> def=", (_game_def.title if _game_def else "null"),
		" stream=", (mp.stream.resource_path if mp.stream else "null"),
		" bus=", mp.bus,
		" vol=", mp.volume_db,
		" playing=", mp.playing,
		" tree_paused=", get_tree().paused,
		" node_mode=", mp.process_mode)


func _start_music_now() -> void:
	_configure_music_nodes()
	var mp := _get_music_player()
	if mp == null:
		return
	mp.stream_paused = false
	mp.volume_db = 0.0
	if mp.stream:
		mp.play()
	_music_debug_dump("after_play")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_music_nodes()

	add_to_group("timer")

	var menu_path := _resolve_game_select_path()
	print("GAME SELECT PATH CHECK -> exported=", game_select_scene_path,
		" | resolved=", menu_path,
		" | exists=", (menu_path != "" and ResourceLoader.exists(menu_path)))

	_ensure_game_selected()
	if not CurrentGame.has_game():
		push_error("GameplayRoot: No game selected and no default_game_def assigned.")
		return

	_setup_score_ui()
	reload_current_game()
	_enter_attract_mode()
	_force_viewport_settle()



func set_game_and_reload(game_def: GameDef) -> void:
	if game_def == null:
		return

	if CurrentGame.has_method("set_game"):
		CurrentGame.set_game(game_def)
	else:
		CurrentGame.def = game_def

	reload_current_game()
	_enter_attract_mode()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_highscores"):
		_reset_holding = true
		_reset_hold_time = 0.0
		return

	if event.is_action_released("reset_highscores"):
		_reset_holding = false
		_reset_hold_time = 0.0
		return

	if game_over and game_over_ui and game_over_ui.visible:
		return

	if waiting_for_start:
		# Any input on the press-start screen resets the idle clock.
		_attract_idle_time = 0.0

		if event.is_action_pressed("ui_accept"):
			_start_round()


func _process(delta: float) -> void:
	if _reset_holding:
		_reset_hold_time += delta
		if _reset_hold_time >= RESET_HOLD_SECONDS:
			_reset_holding = false
			_reset_hold_time = 0.0
			_reset_highscores_now()

	if waiting_for_start and not game_over:
		_tick_attract_idle(delta)

	if waiting_for_start or game_over:
		return

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_update_timer_ui()
		_on_time_up()
		return

	_tick_mars_robot_timer(delta)
	_tick_beer_crate_timer(delta)
	_update_timer_ui()


# ==================================================
# ATTRACT IDLE TIMEOUT
# ==================================================
func _tick_attract_idle(delta: float) -> void:
	if _attract_idle_fired:
		return

	_attract_idle_time += delta
	if _attract_idle_time >= ATTRACT_IDLE_SECONDS:
		_attract_idle_fired = true
		var path := _resolve_game_select_path()
		if path != "" and ResourceLoader.exists(path):
			print("💤 Press-start idle for ", ATTRACT_IDLE_SECONDS, "s — back to game select")
			call_deferred("_go_to_game_select", path)
		else:
			push_error("GameplayRoot: idle timeout — could not resolve game select path.")
			_attract_idle_time = 0.0
			_attract_idle_fired = false


func _reset_highscores_now() -> void:
	var hs: Node = get_tree().get_first_node_in_group("hiscore")

	if hs == null:
		hs = get_node_or_null("UI_Overlay/GameOverUI/HiScore")
	if hs == null:
		hs = get_node_or_null("UI_Overlay/HiScore")
	if hs == null:
		hs = get_node_or_null("HiScore")

	if hs and hs.has_method("reset_highscores_low_test_values"):
		hs.call("reset_highscores_low_test_values")
		print("✅ High scores reset (button 2 hold)")
	elif hs and hs.has_method("reset_highscores"):
		hs.call("reset_highscores")
		print("✅ High scores reset (button 2 hold)")
	else:
		print("⚠️ High score reset: could not find hiscore node or reset method.")


func subtract_time(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if waiting_for_start or game_over:
		return
	if _world_frozen or get_tree().paused:
		return

	time_left = maxf(0.0, time_left - seconds)
	_update_timer_ui()

	if time_left <= 0.0:
		_on_time_up()


func _reset_all_pickups() -> void:
	get_tree().call_group("pickup", "reset_pickup")


func _set_pickups_locked(locked: bool) -> void:
	for p in get_tree().get_nodes_in_group("pickup"):
		if p == null:
			continue
		if p.has_method("set_locked"):
			p.call("set_locked", locked)
		elif "locked" in p:
			p.locked = locked


func _enter_attract_mode() -> void:
	_configure_music_nodes()
	waiting_for_start = true
	game_over = false
	game_over_triggered = false
	_world_frozen = true

	_attract_idle_time = 0.0
	_attract_idle_fired = false

	var mp := _get_music_player()
	if mp and mp.playing:
		mp.stop()

	start_room_index = 0
	max_room_reached = 0
	room_index = -1

	_bubba_spawned = false
	_fish_spawned = false
	_mars_ship_spawned = false
	_fizz_ptero_spawned = false
	_paw_baseball_spawned = false
	_mars_robot_spawned = false
	_mars_robot_timer = 0.0
	_beer_crate_spawned = false
	_beer_crate_timer = 0.0
	_beer_crate_delay = -1.0

	if ui_text:
		ui_text.visible = true
	if press_start_ui:
		press_start_ui.visible = true

	score.reset()
	_reset_timer_display_only()

	if not _get_room_backgrounds().is_empty():
		_apply_room(0, true)

	_clear_enemies()
	_reset_all_pickups()
	_set_pickups_locked(true)

	_set_world_paused(true)
	_set_frozen_all(true)
	_set_processing_all(false)

	_reset_player_position()
	_apply_player_visual()
	_setup_camera()
	_force_viewport_settle()


func _start_round() -> void:
	waiting_for_start = false
	game_over = false
	game_over_triggered = false
	_world_frozen = false

	_bubba_spawned = false
	_fish_spawned = false
	_mars_ship_spawned = false
	_fizz_ptero_spawned = false
	_paw_baseball_spawned = false
	_mars_robot_spawned = false
	_mars_robot_timer = 0.0
	_beer_crate_spawned = false
	_beer_crate_timer = 0.0
	_beer_crate_delay = randf_range(20.0, 80.0)

	var _gd := _get_current_game_def()
	if _gd and has_node("/root/MarqueeWindow"):
		get_node("/root/MarqueeWindow").show_game_marquee(str(_gd.game_id))

	if press_start_ui:
		press_start_ui.visible = false

	start_room_index = 0
	max_room_reached = 0
	room_index = -1

	if not _get_room_backgrounds().is_empty():
		_apply_room(0, true)

	score.reset()
	_reset_timer_full()
	_reset_all_pickups()
	_set_pickups_locked(false)

	_set_processing_all(true)
	_set_world_paused(false)
	_set_frozen_all(false)

	_reset_player_position()
	_apply_player_visual()
	_setup_camera()
	_force_viewport_settle()

	_configure_music_nodes()
	var mp := _get_music_player()
	if mp:
		if _game_def and ("music_stream" in _game_def) and _game_def.music_stream:
			mp.stream = _game_def.music_stream
		else:
			mp.stream = null
		_music_debug_dump("before_play")
		call_deferred("_start_music_now")

	_respawn_room_enemy()
	_trigger_enemy_intro_if_allowed()



func _reset_player_position() -> void:
	if player_instance and player_spawn:
		player_instance.global_position = player_spawn.global_position
		if player_instance is CharacterBody2D:
			(player_instance as CharacterBody2D).velocity = Vector2.ZERO


func _set_world_paused(paused: bool) -> void:
	get_tree().paused = paused

	if game_over_ui:
		game_over_ui.process_mode = Node.PROCESS_MODE_ALWAYS

	process_mode = Node.PROCESS_MODE_ALWAYS


# ==================================================
# FREEZE + PROCESS HELPERS
# ==================================================
func _set_frozen_all(f: bool) -> void:
	_set_node_frozen(player_instance, f)
	if enemy_container:
		for child in enemy_container.get_children():
			if child.is_in_group("bubba"):
				continue
			_set_node_frozen(child, f)


func _set_node_frozen(n: Node, f: bool) -> void:
	if n == null:
		return
	if n.has_method("set_frozen"):
		n.call("set_frozen", f)
	elif "frozen" in n:
		n.frozen = f


func _set_processing_all(enabled: bool) -> void:
	_set_node_processing(player_instance, enabled)
	if enemy_container:
		for child in enemy_container.get_children():
			if child.is_in_group("bubba"):
				continue
			_set_node_processing(child, enabled)


func _set_node_processing(n: Node, enabled: bool) -> void:
	if n == null:
		return
	n.set_physics_process(enabled)
	n.set_process(enabled)


func _clear_room_carryover_effects() -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p.has_method("clear_slow"):
		p.call("clear_slow")


func _reset_timer_display_only() -> void:
	time_left = START_TIME_SECONDS
	time_bonus_index = 0
	_update_timer_ui()


func _reset_timer_full() -> void:
	time_left = START_TIME_SECONDS
	game_over = false
	game_over_triggered = false
	time_bonus_index = 0
	_update_timer_ui()


func _grant_time_bonus_if_needed(cents: int) -> void:
	while time_bonus_index < TIME_BONUS_STEPS.size():
		var step = TIME_BONUS_STEPS[time_bonus_index]
		if cents < int(step["cents"]):
			break
		time_left += float(step["seconds"])
		time_bonus_index += 1


func _update_timer_ui() -> void:
	if not timer_label:
		return
	var t: int = int(ceil(time_left))
	var minutes: int = int(t / 60)
	var seconds: int = int(t % 60)
	timer_label.text = "%d:%02d" % [minutes, seconds]


func _on_time_up() -> void:
	game_over = true
	_trigger_game_over()


func _trigger_game_over() -> void:
	if game_over_triggered:
		return
	game_over_triggered = true
	_world_frozen = true

	var mp := _get_music_player()
	if mp and mp.playing:
		mp.stop()

	if ui_text:
		ui_text.visible = false

	_set_frozen_all(true)
	_set_world_paused(true)
	_set_processing_all(false)
	_clear_enemies()
	_set_pickups_locked(true)

	if game_over_ui and game_over_ui.has_method("open_game_over"):
		game_over_ui.open_game_over(score.cents)
		game_over_ui.call_deferred("grab_focus")

		if game_over_ui.has_signal("finished") and not game_over_ui.finished.is_connected(_on_game_over_finished):
			game_over_ui.finished.connect(_on_game_over_finished, CONNECT_ONE_SHOT)
	else:
		_on_game_over_finished()


func _on_game_over_finished() -> void:
	if game_over_ui:
		game_over_ui.visible = false

	if return_to_game_select_on_game_over:
		var path := _resolve_game_select_path()
		print("GAME OVER FINISHED -> return_to_menu=", return_to_game_select_on_game_over,
			" | exported=", game_select_scene_path,
			" | resolved=", path,
			" | exists=", (path != "" and ResourceLoader.exists(path)))

		if path != "" and ResourceLoader.exists(path):
			get_tree().paused = false
			call_deferred("_go_to_game_select", path)
			return
		else:
			push_error("GameplayRoot: Could not resolve game select scene path.")

	_enter_attract_mode()


func _go_to_game_select(path: String) -> void:
	get_tree().paused = false
	if has_node("/root/MarqueeWindow"):
		get_node("/root/MarqueeWindow").show_idle_cycle()
	get_tree().change_scene_to_file(path)


func _resolve_game_select_path() -> String:
	if game_select_scene_path != "" and ResourceLoader.exists(game_select_scene_path):
		return game_select_scene_path

	var candidates := [
		"res://core/game_select.tscn",
		"res://game_select.tscn",
		"res://scenes/game_select.tscn",
		"res://core/scenes/game_select.tscn",
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			return p

	return ""


func _setup_score_ui() -> void:
	if not score.changed.is_connected(_on_score_changed):
		score.changed.connect(_on_score_changed)
	if not score.changed.is_connected(_on_score_progression):
		score.changed.connect(_on_score_progression)
	if not score.changed.is_connected(_on_bubba_check):
		score.changed.connect(_on_bubba_check)
	if not score.changed.is_connected(_on_fish_check):
		score.changed.connect(_on_fish_check)
	if not score.changed.is_connected(_on_mars_ship_check):
		score.changed.connect(_on_mars_ship_check)
	if not score.changed.is_connected(_on_fizz_pterodactyl_check):
		score.changed.connect(_on_fizz_pterodactyl_check)
	if not score.changed.is_connected(_on_paw_baseball_check):
		score.changed.connect(_on_paw_baseball_check)

	_on_score_changed(score.cents)
	_on_score_progression(score.cents)


func _on_score_changed(cents: int) -> void:
	if score_label:
		score_label.text = score.dollars_string()

	if not waiting_for_start and not game_over:
		_grant_time_bonus_if_needed(cents)


func _on_score_progression(cents: int) -> void:
	var bgs: Array[Texture2D] = _get_room_backgrounds()
	if bgs.is_empty():
		return

	var target_room: int = int(floor(float(cents) / 500.0))
	target_room = clampi(target_room, 0, bgs.size() - 1)

	if target_room <= max_room_reached:
		return

	max_room_reached = target_room
	start_room_index = target_room

	_apply_room(target_room, false)

	if not waiting_for_start and not game_over:
		_respawn_room_enemy()
		_trigger_enemy_intro_if_allowed()


func _on_bubba_check(cents: int) -> void:
	if _bubba_spawned:
		return
	if waiting_for_start or game_over:
		return
	if cents < 2800:
		return

	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"Gobles":
		return
	if room_index != 4:
		return

	_bubba_spawned = true
	_spawn_bubba()


func _spawn_bubba() -> void:
	if not BUBBA_SCENE:
		push_error("GameplayRoot: BUBBA_SCENE not found — check res://core/enemies/fang/bubba.tscn")
		return

	var bubba := BUBBA_SCENE.instantiate() as Node2D
	if bubba == null:
		return

	if enemy_container:
		enemy_container.add_child(bubba)
	else:
		add_child(bubba)

	print("🍺 Bubba has entered the building at $28!")


func _on_fish_check(cents: int) -> void:
	if _fish_spawned:
		return
	if waiting_for_start or game_over:
		return

	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"Paw Paw":
		return
	if room_index != 1:
		return

	_fish_spawned = true
	_spawn_fish()


func _spawn_fish() -> void:
	if not FISH_JUMP_SCENE:
		push_error("GameplayRoot: FISH_JUMP_SCENE not found — check res://series/paw/fish_jump.tscn")
		return
	var fish := FISH_JUMP_SCENE.instantiate() as Node2D
	if fish == null:
		return
	fish.name = "FishJumpInstance"
	add_child(fish)
	print("🐟 Fish jump spawned for Paw Paw lake!")


func _despawn_fish() -> void:
	var existing := get_node_or_null("FishJumpInstance")
	if existing:
		existing.queue_free()
	_fish_spawned = false


func _on_mars_ship_check(cents: int) -> void:
	if _mars_ship_spawned:
		return
	if waiting_for_start or game_over:
		return

	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"mars":
		return
	if cents < 2710:
		return

	_mars_ship_spawned = true
	_spawn_mars_ship()


func _spawn_mars_ship() -> void:
	if not MARS_SPACESHIP_SCENE:
		push_error("GameplayRoot: MARS_SPACESHIP_SCENE not found — check res://series/mars/spaceship_helper/mars_spaceship.tscn")
		return

	var ship := MARS_SPACESHIP_SCENE.instantiate() as Node2D
	if ship == null:
		return

	ship.name = "MarsSpaceshipHelper"
	add_child(ship)
	print("🚀 Mars Spaceship Helper launched at $27.10!")


func _on_fizz_pterodactyl_check(cents: int) -> void:
	if _fizz_ptero_spawned:
		return
	if waiting_for_start or game_over:
		return

	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"Fizz":
		return
	if cents < 2810:
		return

	_fizz_ptero_spawned = true
	_spawn_fizz_pterodactyl()


func _spawn_fizz_pterodactyl() -> void:
	if not FIZZ_PTERODACTYL_SCENE:
		push_error("GameplayRoot: FIZZ_PTERODACTYL_SCENE not found — check res://series/fizz/fizz_pterodactyl.tscn")
		return

	var ptero := FIZZ_PTERODACTYL_SCENE.instantiate() as Node2D
	if ptero == null:
		return

	ptero.name = "FizzPterodactylHelper"
	add_child(ptero)
	print("🦕 Fizz Pterodactyl dive bomber launched at $28.10!")


# ==================================================
# MARS ROBOT CAMEO — time-based trigger (20 seconds)
# ==================================================
func _tick_mars_robot_timer(delta: float) -> void:
	if _mars_robot_spawned:
		return
	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"mars":
		return
	_mars_robot_timer += delta
	if _mars_robot_timer >= 20.0:
		_mars_robot_spawned = true
		_spawn_mars_robot()


func _spawn_mars_robot() -> void:
	if not MARS_ROBOT_SCENE:
		push_error("GameplayRoot: MARS_ROBOT_SCENE not found — check res://series/mars/robot_cameo/RobotCameo.tscn")
		return

	var robot := MARS_ROBOT_SCENE.instantiate() as Node2D
	if robot == null:
		return

	robot.name = "MarsRobotCameo"
	add_child(robot)
	if robot.has_method("start_cameo"):
		robot.start_cameo()
	print("🤖 Mars Robot Cameo triggered at 20 seconds!")


# ==================================================
# BEER CRATE — random time + position, Paw Paw only
# ==================================================
func _tick_beer_crate_timer(delta: float) -> void:
	if _beer_crate_spawned:
		return
	if _beer_crate_delay < 0.0:   # not initialized yet — attract mode guard
		return
	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"Paw Paw":
		return
	_beer_crate_timer += delta
	if _beer_crate_timer >= _beer_crate_delay:
		_beer_crate_spawned = true
		_spawn_beer_crate()


func _spawn_beer_crate() -> void:
	if not BEER_CRATE_SCENE:
		push_error("GameplayRoot: BEER_CRATE_SCENE not found — check res://series/paw/beer_crate/BeerCrate.tscn")
		return

	var crate := BEER_CRATE_SCENE.instantiate() as Node2D
	if crate == null:
		return

	crate.name = "BeerCratePickup"
	add_child(crate)
	print("🍺 Beer Crate spawned at %.1fs (delay was %.1fs)!" % [_beer_crate_timer, _beer_crate_delay])


func _update_star_twinkle() -> void:
	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"mars":
		_despawn_stars()
		return
	if room_index == 0:
		_spawn_stars()
	else:
		_despawn_stars()


func _spawn_stars() -> void:
	if is_instance_valid(_star_twinkle_node):
		return
	if not STAR_TWINKLE_SCENE:
		push_error("GameplayRoot: STAR_TWINKLE_SCENE not found — check res://series/mars/star_twinkle.tscn")
		return
	var node := STAR_TWINKLE_SCENE.instantiate() as Node2D
	if node == null:
		return
	_star_twinkle_node = node
	add_child(_star_twinkle_node)
	print("✨ Star twinkle spawned for Mars cockpit!")


func _despawn_stars() -> void:
	if is_instance_valid(_star_twinkle_node):
		_star_twinkle_node.queue_free()
	_star_twinkle_node = null


func _update_arcade_sign() -> void:
	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"Gobles":
		_despawn_arcade_sign()
		return
	if room_index == 1:
		_spawn_arcade_sign()
	else:
		_despawn_arcade_sign()


func _spawn_arcade_sign() -> void:
	if is_instance_valid(_arcade_sign_node):
		return
	if not ARCADE_SIGN_SCENE:
		push_error("GameplayRoot: ARCADE_SIGN_SCENE not found — check res://series/gob/arcade_sign.tscn")
		return
	var node := ARCADE_SIGN_SCENE.instantiate() as Node2D
	if node == null:
		return
	_arcade_sign_node = node
	add_child(_arcade_sign_node)
	print("🕹️ Arcade sign spawned for Gobles KA!")


func _despawn_arcade_sign() -> void:
	if is_instance_valid(_arcade_sign_node):
		_arcade_sign_node.queue_free()
	_arcade_sign_node = null


func _apply_room(idx: int, force: bool) -> void:
	var bgs: Array[Texture2D] = _get_room_backgrounds()
	if bgs.is_empty():
		return

	idx = clampi(idx, 0, bgs.size() - 1)

	if not force and idx == room_index:
		return

	if idx != room_index:
		_clear_room_carryover_effects()
		if idx != 1:
			_despawn_fish()
		if idx == 1:
			_fish_spawned = false

	room_index = idx
	_set_background(bgs[room_index])
	_update_star_twinkle()
	_update_arcade_sign()


func _respawn_room_enemy() -> void:
	_clear_enemies()
	await get_tree().process_frame
	if waiting_for_start or game_over:
		return

	if _room_enemy_scenes.size() > 0:
		var idx: int = clampi(room_index, 0, _room_enemy_scenes.size() - 1)
		var scene: PackedScene = _room_enemy_scenes[idx]
		if scene:
			_spawn_enemy(scene)
		return

	match room_index:
		0: _spawn_enemy(BUZZ_SCENE)
		1: _spawn_enemy(LOUIE_SCENE)
		2: _spawn_enemy(LADY_SCENE)
		3: _spawn_enemy(FIZZ_SCENE)
		4: _spawn_enemy(FANG_SCENE)
		_: pass


func _clear_enemies() -> void:
	if not enemy_container:
		return
	for child in enemy_container.get_children():
		if child.is_in_group("bubba"):
			continue
		child.queue_free()


func _spawn_enemy(scene: PackedScene) -> void:
	if not enemy_container or not scene:
		return

	var enemy := scene.instantiate() as Node2D
	enemy_container.add_child(enemy)
	enemy.global_position = WORLD_CENTER + Vector2(-400.0, 0.0)
	enemy.add_to_group("enemy")

	if get_tree().paused or _world_frozen or waiting_for_start or game_over:
		_set_node_frozen(enemy, true)
		_set_node_processing(enemy, false)


func _trigger_enemy_intro_if_allowed() -> void:
	if waiting_for_start or game_over:
		return
	if _world_frozen or get_tree().paused:
		return
	if room_index != 0:
		return
	if enemy_container == null:
		return

	for child in enemy_container.get_children():
		if child and child.has_method("play_intro"):
			child.call_deferred("play_intro")
			return


func _set_background(tex: Texture2D) -> void:
	if not background:
		return
	background.texture = tex
	background.centered = true
	background.position = WORLD_CENTER
	background.z_index = -10
	background.scale = Vector2.ONE
	background.offset = Vector2.ZERO


func reload_current_game() -> void:
	_game_def = _get_current_game_def()
	if _game_def == null:
		push_error("GameplayRoot: CurrentGame has no GameDef.")
		return

	apply_game(_game_def)

	if not _get_room_backgrounds().is_empty():
		_apply_room(start_room_index, true)


func apply_game(game_def: GameDef) -> void:
	if game_def == null or game_def.player_scene == null:
		push_error("GameplayRoot: GameDef missing or player_scene not set.")
		return
	if not player_spawn:
		push_error("GameplayRoot: Missing PlayerSpawn.")
		return

	_game_def = game_def
	_room_backgrounds = game_def.room_backgrounds
	_room_enemy_scenes = game_def.room_enemy_scenes

	var mp := _get_music_player()
	if mp:
		if ("music_stream" in game_def) and game_def.music_stream:
			mp.stream = game_def.music_stream
		else:
			mp.stream = null
		if waiting_for_start and mp.playing:
			mp.stop()

	if is_instance_valid(player_instance):
		player_instance.queue_free()

	player_instance = game_def.player_scene.instantiate() as Node2D
	_apply_player_visual_to_instance(player_instance, game_def)
	add_child(player_instance)

	player_instance.scale = Vector2.ONE
	player_instance.rotation = 0.0
	player_instance.skew = 0.0

	player_instance.global_position = player_spawn.global_position
	_setup_camera()
	player_instance.add_to_group("player")
	_apply_player_visual()

	if get_tree().paused or _world_frozen or waiting_for_start:
		_set_node_frozen(player_instance, true)
		_set_node_processing(player_instance, false)


func _apply_player_visual() -> void:
	if player_instance == null:
		return
	_apply_player_visual_to_instance(player_instance, _game_def)


func _apply_player_visual_to_instance(p: Node2D, game_def: GameDef) -> void:
	if p == null:
		return

	var spr_node: Sprite2D = p.get_node_or_null("Sprite2D") as Sprite2D
	var anim_node: AnimatedSprite2D = p.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

	var scene_sprite_scale: Vector2 = (spr_node.scale if spr_node else Vector2.ONE)
	var scene_anim_scale: Vector2 = (anim_node.scale if anim_node else Vector2.ONE)

	var wants_sheet := false
	var frames: SpriteFrames = null

	if game_def != null:
		if "player_use_sprite_sheet" in game_def:
			wants_sheet = bool(game_def.player_use_sprite_sheet)
		if "player_sprite_frames" in game_def:
			frames = game_def.player_sprite_frames as SpriteFrames

	var enable_sheet := wants_sheet and (anim_node != null) and (frames != null)

	var has_scale_override := false
	var scale_override := Vector2.ZERO
	if game_def != null and ("player_sprite_scale" in game_def):
		scale_override = game_def.player_sprite_scale
		has_scale_override = (scale_override != Vector2.ZERO)

	if enable_sheet:
		if anim_node:
			anim_node.visible = true
			anim_node.sprite_frames = frames
			if frames.has_animation("idle"):
				anim_node.play("idle")
			elif frames.get_animation_names().size() > 0:
				anim_node.play(frames.get_animation_names()[0])

		if spr_node:
			spr_node.visible = false

		if anim_node:
			anim_node.scale = (scale_override if has_scale_override else scene_anim_scale)

	else:
		if anim_node:
			anim_node.stop()
			anim_node.visible = false
			anim_node.sprite_frames = null

		if spr_node:
			spr_node.visible = true
			if game_def != null and ("player_sprite_texture" in game_def) and game_def.player_sprite_texture:
				spr_node.texture = game_def.player_sprite_texture
			spr_node.scale = (scale_override if has_scale_override else scene_sprite_scale)


func _setup_camera() -> void:
	if not cam:
		return
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.make_current()
	cam.zoom = Vector2.ONE
	cam.offset = Vector2.ZERO
	cam.position_smoothing_enabled = false
	cam.global_position = WORLD_CENTER


func _force_viewport_settle() -> void:
	await get_tree().process_frame

	var vp := get_viewport()
	if vp:
		vp.canvas_transform = Transform2D.IDENTITY
		vp.global_canvas_transform = Transform2D.IDENTITY

	_setup_camera()
	_reset_player_position()
	_apply_player_visual()


func _ensure_game_selected() -> void:
	if not CurrentGame.has_game() and default_game_def:
		if CurrentGame.has_method("set_game"):
			CurrentGame.set_game(default_game_def)
		else:
			CurrentGame.def = default_game_def


func _get_current_game_def() -> GameDef:
	if CurrentGame.has_method("get_game"):
		return CurrentGame.get_game() as GameDef
	if "def" in CurrentGame:
		return (CurrentGame.def as GameDef)
	return null


func _get_room_backgrounds() -> Array[Texture2D]:
	if _room_backgrounds.size() > 0:
		return _room_backgrounds
	return room_backgrounds


func _on_paw_baseball_check(cents: int) -> void:
	if _paw_baseball_spawned:
		return
	if waiting_for_start or game_over:
		return

	var gd := _get_current_game_def()
	if gd == null or gd.game_id != &"Paw Paw":
		return
	if cents < 2820:
		return

	_paw_baseball_spawned = true
	_spawn_paw_baseball()


func _spawn_paw_baseball() -> void:
	if not PAW_BASEBALL_SCENE:
		push_error("GameplayRoot: PAW_BASEBALL_SCENE not found — check res://series/paw/paw_baseball_player.tscn")
		return

	var player := PAW_BASEBALL_SCENE.instantiate() as Node2D
	if player == null:
		return

	player.name = "PawBaseballPlayerHelper"
	add_child(player)
	print("⚾ Paw Paw Baseball Player launched at $28.20!")
