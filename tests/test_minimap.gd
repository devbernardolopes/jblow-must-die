extends SceneTree
## Headless checks for minimap layout, projection, discovery and the fog seam.
## No gameplay scene is started.

var _failures: int = 0


class FakeSource extends Node2D:
	var shapes: Array[MinimapGeometry] = []

	func get_minimap_geometry() -> Array[MinimapGeometry]:
		return shapes


class FakeVisibility extends MinimapVisibility:
	var explored: bool = true
	var visible_now: bool = true

	func is_explored(_world_position: Vector2) -> bool:
		return explored

	func is_visible_now(_world_position: Vector2) -> bool:
		return visible_now


class FakeEntity extends Node2D:
	var facing: Vector2 = Vector2.RIGHT

	func _ready() -> void:
		add_to_group(&"entities")


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_layout()
	_test_viewport_fit()
	_test_projection()
	_test_discovery()
	_test_entities()
	_test_visibility()
	_test_wall_geometry()
	_test_source_geometry()
	_test_clip_polygons()
	_test_geometry_clipping()
	_test_rectangle_clip_polygon()
	await _test_late_source_registration()
	if _failures == 0:
		print("Minimap tests: PASS")
		quit(0)
	else:
		printerr("Minimap tests: %d failure(s)" % _failures)
		quit(1)


func _test_layout() -> void:
	var map_size := Vector2(200.0, 200.0)
	var margin := Vector2(20.0, 20.0)
	var parent_size := Vector2(1920.0, 1080.0)
	_assert_rect(
		Minimap.compute_screen_rect(Minimap.MapCorner.TOP_LEFT, map_size, margin, parent_size),
		Rect2(20.0, 20.0, 200.0, 200.0),
		"top left corner"
	)
	_assert_rect(
		Minimap.compute_screen_rect(Minimap.MapCorner.TOP_RIGHT, map_size, margin, parent_size),
		Rect2(1700.0, 20.0, 200.0, 200.0),
		"top right corner"
	)
	_assert_rect(
		Minimap.compute_screen_rect(Minimap.MapCorner.BOTTOM_LEFT, map_size, margin, parent_size),
		Rect2(20.0, 860.0, 200.0, 200.0),
		"bottom left corner"
	)
	_assert_rect(
		Minimap.compute_screen_rect(Minimap.MapCorner.BOTTOM_RIGHT, map_size, margin, parent_size),
		Rect2(1700.0, 860.0, 200.0, 200.0),
		"bottom right corner"
	)
	_assert_vec(
		Minimap.fit_map_size(Vector2(220.0, 220.0), Vector2(1920.0, 1080.0), 0.3),
		Vector2(220.0, 220.0),
		"desktop keeps the requested size"
	)
	_assert_vec(
		Minimap.fit_map_size(Vector2(220.0, 220.0), Vector2(640.0, 360.0), 0.3),
		Vector2(108.0, 108.0),
		"phone shrinks the map uniformly"
	)


func _test_viewport_fit() -> void:
	var minimap := _make_minimap()
	minimap.map_size = Vector2(400.0, 400.0)
	minimap.max_viewport_fraction = 0.3
	var viewport_size: Vector2 = root.get_visible_rect().size
	var expected: Vector2 = Minimap.fit_map_size(minimap.map_size, viewport_size, 0.3)
	minimap._apply_layout()
	_assert_vec(minimap.size, expected, "layout respects the viewport cap")
	minimap.free()


func _test_projection() -> void:
	var center := Vector2(100.0, 100.0)
	var player := Vector2(500.0, 500.0)
	var map_scale := 0.5
	_assert_vec(
		Minimap.world_to_map(player, player, map_scale, 0.0, center),
		center,
		"player is centred"
	)
	_assert_vec(
		Minimap.world_to_map(player + Vector2(0.0, -100.0), player, map_scale, 0.0, center),
		center + Vector2(0.0, -50.0),
		"north maps up"
	)

	var transform := Minimap.map_transform(player, map_scale, 0.0, center)
	_assert_vec(transform * player, center, "transform centres the player")
	_assert_vec(
		transform * (player + Vector2(100.0, 0.0)),
		center + Vector2(50.0, 0.0),
		"transform scales world points"
	)

	# Rotate with player: facing right must end up pointing up on screen.
	var rotated := Minimap.map_transform(player, map_scale, -PI * 0.5, center)
	_assert_vec(
		rotated * (player + Vector2.RIGHT),
		center + Vector2(0.0, -map_scale),
		"facing maps up when the map rotates"
	)


