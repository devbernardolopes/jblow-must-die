@tool
class_name AIChaseTarget
extends EntityBTAction
## Steers directly at the target until inside the stop distance.

## Center-to-center distance at which the entity stops approaching, in meters.
@export var stop_distance_m: float = 8.0

func _generate_name() -> String:
	return "ChaseTarget (stop %.1f m)" % stop_distance_m

func _tick(_delta: float) -> Status:
	var ai: AIController = _ai()
	if ai == null or ai.perception == null or entity == null:
		return FAILURE
	if not ai.perception.has_target():
		return FAILURE
	var target_position: Vector2 = ai.perception.get_target_position()
	ai.set_aim_position(target_position)
	var offset: Vector2 = target_position - entity.global_position
	var stop_px: float = Units.m_to_px(maxf(stop_distance_m, 0.0))
	if offset.length_squared() <= stop_px * stop_px:
		return RUNNING
	ai.set_move_direction(offset.normalized())
	ai.set_running(true)
	return RUNNING
