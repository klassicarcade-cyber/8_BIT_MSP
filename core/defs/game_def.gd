extends Resource
class_name GameDef

@export_category("Identity")
@export var game_id: StringName = &""
@export var title: String = ""

@export_category("Player")
@export var player_scene: PackedScene
@export var player_sprite_texture: Texture2D
@export var player_sprite_scale: Vector2 = Vector2.ONE
@export var music_stream: AudioStream

# NEW — sprite sheet support (optional per game)
@export var player_use_sprite_sheet: bool = false
@export var player_sprite_frames: SpriteFrames

@export_category("Backgrounds / Rooms")
# (Older single background kept for back-compat if you still use it anywhere)
@export var background_texture: Texture2D
# Preferred: per-room list
@export var room_backgrounds: Array[Texture2D] = []
@export var room_enemy_scenes: Array[PackedScene] = []

@export_category("Pickups (Textures)")
@export var bottle_texture: Texture2D
@export var can_texture: Texture2D
@export var bottle_scale: Vector2 = Vector2.ONE
@export var can_scale: Vector2 = Vector2.ONE

# ----------------------------------------------------
# Optional helper: sanity check in editor / runtime
# Call from GameplayRoot after apply_game() if you want.
# ----------------------------------------------------
func debug_summary() -> String:
	var bg_count := room_backgrounds.size()
	var en_count := room_enemy_scenes.size()
	return "GameDef[%s] rooms=%d enemies=%d player_scene=%s" % [
		String(game_id),
		bg_count,
		en_count,
		(player_scene.resource_path if player_scene else "<null>")
	]
