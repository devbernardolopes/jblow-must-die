@tool
class_name AITargetVisible
extends EntityBTCondition
## Succeeds while the remembered target was seen during the last scan.

func _tick(_delta: float) -> Status:
	var ai: AIController = _ai()
	if ai == null or ai.perception == null:
		return FAILURE
	return SUCCESS if ai.perception.is_target_visible() else FAILURE
