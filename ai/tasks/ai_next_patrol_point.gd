@tool
class_name AINextPatrolPoint
extends EntityBTAction
## Advances the patrol index and writes the chosen point to the blackboard.

@export var points_var: StringName = &"patrol_points"
@export var index_var: StringName = &"patrol_index"
@export var point_var: StringName = &"patrol_point"

func _tick(_delta: float) -> Status:
	var points_value: Variant = blackboard.get_var(points_var, [])
	if not points_value is Array:
		return FAILURE
	var points: Array = points_value
	if points.is_empty():
		return FAILURE
	var index: int = int(blackboard.get_var(index_var, 0))
	index = posmod(index, points.size())
	var point_value: Variant = points[index]
	if not point_value is Vector2:
		return FAILURE
	blackboard.set_var(point_var, point_value as Vector2)
	blackboard.set_var(index_var, posmod(index + 1, points.size()))
	return SUCCESS
