extends SceneTree
## Headless checks for Door state, panel transforms and the fixed interaction
## anchor. No gameplay scene is started.

const LENGTH: float = 100.0
const WIDTH: float = 32.0
const SPEED: float = 1000.0
const MAX_FRAMES: int = 600

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _test_single_slide()
	await _test_single_slide_reversed()
	await _test_double_slide()
	await _test_single_swing_hinge_start()
	await _test_single_swing_hinge_end()
	await _test_double_swing()
	await _test_interactable_stays_fixed()
	await _test_door_switch()
	await _test_starts_open()
	await _test_reversal()
	await _test_rebuild_keeps_pose()
	await _test_minimap()
	_test_authored_resource()
	if _failures == 0:
		print("Door tests: PASS")
		quit(0)
	else:
		printerr("Door tests: %d failure(s)" % _failures)
		quit(1)


# --- Tests ----------------------------------------------------------------

func _test_single_slide() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SLIDE)
	_assert(door.leaves.size() == 1, "single door builds one panel")
	_assert(door.state == Door.DoorState.CLOSED, "door starts closed")
	_assert(door.progress == 0.0, "door starts at progress 0")
	var leaf: DoorLeaf = door.leaves[0]
	_assert(leaf.body != null and leaf.body.get_child_count() > 0, "panel owns collision")

	door.open()
	_assert(door.state == Door.DoorState.OPENING, "open() starts opening")
	await _run_until_opened(door)
	_assert(door.state == Door.DoorState.OPENED, "door reaches OPENED")
	_assert(is_equal_approx(door.progress, 1.0), "open door is at progress 1")
	_assert_vec(leaf.transform.origin, Vector2(LENGTH, 0.0), "panel slides past its far end")
	_assert_angle(leaf.transform.get_rotation(), 0.0, "sliding panel does not rotate")

	door.close()
	await _run_until_closed(door)
	_assert(door.state == Door.DoorState.CLOSED, "door closes again")
	_assert_vec(leaf.transform.origin, Vector2.ZERO, "panel returns to the closed pose")
	_free_door(door)


func _test_single_slide_reversed() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SLIDE)
	door.slide_reversed = true
	var leaf: DoorLeaf = door.leaves[0]
	door.open()
	await _run_until_opened(door)
	_assert_vec(
		leaf.transform.origin, Vector2(-LENGTH, 0.0), "reversed panel slides the other way"
	)
	_free_door(door)


func _test_double_slide() -> void:
	var door: Door = _make_door(DoorData.Kind.DOUBLE, DoorData.Motion.SLIDE)
	_assert(door.leaves.size() == 2, "double door builds two panels")
	var first: DoorLeaf = door.leaves[0]
	var second: DoorLeaf = door.leaves[1]
	door.open()
	await _run_until_opened(door)
	_assert_vec(first.transform.origin, Vector2(-LENGTH * 0.5, 0.0), "first half retracts left")
	_assert_vec(
		second.transform.origin, Vector2(LENGTH * 1.5, 0.0), "second half retracts right"
	)
	_free_door(door)


func _test_single_swing_hinge_start() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SWING)
	var leaf: DoorLeaf = door.leaves[0]
	door.open()
	await _run_until_opened(door)
	_assert_vec(leaf.transform.origin, Vector2.ZERO, "hinged panel keeps its pivot")
	_assert_angle(leaf.transform.get_rotation(), PI * 0.5, "panel swings 90 degrees")
	_free_door(door)


func _test_single_swing_hinge_end() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SWING)
	door.hinge_at_end = true
	var leaf: DoorLeaf = door.leaves[0]
	door.open()
	await _run_until_opened(door)
	_assert_vec(
		leaf.transform.origin, Vector2(LENGTH, 0.0), "hinge moved to the far end of the curve"
	)
	_assert_angle(
		leaf.transform.get_rotation(), -PI * 0.5, "far hinge rotates the other way to sweep the same side"
	)
	_free_door(door)


func _test_double_swing() -> void:
	var door: Door = _make_door(DoorData.Kind.DOUBLE, DoorData.Motion.SWING)
	var first: DoorLeaf = door.leaves[0]
	var second: DoorLeaf = door.leaves[1]
	door.open()
	await _run_until_opened(door)
	_assert_vec(first.transform.origin, Vector2.ZERO, "first leaf hinges on the start")
	_assert_vec(second.transform.origin, Vector2(LENGTH, 0.0), "second leaf hinges on the end")
	_assert_angle(first.transform.get_rotation(), PI * 0.5, "first leaf swings one way")
	_assert_angle(second.transform.get_rotation(), -PI * 0.5, "second leaf swings the other way")
	_free_door(door)


func _test_interactable_stays_fixed() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SWING)
	_assert(door.interactable != null, "door creates an interaction area")
	if door.interactable == null:
		_free_door(door)
		return
	_assert_vec(door.interactable.position, Vector2(LENGTH * 0.5, 0.0), "anchor sits on the midpoint")
	_assert(
		is_equal_approx(door.interactable.radius_m, door.interaction_radius_m),
		"interaction radius uses meters"
	)
	_assert(door.interactable.prompt_text == "Open", "closed prompt asks to open")

	_assert(door.interactable.interact(null), "interaction is accepted while closed")
	_assert(door.state == Door.DoorState.OPENING, "interaction toggles the door")
	await _run_until_opened(door)
	_assert_vec(
		door.interactable.position,
		Vector2(LENGTH * 0.5, 0.0),
		"anchor does not follow the moving panel"
	)
	_assert(door.interactable.prompt_text == "Close", "open prompt asks to close")

	door.interactable.interact(null)
	await _run_until_closed(door)
	_assert_vec(
		door.interactable.position, Vector2(LENGTH * 0.5, 0.0), "anchor stays fixed after closing"
	)
	_assert(door.interactable.prompt_text == "Open", "prompt resets when closed")
	_free_door(door)


