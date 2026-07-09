extends Node2D

# ============================================================
#  RobotCameo.gd
#  Place RobotCameo.tscn at res://series/mars/robot_cameo/
#  Called automatically by gameplay_root.gd at 20 seconds
# ============================================================

# --- EASY TUNING CONSTANTS ----------------------------------
const ROBOT_SCALE       := 0.55
const ROLL_START_X      := 1400.0
const ROLL_STOP_X       := 820.0
const ROBOT_Y           := 840.0
const ROLL_DURATION     := 1.8
const WAVE_LOOPS        := 3
const WAVE_FRAME_DELAY  := 0.18
const TALK_DURATION     := 3.0
const POOF_DURATION     := 0.6

# --- SPRITE SHEET INFO (4x4 grid, 16 frames) ----------------
const HFRAMES := 4
const VFRAMES := 4

const WAVE_FRAMES_A := [8, 9, 10, 11]
const WAVE_FRAMES_B := [12, 13, 14, 15]
const IDLE_FRAMES   := [4, 5, 6, 7]
const ROLL_FRAMES   := [0, 1, 2, 3]

# ------------------------------------------------------------
var _sprite      : Sprite2D
var _bubble      : CanvasLayer
var _bubble_panel: Panel
var _bubble_label: Label
var _poof        : CPUParticles2D
var _talk_sfx    : AudioStreamPlayer

var _state       := "idle"
var _wave_count  := 0
var _wave_frame  := 0
var _frame_timer : Timer

signal cameo_finished

# ============================================================
func _ready() -> void:
	_build_sprite()
	_build_bubble()
	_build_poof()
	_build_talk_sfx()
	visible = false

# ============================================================
func start_cameo() -> void:
	visible = true
	position = Vector2(ROLL_START_X, ROBOT_Y)
	_sprite.frame = ROLL_FRAMES[0]
	_state = "rolling"
	_roll_in()

# ============================================================
#  PHASE 1 — roll in from right
# ============================================================
func _roll_in() -> void:
	_sprite.frame = ROLL_FRAMES[0]
	var tween := create_tween()
	tween.tween_property(self, "position:x", ROLL_STOP_X, ROLL_DURATION)\
		 .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_on_arrived)

func _on_arrived() -> void:
	_state = "waving"
	_wave_count = 0
	_wave_frame = 0
	_start_wave_cycle()

# ============================================================
#  PHASE 2 — wave arms
# ============================================================
func _start_wave_cycle() -> void:
	if _wave_count >= WAVE_LOOPS:
		_show_talk_bubble()
		return
	_frame_timer = Timer.new()
	add_child(_frame_timer)
	_frame_timer.wait_time = WAVE_FRAME_DELAY
	_frame_timer.timeout.connect(_advance_wave)
	_frame_timer.start()

func _advance_wave() -> void:
	var src := WAVE_FRAMES_A if (_wave_count % 2 == 0) else WAVE_FRAMES_B
	_sprite.frame = src[_wave_frame % src.size()]
	_wave_frame += 1
	if _wave_frame >= src.size():
		_wave_frame = 0
		_wave_count += 1
		if _wave_count >= WAVE_LOOPS:
			_frame_timer.stop()
			_frame_timer.queue_free()
			_show_talk_bubble()

# ============================================================
#  PHASE 3 — speech bubble + audio
# ============================================================
func _show_talk_bubble() -> void:
	_state = "talking"
	_sprite.frame = IDLE_FRAMES[0]
	if _talk_sfx:
		_talk_sfx.play()
	_bubble.visible = true
	await get_tree().create_timer(TALK_DURATION).timeout
	_bubble.visible = false
	_do_poof()

# ============================================================
#  PHASE 4 — poof and disappear
# ============================================================
func _do_poof() -> void:
	_state = "poofing"
	_sprite.visible = false
	_poof.emitting = true
	await get_tree().create_timer(POOF_DURATION).timeout
	visible = false
	emit_signal("cameo_finished")

# ============================================================
#  BUILD HELPERS
# ============================================================
func _build_sprite() -> void:
	var spr := Sprite2D.new()
	spr.name = "RobotSprite"
	spr.texture = load("res://series/mars/robot_cameo/robot_sheet.png")
	spr.hframes = HFRAMES
	spr.vframes = VFRAMES
	spr.frame   = 0
	spr.scale   = Vector2(ROBOT_SCALE, ROBOT_SCALE)
	add_child(spr)
	_sprite = spr

func _build_bubble() -> void:
	_bubble = CanvasLayer.new()
	_bubble.layer = 10
	add_child(_bubble)

	_bubble_panel = Panel.new()
	_bubble_panel.size = Vector2(320, 90)
	_bubble_panel.position = Vector2(ROLL_STOP_X - 260, ROBOT_Y - 200)
	_bubble.add_child(_bubble_panel)

	_bubble_label = Label.new()
	_bubble_label.text = "DANGER WILL ROBINSON!"
	_bubble_label.add_theme_font_size_override("font_size", 22)
	_bubble_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_bubble_panel.add_child(_bubble_label)

	_bubble.visible = false

func _build_poof() -> void:
	_poof = CPUParticles2D.new()
	_poof.emitting       = false
	_poof.one_shot       = true
	_poof.amount         = 80
	_poof.lifetime       = 0.5
	_poof.explosiveness  = 0.95
	_poof.direction      = Vector2(0, -1)
	_poof.spread         = 180.0
	_poof.gravity        = Vector2(0, 60)
	_poof.initial_velocity_min = 80.0
	_poof.initial_velocity_max = 220.0
	_poof.scale_amount_min = 6.0
	_poof.scale_amount_max = 14.0
	_poof.color          = Color(0.95, 0.95, 0.95, 0.9)
	add_child(_poof)

func _build_talk_sfx() -> void:
	var sfx_path := "res://series/mars/robot_cameo/danger_will_robinson.wav"
	if not ResourceLoader.exists(sfx_path):
		push_warning("RobotCameo: SFX not found at " + sfx_path)
		return
	_talk_sfx = AudioStreamPlayer.new()
	_talk_sfx.stream = load(sfx_path)
	add_child(_talk_sfx)

# ============================================================
#  Public helper — change speech bubble text at runtime
# ============================================================
func set_dialog(text: String) -> void:
	if _bubble_label:
		_bubble_label.text = text
