extends Node

# How long with no input before the screensaver appears.
@export var idle_seconds: float = 60.0

# Ignore tiny joystick drift
@export var joy_deadzone: float = 0.35

# Debug prints
@export var debug_idle: bool = false

var _idle: float = 0.0
var _active: bool = false
var _debug_next_mark: int = 5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_idle = 0.0
	_active = false

	if debug_idle:
		print("AttractController READY | idle_seconds=", idle_seconds)


func _process(delta: float) -> void:
	if _active:
		return

	# Don't count idle time while waiting for player to press Start.
	# GameplayRoot exposes waiting_for_start; reset our timer so the
	# countdown begins fresh once the round actually starts.
	var root := get_parent()
	if root and "waiting_for_start" in root and root.waiting_for_start:
		_idle = 0.0
		_debug_next_mark = 5
		return

	_idle += delta

	if debug_idle:
		var sec := int(_idle)
		if sec >= _debug_next_mark:
			print("IDLE:", _idle, "/", idle_seconds)
			_debug_next_mark += 5

	if _idle >= idle_seconds:
		_enter_screensaver()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_real_input(event):
		return

	_idle = 0.0
	_debug_next_mark = 5

	if _active:
		_exit_screensaver()
		if debug_idle:
			print("AttractController: screensaver dismissed")


func _enter_screensaver() -> void:
	_active = true
	_idle = 0.0
	_debug_next_mark = 5

	if debug_idle:
		print("AttractController: entering screensaver")

	# Freeze gameplay
	get_tree().call_group("player", "set_frozen", true)
	for e in get_tree().get_nodes_in_group("enemy"):
		if "frozen" in e:
			e.frozen = true

	# Tell the overlay to show itself.
	var overlay := _find_screensaver_overlay()
	if debug_idle:
		print("AttractController: overlay found=", overlay)
	if overlay and overlay.has_method("show_screensaver"):
		overlay.call("show_screensaver")
	elif overlay:
		overlay.show()
	else:
		print("AttractController: ERROR - no ScreensaverOverlay found!")


func _exit_screensaver() -> void:
	_active = false
	_idle = 0.0
	_debug_next_mark = 5

	if debug_idle:
		print("AttractController: exiting screensaver")

	# Unfreeze gameplay
	get_tree().call_group("player", "set_frozen", false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if "frozen" in e:
			e.frozen = false


func _find_screensaver_overlay() -> Node:
	# 1. Look for a sibling named ScreensaverOverlay
	var parent := get_parent()
	if parent:
		var sibling := parent.get_node_or_null("ScreensaverOverlay")
		if sibling:
			return sibling

	# 2. Search by group
	var by_group := get_tree().get_first_node_in_group("screensaver_overlay")
	if by_group:
		return by_group

	# 3. Broad search from root (catches deep nesting)
	var by_name := get_tree().root.find_child("ScreensaverOverlay", true, false)
	if by_name:
		return by_name

	return null


func _is_real_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) > joy_deadzone
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	return false
