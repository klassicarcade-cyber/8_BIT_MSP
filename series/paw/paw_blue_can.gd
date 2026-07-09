# paw_blue_can.gd
# Blue Mr. Sodapop baseball can — drops from above into the player's mitt.
# Spawned and controlled by paw_baseball_player.gd.

extends Node2D

@export var can_scale: Vector2 = Vector2(0.4, 0.4)

@onready var spr: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

func _ready() -> void:
	if spr:
		spr.scale = can_scale
