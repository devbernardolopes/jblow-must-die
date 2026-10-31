@tool
class_name AIMoveToPoint
extends EntityBTAction
## Steers directly at a world-space point until the arrival distance is reached.

@export var point_var: StringName = &"patrol_point"
## Center-to-center distance that counts as arrived, in meters.
@export var arrival_distance_m: float = 1.0
## Whether to run while moving.
@export var run: bool = false

func _generate_name() -> String:
	return "MoveToPoint '%s'" % point_var

func _tick(_delta: float) -> Status:
	var ai: AIController = _ai()
	if ai == null or entity == null:
		return FAILURE
	var point_value: Variant = blackboard.get_var(point_var, null)
	if not point_value is Vector2:
		return FAILURE
	var point: Vector2 = point_value
	var offset: Vector2 = point - entity.global_position
	var arrival_px: float = Units.m_to_px(maxf(arrival_distance_m, 0.0))
	if offset.length_squared() <= arrival_px * arrival_px:
		return SUCCESS
	ai.set_aim_position(point)
	ai.set_move_direction(offset.normalized())
	ai.set_running(run)
	return RUNNING
