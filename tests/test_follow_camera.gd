extends SceneTree
## Headless checks for the follow camera: aim lead, exact settling, sprint
## hysteresis and trauma shake. No gameplay scene is started.

const STEP: float = 1.0 / 60.0

var _failures: int = 0


class RunController extends EntityController:
	var running: bool = false

	func wants_run() -> bool:
		return running


class Rig:
	var entity: Entity
	var controller: RunController
	var camera: FollowCamera


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _test_lead_uses_facing_when_stopped()
	await _test_backpedal_keeps_aim_lead()
	await _test_settles_exactly()
	await _test_no_speed_zoom_by_default()
	await _test_sprint_zoom_hysteresis()
	await _test_damage_shake()
	if _failures == 0:
		print("Follow camera tests: PASS")
		quit(0)
	else:
		printerr("Follow camera tests: %d failure(s)" % _failures)
		quit(1)


# --- Tests ----------------------------------------------------------------

func _test_lead_uses_facing_when_stopped() -> void:
	var rig: Rig = await _make_rig()
	rig.entity.global_position = Vector2(1000.0, 1000.0)
	rig.entity.velocity = Vector2.ZERO
	rig.entity.facing = Vector2.RIGHT
	rig.camera.snap_to_target()
	_settle(rig.camera, 2.0)

	var offset_m: Vector2 = Units.to_m(rig.camera.global_position - rig.entity.global_position)
	var px_per_m: float = rig.camera.base_zoom * Units.PX_PER_METER
	var expected_m: float = rig.camera.aim_lead_px / px_per_m
	_assert(offset_m.x > 0.0, "a stopped target still leads toward its facing")
	_assert_close(offset_m.x, expected_m, "the stopped lead matches the aim lead")
	_assert_close(offset_m.y, 0.0, "the stopped lead has no sideways component")
	_free_rig(rig)


func _test_backpedal_keeps_aim_lead() -> void:
	var rig: Rig = await _make_rig()
	rig.entity.global_position = Vector2(1000.0, 1000.0)
	rig.entity.facing = Vector2.RIGHT
	rig.entity.velocity = Units.to_px(Vector2(-40.0, 0.0))
	rig.camera.snap_to_target()
	_settle(rig.camera, 2.0)

	var offset_m: Vector2 = Units.to_m(rig.camera.global_position - rig.entity.global_position)
	var px_per_m: float = rig.camera.base_zoom * Units.PX_PER_METER
	var expected_px: float = rig.camera.aim_lead_px - rig.camera.move_lead_px
	var expected_m: float = expected_px / px_per_m
	_assert(offset_m.x > 0.0, "backpedalling keeps the lead on the aim side")
	_assert_close(offset_m.x, expected_m, "backpedal lead subtracts the travel lead")
	_free_rig(rig)


func _test_settles_exactly() -> void:
	var rig: Rig = await _make_rig()
	rig.entity.facing = Vector2.RIGHT
	rig.camera.snap_to_target()
	_settle(rig.camera, 3.0)

	var settled_position: Vector2 = rig.camera.global_position
	var settled_zoom: Vector2 = rig.camera.zoom
	rig.camera._update_follow(STEP)
	_assert(
		rig.camera.global_position.is_equal_approx(settled_position),
		"the camera stops micro-panning at rest"
	)
	_assert(
		rig.camera.zoom.is_equal_approx(settled_zoom),
		"the camera stops micro-scaling at rest"
	)
	_assert_close(rig.camera.zoom.x, rig.camera.base_zoom, "auto zoom settles on the base zoom")
	_free_rig(rig)


func _test_no_speed_zoom_by_default() -> void:
	var rig: Rig = await _make_rig()
	rig.controller = RunController.new()
	rig.controller.running = true
	rig.entity.set_controller(rig.controller)
	rig.entity.velocity = Units.to_px(Vector2(40.0, 0.0))
	_settle(rig.camera, 3.0)
	_assert_close(
		rig.camera.zoom.x,
		rig.camera.base_zoom,
		"walking and running do not change zoom by default"
	)
	_free_rig(rig)


func _test_sprint_zoom_hysteresis() -> void:
	var rig: Rig = await _make_rig()
	rig.camera.sprint_zoom_enabled = true
	rig.controller = RunController.new()
	rig.controller.running = true
	rig.entity.set_controller(rig.controller)
	rig.entity.velocity = Units.to_px(Vector2(10.0, 0.0))

	_settle(rig.camera, 0.4)
	_assert_close(
		rig.camera.zoom.x,
		rig.camera.base_zoom,
		"sprint zoom needs a sustained run"
	)

	_settle(rig.camera, 3.0)
	_assert_close(
		rig.camera.zoom.x,
		rig.camera.sprint_zoom,
		"a sustained run widens the view"
	)

	rig.controller.running = false
	rig.entity.velocity = Vector2.ZERO
	_settle(rig.camera, 0.6)
	_assert_close(
		rig.camera.zoom.x,
		rig.camera.sprint_zoom,
		"the sprint zoom holds through the release delay"
	)

	_settle(rig.camera, 3.0)
	_assert_close(
		rig.camera.zoom.x,
		rig.camera.base_zoom,
		"zoom returns to base after the release delay"
	)
	_free_rig(rig)


func _test_damage_shake() -> void:
	var rig: Rig = await _make_rig()
	rig.camera.shake_enabled = true
	rig.entity.damaged.emit(10.0, null)
	_assert(rig.camera._trauma > 0.0, "damage starts a shake")
	_settle(rig.camera, 2.0)
	_assert_close(rig.camera._trauma, 0.0, "shake trauma decays")
	_assert(
		rig.camera._shake_offset_px.is_zero_approx(),
		"the shake offset clears when trauma reaches zero"
	)
	_free_rig(rig)


# --- Helpers --------------------------------------------------------------

func _make_rig() -> Rig:
	var rig := Rig.new()
	rig.entity = Entity.new()
	var data := EntityData.new()
	data.walk_speed_mps = 10.0
	data.run_speed_mps = 40.0
	rig.entity.data = data
	rig.entity.speed_multiplier = 1.0
	rig.entity.facing = Vector2.RIGHT
	rig.entity.set_physics_process(false)
	root.add_child(rig.entity)
	await process_frame

	rig.camera = FollowCamera.new()
	rig.camera.target = rig.entity
	rig.camera.shake_enabled = false
	rig.camera.set_physics_process(false)
	root.add_child(rig.camera)
	await process_frame
	rig.camera.snap_to_target()
	return rig


func _settle(camera: FollowCamera, seconds: float) -> void:
	var steps: int = ceili(seconds / STEP)
	for _index: int in range(steps):
		camera._update_follow(STEP)


func _free_rig(rig: Rig) -> void:
	rig.camera.free()
	rig.entity.free()


func _assert_close(actual: float, expected: float, message: String) -> void:
	_assert(
		is_equal_approx(actual, expected),
		"%s (got %f, expected %f)" % [message, actual, expected]
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
