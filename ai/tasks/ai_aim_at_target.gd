@tool
class_name AIAimAtTarget
extends EntityBTAction
## Keeps the entity facing the target, or its last known position.

func _tick(_delta: float) -> Status:
	var ai: AIController = _ai()
	if ai == null or ai.perception == null:
		return FAILURE
	if not ai.perception.has_target():
		return FAILURE
	ai.set_aim_position(ai.perception.get_target_position())
	return RUNNING
