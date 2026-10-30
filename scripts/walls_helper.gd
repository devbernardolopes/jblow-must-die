@tool
extends Node2D

@export_range(0.0, 0.5, 0.005) var height_factor: float = 0.06:
	set(v):
		height_factor = v
		update_children_height_factor()

@export var disable_editor: bool = false:
	set(v):
		disable_editor = v

func update_children_height_factor() -> void:
	var wall_children = find_children("*")
	if wall_children and not wall_children.is_empty():
		for i in wall_children.size():
			if wall_children[i] is Wall:
				(wall_children[i] as Wall).height_factor = height_factor

func update_children_disable_editor() -> void:
	var wall_children = find_children("*")
	if wall_children and not wall_children.is_empty():
		for i in wall_children.size():
			if wall_children[i] is Wall:
				(wall_children[i] as Wall).disable_editor = disable_editor
