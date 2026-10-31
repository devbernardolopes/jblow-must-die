extends Node2D

@onready var base: Polygon2D = $Terrain/Base
@onready var enemies: Node2D = $Entities/Enemies
@onready var outer_walls: Node2D = $Walls/OuterWalls

func _ready() -> void:
	if base:
		base.visible = true
	if enemies:
		enemies.visible = true
	if outer_walls:
		outer_walls.visible = true
		
	MusicManager.play_01()
