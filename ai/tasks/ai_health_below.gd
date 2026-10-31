@tool
class_name AIHealthBelow
extends EntityBTCondition
## Succeeds while the entity's health ratio is below the threshold.

@export_range(0.0, 1.0, 0.01) var threshold: float = 0.25

func _generate_name() -> String:
	return "HealthBelow %.0f%%" % (threshold * 100.0)

func _tick(_delta: float) -> Status:
	if entity == null or not is_instance_valid(entity):
		return FAILURE
	return SUCCESS if entity.get_health_ratio() < threshold else FAILURE
