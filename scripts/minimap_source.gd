@tool
class_name MinimapSource
extends Node2D
## Authored minimap shape. Parent it to a door, an Area2D, a POI, or anything
## else that should appear on the map. Points are in this node's local space,
## so the shape follows its parent's transform.

@export var kind: MinimapGeometry.Kind = MinimapGeometry.Kind.AREA:
	set(value):
		kind = value
		notify_minimap_changed()
## Shape points in this node's local space.
@export var points: PackedVector2Array = PackedVector2Array():
	set(value):
		points = value
		notify_minimap_changed()
@export var closed: bool = false:
	set(value):
		closed = value
		notify_minimap_changed()
@export var filled: bool = false:
	set(value):
		filled = value
		notify_minimap_changed()
## Color.TRANSPARENT uses the Minimap's default color for the kind.
@export var color: Color = Color.TRANSPARENT:
	set(value):
		color = value
		notify_minimap_changed()
@export var minimap_visible: bool = true:
	set(value):
		minimap_visible = value
		notify_minimap_changed()


func _ready() -> void:
	add_to_group(&"minimap_source")
	call_deferred(&"notify_minimap_changed")


func get_minimap_geometry() -> Array[MinimapGeometry]:
	var result: Array[MinimapGeometry] = []
	if not minimap_visible or points.size() < 2:
		return result
	var geometry := MinimapGeometry.new()
	geometry.kind = kind
	geometry.closed = closed
	geometry.filled = filled
	geometry.color = color
	var global_points := PackedVector2Array()
	global_points.resize(points.size())
	for index: int in range(points.size()):
		global_points[index] = global_transform * points[index]
	geometry.points = global_points
	result.append(geometry)
	return result


## Call after mutating a shape at runtime so the minimap rebuilds its cache.
func notify_minimap_changed() -> void:
	if not is_inside_tree():
		return
	var minimap := get_tree().get_first_node_in_group(&"minimap") as Minimap
	if minimap != null:
		minimap.rebuild_geometry()