func _test_door_switch() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SLIDE)
	var switch := DoorSwitch.new()
	switch.door = door
	root.add_child(switch)
	_assert(switch.prompt_text == "Open", "switch borrows the closed prompt")
	_assert(switch.interact(null), "switch accepts interaction")
	_assert(door.state == Door.DoorState.OPENING, "switch drives the door")
	await _run_until_opened(door)
	_assert(switch.prompt_text == "Close", "switch borrows the open prompt")
	switch.free()
	_free_door(door)


func _test_starts_open() -> void:
	var opened_door: Door = Door.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(LENGTH, 0.0))
	opened_door.curve = curve
	opened_door.data = DoorData.new()
	opened_door.starts_open = true
	opened_door.open_speed = SPEED
	root.add_child(opened_door)
	_assert(opened_door.state == Door.DoorState.OPENED, "starts_open reports OPENED")
	_assert(is_equal_approx(opened_door.progress, 1.0), "starts_open starts at progress 1")
	_assert_vec(
		opened_door.leaves[0].transform.origin, Vector2(LENGTH, 0.0), "starts_open applies the pose"
	)
	_free_door(opened_door)


func _test_reversal() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SLIDE)
	door.open()
	await _run_frames(3)
	var before: float = door.progress
	_assert(before > 0.0 and before < 1.0, "door is mid-travel before reversing")
	door.close()
	await _run_frames(2)
	var after: float = door.progress
	_assert(after < before, "closing reduces progress from the current pose")
	door.open()
	await _run_frames(2)
	_assert(door.progress > after, "opening resumes from the current pose without jumping")
	_assert(door.state == Door.DoorState.OPENING, "reversal reports OPENING")
	_free_door(door)


func _test_rebuild_keeps_pose() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SLIDE)
	door.open()
	await _run_until_opened(door)
	var leaf: DoorLeaf = door.leaves[0]
	var curve: Curve2D = door.curve
	curve.set_point_position(0, Vector2(0.0, 50.0))
	curve.set_point_position(1, Vector2(LENGTH, 50.0))
	door.rebuild()
	_assert(is_equal_approx(door.progress, 1.0), "rebuild keeps the progress")
	_assert_vec(
		leaf.transform.origin,
		Vector2(LENGTH, 50.0),
		"rebuild reapplies the open pose to the moved curve"
	)
	_free_door(door)


func _test_minimap() -> void:
	var door: Door = _make_door(DoorData.Kind.SINGLE, DoorData.Motion.SLIDE)
	var geometry: Array[MinimapGeometry] = door.get_minimap_geometry()
	_assert(geometry.size() == 1, "door publishes one minimap shape")
	if geometry.size() == 1:
		var shape: MinimapGeometry = geometry[0]
		_assert(shape.kind == MinimapGeometry.Kind.DOOR, "door uses the DOOR kind")
		_assert(shape.points.size() >= 2, "door shape has points")
		_assert_vec(shape.points[0], Vector2.ZERO, "shape starts at the authored start")
		_assert_vec(
			shape.points[shape.points.size() - 1],
			Vector2(LENGTH, 0.0),
			"shape ends at the authored end"
		)
	_free_door(door)


func _test_authored_resource() -> void:
	var data := load("res://resources/doors/regular_door.tres") as DoorData
	_assert(data != null, "regular door resource loads as DoorData")
	if data == null:
		return
	_assert(data.kind == DoorData.Kind.SINGLE, "regular door is single")
	_assert(data.motion == DoorData.Motion.SLIDE, "regular door slides")
	_assert(not data.prompt.is_empty(), "regular door has an open prompt")
	_assert(not data.close_prompt.is_empty(), "regular door has a close prompt")


# --- Helpers --------------------------------------------------------------

func _make_door(kind: DoorData.Kind, motion: DoorData.Motion) -> Door:
	var door := Door.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(LENGTH, 0.0))
	door.curve = curve
	var data := DoorData.new()
	data.kind = kind
	data.motion = motion
	door.data = data
	door.width = WIDTH
	door.open_speed = SPEED
	root.add_child(door)
	return door


func _run_until_opened(door: Door) -> void:
	for _index: int in range(MAX_FRAMES):
		if door.state == Door.DoorState.OPENED:
			return
		await physics_frame
	_assert(false, "door did not finish opening")


func _run_until_closed(door: Door) -> void:
	for _index: int in range(MAX_FRAMES):
		if door.state == Door.DoorState.CLOSED:
			return
		await physics_frame
	_assert(false, "door did not finish closing")


func _run_frames(count: int) -> void:
	for _index: int in range(count):
		await physics_frame


func _free_door(door: Door) -> void:
	if is_instance_valid(door):
		door.free()


func _assert_angle(actual: float, expected: float, message: String) -> void:
	_assert(
		absf(angle_difference(actual, expected)) < 0.001,
		"%s (got %.4f, expected %.4f)" % [message, actual, expected]
	)


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
