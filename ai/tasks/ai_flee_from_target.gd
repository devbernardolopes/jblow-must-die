@tool
class_name AIFleeFromTarget
extends EntityBTAction
## Runs directly away from the target until the safe distance is reached.

@export var safe_distance_m: float = 30.0

func _generate_name() -> String:
	return "FleeFromTarget (safe %.1f m)" % safe_distance_m

func _tick(_delta: float) -> Status:
	var ai: AIController = _ai()
	if ai == null or ai.perception == null or entity == null:
		return FAILURE
	if not ai.perception.has_target():
		return FAILURE
	var target_position: Vector2 = ai.perception.get_target_position()
	var offset: Vector2 = entity.global_position - target_position
	var safe_px: float = Units.m_to_px(maxf(safe_distance_m, 0.0))
	if offset.length_squared() >= safe_px * safe_px:
		return RUNNING
	if offset.is_zero_approx():
		offset = -entity.facing
	var flee_direction: Vector2 = offset.normalized()
	ai.set_aim_position(entity.global_position + flee_direction)
	ai.set_move_direction(flee_direction)
	ai.set_running(true)
	return RUNNING