func _test_discovery() -> void:
	var minimap := _make_minimap()
	var source := FakeSource.new()
	var shapes: Array[MinimapGeometry] = [
		_make_geometry(MinimapGeometry.Kind.WALL, [Vector2(0.0, 0.0), Vector2(100.0, 0.0)])
	]
	source.shapes = shapes
	source.add_to_group(&"minimap_source")
	root.add_child(source)

	minimap.rebuild_geometry()
	_assert(minimap.get_geometry().size() == 1, "source geometry is collected")
	_assert(
		minimap.get_geometry()[0].kind == MinimapGeometry.Kind.WALL,
		"geometry kind survives discovery"
	)

	source.free()
	minimap.free()


func _test_entities() -> void:
	var minimap := _make_minimap()
	minimap.world_radius_m = 10.0
	minimap.show_other_entities = true

	var player := FakeEntity.new()
	player.facing = Vector2.RIGHT
	root.add_child(player)
	player.global_position = Vector2.ZERO

	var other := FakeEntity.new()
	root.add_child(other)
	other.global_position = Vector2(100.0, 0.0)

	var markers := minimap.collect_entity_markers(player)
	_assert(markers.size() == 1, "other entity is drawn")
	if markers.size() == 1:
		_assert_vec(
			markers[0],
			Vector2(100.0, 100.0) + Vector2(100.0, 0.0) * 0.625,
			"entity marker is projected"
		)

	minimap.show_other_entities = false
	_assert(minimap.collect_entity_markers(player).is_empty(), "toggle hides other entities")

	minimap.show_other_entities = true
	other.global_position = Vector2(1000.0, 0.0)
	_assert(minimap.collect_entity_markers(player).is_empty(), "off-map entities are culled")

	other.free()
	player.free()
	minimap.free()


func _test_visibility() -> void:
	var minimap := _make_minimap()
	var fog := FakeVisibility.new()
	minimap.visibility = fog

	var geometry := _make_geometry(
		MinimapGeometry.Kind.WALL, [Vector2(0.0, 0.0), Vector2(100.0, 0.0)]
	)
	fog.explored = false
	_assert(not minimap._is_geometry_revealed(geometry), "unexplored geometry is hidden")
	fog.explored = true
	_assert(minimap._is_geometry_revealed(geometry), "explored geometry is shown")

	var player := FakeEntity.new()
	root.add_child(player)
	var other := FakeEntity.new()
	root.add_child(other)
	minimap.show_other_entities = true
	fog.visible_now = false
	_assert(minimap.collect_entity_markers(player).is_empty(), "invisible entities are hidden")
	fog.visible_now = true
	_assert(minimap.collect_entity_markers(player).size() == 1, "visible entities are shown")

	other.free()
	player.free()
	minimap.free()


func _test_wall_geometry() -> void:
	var wall := Wall.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(100.0, 0.0))
	wall.curve = curve
	wall.width = 2.5
	wall.position = Vector2(50.0, 25.0)
	root.add_child(wall)

	_assert(wall.is_in_group(&"minimap_source"), "walls register as minimap sources")
	var shapes := wall.get_minimap_geometry()
	_assert(shapes.size() == 1, "wall returns one shape")
	if shapes.size() == 1:
		_assert(shapes[0].kind == MinimapGeometry.Kind.WALL, "wall kind")
		_assert(shapes[0].points.size() >= 2, "wall has points")
		_assert_vec(shapes[0].points[0], Vector2(50.0, 25.0), "wall points are global")

	wall.free()


