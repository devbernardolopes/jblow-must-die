@tool
class_name EntityBTCondition
extends BTCondition
## Base for AI conditions that inspect an Entity through its AIController.

var entity: Entity = null

func _setup() -> void:
	if Engine.is_editor_hint():
		return
	entity = agent as Entity

## Resolved lazily because the tree is initialized before Entity._ready().
func _ai() -> AIController:
	if entity == null and not Engine.is_editor_hint():
		entity = agent as Entity
	if entity == null or not is_instance_valid(entity):
		return null
	return entity.controller as AIController
