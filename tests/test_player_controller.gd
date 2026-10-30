extends SceneTree
## Headless checks for cursor aim, relative turning and mouse-relative strafing.
## No gameplay scene is started.

var _failures: int = 0

class FakeController extends EntityController:
	var move_vector: Vector2 = Vector2.ZERO
	var move_intent: Vector2 = Vector2.ZERO

	func get_move_vector() -> Vector2:
		return move_vector

	func get_move_intent() -> Vector2:
		return move_intent

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	await _test_aim_request()
	_test_relative_rotation()
	_test_relative_mouse_vector()
	_test_intent_selection()
	if _failures == 0:
		print("Player controller tests: PASS")
		quit(0)
	else:
		printerr("Player controller tests: %d failure(s)" % _failures)
		quit(1)

func _test_aim_request() -> void:
	var entity := Entity.new()
	entity.data = load("res://resources/entities/web_developer/web_developer.tres") as EntityData
	var controller := PlayerController.new()
	entity.add_child(controller)
	root.add_child(entity)
	await process_frame

	controller.movement_mode = EntityController.MovementMode.RELATIVE
	controller.mouse_aim_enabled = true

	var mouse_world: Vector2 = entity.get_global_mouse_position()
	entity.global_position = mouse_world + Vector2(100.0, 0.0)

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(12.0, -3.0)
	controller._input(motion)
	_assert_vec(controller.consume_aim_direction(), Vector2.LEFT, "cursor aim points at the mouse")
	_assert(
		controller.consume_aim_direction().is_zero_approx(),
		"aim is consumed once per tick"
	)

	var still := InputEventMouseMotion.new()
	controller._input(still)
	_assert(
		controller.consume_aim_direction().is_zero_approx(),
		"a still mouse does not request aim"
	)

	controller._input(motion)
	controller.mouse_aim_enabled = false
	_assert(
		controller.consume_aim_direction().is_zero_approx(),
		"disabled mouse aim is ignored"
	)
	controller.mouse_aim_enabled = true

	controller.movement_mode = EntityController.MovementMode.OMNI
	controller._input(motion)
	_assert(
		controller.consume_aim_direction().is_zero_approx(),
		"OMNI mode ignores cursor aim"
	)

	controller.movement_mode = EntityController.MovementMode.RELATIVE_MOUSE
	controller._input(motion)
	_assert_vec(
		controller.consume_aim_direction(),
		Vector2.LEFT,
		"RELATIVE_MOUSE also aims at the cursor"
	)

	controller.movement_mode = EntityController.MovementMode.RELATIVE
	controller._input(motion)
	controller.movement_mode = EntityController.MovementMode.OMNI
	_assert(
		controller.consume_aim_direction().is_zero_approx(),
		"mode is re-checked when the aim is consumed"
	)

	entity.free()

func _test_relative_rotation() -> void:
	var entity := Entity.new()
	entity.facing = Vector2.RIGHT
	entity.rotation = 0.0

	var aiming: bool = entity._apply_relative_rotation(0.1, 0.0, PI, Vector2.DOWN)
	_assert(aiming, "aim reports aiming")
	_assert_vec(entity.facing, Vector2.DOWN, "aim sets facing")
	_assert(is_equal_approx(entity.rotation, PI * 0.5), "aim sets rotation instantly")

	entity.facing = Vector2.RIGHT
	entity.rotation = 0.0
	aiming = entity._apply_relative_rotation(1.0, 1.0, PI, Vector2.ZERO)
	_assert(not aiming, "keyboard turn is not aiming")
	_assert_vec(entity.facing, Vector2.LEFT, "keyboard turn rotates facing")
	_assert(is_equal_approx(entity.rotation, 0.0), "keyboard turn leaves smoothing to look_toward")

	entity.facing = Vector2.RIGHT
	entity.rotation = 0.0
	aiming = entity._apply_relative_rotation(1.0, 0.0, PI, Vector2.ZERO)
	_assert(not aiming, "no aim and no turn is not aiming")
	_assert_vec(entity.facing, Vector2.RIGHT, "no input leaves facing untouched")
	_assert(is_equal_approx(entity.rotation, 0.0), "no input leaves rotation untouched")

	entity.free()

func _test_relative_mouse_vector() -> void:
	_assert_vec(
		Entity.relative_mouse_vector(Vector2.RIGHT, 0.0, 1.0),
		Vector2.RIGHT,
		"throttle drives along the facing direction"
	)
	_assert_vec(
		Entity.relative_mouse_vector(Vector2.RIGHT, 1.0, 0.0),
		Vector2.DOWN,
		"positive strafe is the entity's right side"
	)
	_assert_vec(
		Entity.relative_mouse_vector(Vector2.RIGHT, -1.0, 0.0),
		Vector2.UP,
		"negative strafe is the entity's left side"
	)
	_assert_vec(
		Entity.relative_mouse_vector(Vector2.DOWN, 1.0, 0.0),
		Vector2.LEFT,
		"strafe follows the facing direction"
	)
	_assert_vec(
		Entity.relative_mouse_vector(Vector2.DOWN, 0.0, -1.0),
		Vector2.UP,
		"reverse throttle is opposite the facing direction"
	)
	var diagonal: Vector2 = Entity.relative_mouse_vector(Vector2.RIGHT, 1.0, 1.0)
	_assert(is_equal_approx(diagonal.length(), 1.0), "diagonal input does not speed up movement")
	_assert_vec(diagonal, Vector2(1.0, 1.0).normalized(), "diagonal input splits evenly")
	_assert_vec(
		Entity.relative_mouse_vector(Vector2.ZERO, 1.0, 0.0),
		Vector2.DOWN,
		"an unset facing falls back to east"
	)
	_assert(
		Entity.relative_mouse_vector(Vector2.RIGHT, 0.0, 0.0).is_zero_approx(),
		"no input means no movement"
	)

func _test_intent_selection() -> void:
	var entity := Entity.new()
	var controller := FakeController.new()
	controller.move_vector = Vector2(1.0, 0.0)
	controller.move_intent = Vector2(0.0, 1.0)
	entity.controller = controller

	controller.movement_mode = EntityController.MovementMode.OMNI
	_assert_vec(entity._get_intent(), Vector2(1.0, 0.0), "OMNI reads the screen-space vector")

	controller.movement_mode = EntityController.MovementMode.RELATIVE
	_assert_vec(entity._get_intent(), Vector2(0.0, 1.0), "RELATIVE reads turn and throttle")

	controller.movement_mode = EntityController.MovementMode.RELATIVE_MOUSE
	_assert_vec(entity._get_intent(), Vector2(0.0, 1.0), "RELATIVE_MOUSE reads strafe and throttle")

	entity.free()
	controller.free()

func _assert_vec(actual: Vector2, expected: Vector2, message: String) -> void:
	_assert(
		actual.is_equal_approx(expected),
		"%s (got %s, expected %s)" % [message, actual, expected]
	)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