func _test_source_geometry() -> void:
	var source := MinimapSource.new()
	source.points = PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0)])
	source.kind = MinimapGeometry.Kind.DOOR
	source.position = Vector2(100.0, 50.0)
	root.add_child(source)

	_assert(source.is_in_group(&"minimap_source"), "sources register")
	var shapes := source.get_minimap_geometry()
	_assert(shapes.size() == 1, "source returns one shape")
	if shapes.size() == 1:
		_assert_vec(shapes[0].points[0], Vector2(100.0, 50.0), "source points are global")
		_assert_vec(shapes[0].points[1], Vector2(110.0, 50.0), "source follows its transform")

	source.minimap_visible = false
	_assert(source.get_minimap_geometry().is_empty(), "hidden sources return nothing")

	source.free()


func _test_late_source_registration() -> void:
	var minimap := _make_minimap()
	await process_frame
	_assert(minimap.get_geometry().is_empty(), "empty minimap starts without geometry")

	var wall := Wall.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(100.0, 0.0))
	wall.curve = curve
	root.add_child(wall)
	await process_frame
	_assert(minimap.get_geometry().size() == 1, "late wall refreshes minimap geometry")

	wall.free()
	minimap.free()


func _test_clip_polygons() -> void:
	var center := Vector2(100.0, 100.0)
	var radius := 90.0
	var circle: PackedVector2Array = Minimap.circle_polygon(center, radius, 64)
	_assert(circle.size() == 64, "circle clip has the requested segment count")
	var on_radius: bool = true
	for point: Vector2 in circle:
		if absf(point.distance_to(center) - radius) > 0.01:
			on_radius = false
			break
	_assert(on_radius, "circle clip points sit on the radius")
	_assert(Geometry2D.is_point_in_polygon(center, circle), "circle clip contains its centre")
	_assert(
		not Geometry2D.is_point_in_polygon(center + Vector2(radius + 5.0, 0.0), circle),
		"circle clip rejects points outside"
	)
	_assert(Minimap.circle_polygon(center, 0.0).is_empty(), "zero-radius circle clip is empty")

	var rounded: PackedVector2Array = Minimap.rounded_rect_polygon(Vector2(200.0, 200.0), 40.0, 8)
	_assert(rounded.size() > 4, "rounded rectangle clip is a polygon")
	_assert(
		Geometry2D.is_point_in_polygon(Vector2(100.0, 100.0), rounded),
		"rounded rectangle contains its centre"
	)
	_assert(
		not Geometry2D.is_point_in_polygon(Vector2(1.0, 1.0), rounded),
		"rounded rectangle cuts its corners"
	)
	_assert(
		Geometry2D.is_point_in_polygon(Vector2(100.0, 5.0), rounded),
		"rounded rectangle keeps its edges"
	)
	var square: PackedVector2Array = Minimap.rounded_rect_polygon(Vector2(200.0, 200.0), 0.0)
	_assert(square.size() == 4, "zero radius rectangle clip stays a quad")
	_assert(
		Geometry2D.is_point_in_polygon(Vector2(1.0, 1.0), square),
		"zero radius rectangle keeps its corners"
	)


