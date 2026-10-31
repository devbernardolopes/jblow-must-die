@tool
class_name AIHasTarget
extends EntityBTCondition
## Succeeds while perception holds a visible or remembered hostile target.

func _tick(_delta: float) -> Status:
	var ai: AIController = _ai()
	if ai == null or ai.perception == null:
		return FAILURE
	return SUCCESS if ai.perception.has_target() else FAILURE
