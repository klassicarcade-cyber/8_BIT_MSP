extends CanvasLayer

@export var slide_seconds: float = 6.0

# Optional: drag textures here if you want to manually add extras
@export var slides: Array[Texture2D] = []

# Set this in Inspector OR leave blank to use default below
@export var slides_dir: String = ""

# Leave as "" to allow ANY image in the folder
@export var slides_prefix: String = "saver_"

# If true, rebuild playlist every time screensaver starts
@export var rescan_on_show: bool = true

@onready var slide_rect: TextureRect = $Root/Slide

var _playlist: Array[Texture2D] = []
var _playlist_paths: Array[String] = []

var _i: int = 0
var _t: float = 0.0

const _EXTS := ["png", "webp", "jpg", "jpeg"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200

	# Force full screen
	if slide_rect:
		slide_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		slide_rect.offset_left = 0
		slide_rect.offset_top = 0
		slide_rect.offset_right = 0
		slide_rect.offset_bottom = 0
		slide_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slide_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_force_fullscreen_rect()

	_build_playlist()
	hide()

	print("ScreensaverOverlay READY. playlist=", _playlist.size())

func show_screensaver() -> void:
	if rescan_on_show:
		_build_playlist()

	print("ScreensaverOverlay: show_screensaver() playlist=", _playlist.size())

	if _playlist.is_empty():
		print("ScreensaverOverlay: NO slides found.")
		return

	# Hide dim overlays so they don't darken the screensaver
	for node_name in ["UI_Dim", "DimRoot", "Dim"]:
		var n := get_tree().root.find_child(node_name, true, false)
		if n:
			n.visible = false

	show()
	_i = 0
	_t = 0.0
	_force_fullscreen_rect()
	_apply_slide()

func hide_screensaver() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not _is_real_input(event):
		return
	if _is_h_pressed(event):
		hide()
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://core/ui/high_score_viewer.tscn")
		return
	hide()
	# Do not consume - let underlying scene also react


func _is_h_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo and k.physical_keycode == KEY_H
	return false


func _is_real_input(event: InputEvent) -> bool:
	if event is InputEventKey: return (event as InputEventKey).pressed
	if event is InputEventJoypadButton: return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion: return absf((event as InputEventJoypadMotion).axis_value) > 0.35
	if event is InputEventMouseButton: return (event as InputEventMouseButton).pressed
	return false


func _process(delta: float) -> void:
	if not visible:
		return
	if _playlist.is_empty():
		return

	_t += delta
	if _t >= slide_seconds:
		_t = 0.0
		_i += 1
		if _i >= _playlist.size():
			_i = 0
		_apply_slide()

func _apply_slide() -> void:
	if slide_rect and not _playlist.is_empty():
		slide_rect.texture = _playlist[_i]

		var path := "<unknown>"
		if _i < _playlist_paths.size():
			path = _playlist_paths[_i]

		print("ScreensaverOverlay: showing slide ", _i, "/", _playlist.size(), " file=", path)

# Keep fullscreen even if window/viewport size changes
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_force_fullscreen_rect()

func _force_fullscreen_rect() -> void:
	if not slide_rect:
		return
	slide_rect.position = Vector2.ZERO
	slide_rect.size = get_viewport().get_visible_rect().size

# --------------------------------------------------
# PLAYLIST BUILDER
# --------------------------------------------------

func _build_playlist() -> void:
	_playlist.clear()
	_playlist_paths.clear()

	var hardcoded := [
		"res://core/screensavers/rules_111.png",
		"res://core/screensavers/rules_888.png",
		"res://core/screensavers/rules_909.png",
	]

	for path in hardcoded:
		var res := load(path)
		if res and res is Texture2D:
			_playlist.append(res)
			_playlist_paths.append(path)

	for tex in slides:
		if tex != null:
			_playlist.append(tex)
			_playlist_paths.append("<inspector>")

	print("ScreensaverOverlay: built playlist size=", _playlist.size())

func _resolve_slides_dir() -> String:
	if slides_dir.strip_edges() != "":
		return slides_dir

	# Default safe location
	return "res://core/screensavers"

func _autoload_slides_into(target: Array[Texture2D], dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		print("ScreensaverOverlay: FAILED to open dir:", dir_path)
		return

	var names: Array[String] = []

	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "":
			break
		if dir.current_is_dir():
			continue

		var lower := f.to_lower()
		var ext := lower.get_extension()

		if not _EXTS.has(ext):
			continue

		if slides_prefix.strip_edges() != "":
			if not lower.begins_with(slides_prefix.to_lower()):
				continue

		names.append(f)

	dir.list_dir_end()

	names.sort()

	for f in names:
		var path := dir_path.rstrip("/") + "/" + f
		var res := load(path)

		if res == null:
			print("ScreensaverOverlay: LOAD FAILED:", path)
			continue

		if res is Texture2D:
			target.append(res)
			_playlist_paths.append(path)
		else:
			print("ScreensaverOverlay: NOT Texture2D:", path, " type=", res.get_class())

	print("ScreensaverOverlay: autoloaded", target.size(), "images (scanned", names.size(), ")")