func _test_geometry_clipping() -> void:
	var minimap := _make_minimap()
	minimap.shape = Minimap.Shape.CIRCLE
	minimap.line_width_px = 2.0
	var box: Vector2 = minimap._map_box()
	var center: Vector2 = box * 0.5
	var radius: float = minf(box.x, box.y) * 0.5
	var clip: PackedVector2Array = minimap._clip_polygon(0.0)
	var stroke_clip: PackedVector2Array = minimap._clip_polygon(minimap.line_width_px * 0.5)
	_assert(not clip.is_empty(), "circle shape builds a clip polygon")
	_assert(not stroke_clip.is_empty(), "circle shape builds an inset stroke clip")

	var inside := PackedVector2Array([
		center - Vector2(20.0, 0.0), center + Vector2(20.0, 0.0)
	])
	var inside_parts: Array[PackedVector2Array] = Geometry2D.intersect_polyline_with_polygon(
		inside, stroke_clip
	)
	_assert(
		is_equal_approx(_polyline_length(inside_parts), 40.0),
		"inside segment survives clipping"
	)

	var crossing := PackedVector2Array([
		center - Vector2(200.0, 0.0), center + Vector2(200.0, 0.0)
	])
	var crossing_parts: Array[PackedVector2Array] = Geometry2D.intersect_polyline_with_polygon(
		crossing, stroke_clip
	)
	_assert(not crossing_parts.is_empty(), "crossing segment is clipped, not dropped")
	var crossing_inside: bool = true
	for part: PackedVector2Array in crossing_parts:
		for point: Vector2 in part:
			if point.distance_to(center) > radius + 0.01:
				crossing_inside = false
	_assert(crossing_inside, "clipped segment stays inside the circle")
	_assert(
		_polyline_length(crossing_parts) < 400.0,
		"crossing segment is shortened"
	)

	var outside := PackedVector2Array([
		center + Vector2(200.0, 0.0), center + Vector2(220.0, 0.0)
	])
	_assert(
		Geometry2D.intersect_polyline_with_polygon(outside, stroke_clip).is_empty(),
		"outside segment is culled"
	)

	var full := PackedVector2Array([
		center - Vector2(300.0, 300.0),
		center + Vector2(300.0, -300.0),
		center + Vector2(300.0, 300.0),
	])
	var filled_parts: Array[PackedVector2Array] = Geometry2D.intersect_polygons(full, clip)
	_assert(not filled_parts.is_empty(), "filled area is clipped")
	var fill_inside: bool = true
	for part: PackedVector2Array in filled_parts:
		for point: Vector2 in part:
			if point.distance_to(center) > radius + 0.01:
				fill_inside = false
	_assert(fill_inside, "clipped fill stays inside the circle")

	_assert(
		Minimap._is_inside_clip(
			PackedVector2Array([center - Vector2(5.0, 5.0), center + Vector2(5.0, 5.0)]), clip
		),
		"small geometry uses the inside fast path"
	)
	_assert(
		not Minimap._is_inside_clip(crossing, clip),
		"crossing geometry skips the inside fast path"
	)
	minimap.free()


func _test_rectangle_clip_polygon() -> void:
	var minimap := _make_minimap()
	minimap.shape = Minimap.Shape.RECTANGLE
	minimap.corner_radius = 0.0
	_assert(minimap._clip_polygon(0.0).is_empty(), "square shape relies on clip_contents")
	minimap.corner_radius = 24.0
	var clip: PackedVector2Array = minimap._clip_polygon(0.0)
	_assert(not clip.is_empty(), "rounded rectangle builds a clip polygon")
	_assert(
		Minimap._is_inside_clip(
			PackedVector2Array([Vector2(90.0, 90.0), Vector2(110.0, 110.0)]), clip
		),
		"rounded rectangle keeps geometry near its centre"
	)
	var inset: PackedVector2Array = minimap._clip_polygon(4.0)
	_assert(not inset.is_empty(), "rounded rectangle builds an inset stroke clip")
	_assert(
		not Minimap._is_inside_clip(
			PackedVector2Array([Vector2(-10.0, 100.0), Vector2(210.0, 100.0)]), clip
		),
		"rounded rectangle clips geometry crossing its border"
	)
	minimap.free()


func _polyline_length(parts: Array[PackedVector2Array]) -> float:
	var total: float = 0.0
	for part: PackedVector2Array in parts:
		for index: int in range(1, part.size()):
			total += part[index - 1].distance_to(part[index])
	return total


func _make_minimap() -> Minimap:
	var minimap := Minimap.new()
	minimap.map_size = Vector2(200.0, 200.0)
	root.add_child(minimap)
	return minimap


func _make_geometry(kind: MinimapGeometry.Kind, points: Array[Vector2]) -> MinimapGeometry:
	var geometry := MinimapGeometry.new()
	geometry.kind = kind
	geometry.points = PackedVector2Array(points)
	return geometry


func _assert_rect(actual: Rect2, expected: Rect2, message: String) -> void:
	_assert(
		actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size),
		"%s (got %s, expected %s)" % [message, actual, expected]
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
