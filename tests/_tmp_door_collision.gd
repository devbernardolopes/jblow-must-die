extends SceneTree
## Temporary probe: does the leaf collision follow the moving panel?


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var door := Door.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(100.0, 0.0))
	door.curve = curve
	var data := DoorData.new()
	data.kind = DoorData.Kind.SINGLE
	data.motion = DoorData.Motion.SLIDE
	door.data = data
	door.width = 32.0
	door.open_speed = 1000.0
	root.add_child(door)
	await process_frame
	await physics_frame
	await physics_frame
	await process_frame
	await physics_frame

	var leaf_body: AnimatableBody2D = door.leaves[0].body
	print("closed edge (50,16): ", _shape_hit(Vector2(50.0, 16.0)))
	print("closed far edge (95,16): ", _shape_hit(Vector2(95.0, 16.0)))

	leaf_body.sync_to_physics = false
	door.open()
	for _index: int in range(200):
		if door.state == Door.DoorState.OPENED:
			break
		await physics_frame
	await process_frame
	await physics_frame
	await physics_frame

	print("leaf transform: ", door.leaves[0].transform)
	print("leaf body global: ", leaf_body.global_position)
	print("server xform: ", PhysicsServer2D.body_get_state(leaf_body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM))
	print("after open old edge (50,16): ", _shape_hit(Vector2(50.0, 16.0)))
	print("after open new edge (150,16): ", _shape_hit(Vector2(150.0, 16.0)))
	quit(0)


func _shape_hit(point: Vector2) -> int:
	var space := root.world_2d.direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 2.0
	params.shape = circle
	params.transform = Transform2D(0.0, point)
	params.collision_mask = 0xFFFFFFFF
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return space.intersect_shape(params).size()
