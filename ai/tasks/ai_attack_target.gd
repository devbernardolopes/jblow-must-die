@tool
class_name AIAttackTarget
extends EntityBTAction
## Requests the equipped attack action while a visible target is in range.

## Maximum center-to-center distance at which attacks are requested, in meters.
@export var range_m: float = 10.0

func _generate_name() -> String:
	return "AttackTarget (range %.1f m)" % range_m

func _tick(_delta: float) -> Status:
	var ai: AIController = _ai()
	if ai == null or ai.perception == null or entity == null:
		return FAILURE
	if not ai.perception.is_target_visible():
		return RUNNING
	var target: Entity = ai.perception.get_target()
	if target == null:
		return FAILURE
	var offset: Vector2 = target.global_position - entity.global_position
	var range_px: float = Units.m_to_px(maxf(range_m, 0.0))
	if offset.length_squared() > range_px * range_px:
		return RUNNING
	if entity.current_weapon == null:
		return RUNNING
	if entity.is_out_of_ammo(entity.current_weapon):
		ai.request_action(entity.current_weapon.reload_action)
		return RUNNING
	ai.request_action(entity.current_weapon.attack_action)
	return RUNNING
