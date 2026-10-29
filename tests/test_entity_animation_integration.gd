extends SceneTree
## Headless integration checks for Entity + EntityAnimator. No gameplay scene.

var _failures: int = 0

class FakeController extends EntityController:
	var move_vector: Vector2 = Vector2.ZERO
	var action_request: StringName = &""

	func get_move_vector() -> Vector2:
		return move_vector

	func get_move_intent() -> Vector2:
		return move_vector

	func get_action_request() -> StringName:
		return action_request

func _init() -> void:
	_test_handgun()
	_test_zombie()
	if _failures == 0:
		print("Entity animation integration tests: PASS")
		quit(0)
	else:
		printerr("Entity animation integration tests: %d failure(s)" % _failures)
		quit(1)

func _test_handgun() -> void:
	var entity := Entity.new()
	entity.data = load("res://resources/entities/web_developer/web_developer.tres")
	entity.current_weapon = load("res://resources/weapons/handgun_weapon.tres")
	var controller := FakeController.new()
	entity.set_controller(controller)
	root.add_child(entity)

	_assert(entity.animator != null, "entity creates an animator")
	if entity.animator == null:
		entity.free()
		return
	_assert(entity.animator.get_animation_set_id() == &"handgun", "handgun set is active")
	_assert(entity.animator.get_current_animation() == &"idle", "idle is playing")

	var triggered: Array[StringName] = []
	entity.action_triggered.connect(
		func(action_id: StringName) -> void: triggered.append(action_id)
	)
	_assert(entity.try_action(&"shoot"), "shoot starts")
	_assert(entity.animator.is_busy(), "entity is busy")
	_assert(entity.animator.locks_movement(), "shoot locks movement")
	entity.visual.frame = 1
	_assert(triggered.size() == 1 and triggered[0] == &"shoot", "shoot trigger is forwarded")
	entity.animator.cancel_action()

	entity.current_weapon = load("res://resources/weapons/knife_weapon.tres")
	_assert(entity.animator.get_animation_set_id() == &"knife", "knife set is active")
	_assert(entity.animator.get_current_animation() == &"idle", "knife idle is playing")
	_assert(entity.try_action(&"melee_attack"), "melee starts with the knife")

	entity.free()

func _test_zombie() -> void:
	var entity := Entity.new()
	entity.data = load("res://resources/entities/zombies/zombie.tres")
	var controller := FakeController.new()
	controller.action_request = &"attack"
	entity.set_controller(controller)
	root.add_child(entity)

	_assert(entity.animator != null, "zombie creates an animator")
	if entity.animator == null:
		entity.free()
		return
	_assert(entity.animator.get_animation_set_id() == &"hands", "zombie hands set is active")
	_assert(entity.animator.get_current_animation() == &"idle", "zombie idle is playing")
	entity._try_controller_action()
	_assert(entity.animator.get_action_id() == &"attack", "zombie attack starts from the controller")
	entity.animator.cancel_action()

	entity.free()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
