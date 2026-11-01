class_name ShapeUtils

## Returns a random point inside a CollisionShape2D or CollisionPolygon2D,
## in the local coordinates of that node. `margin` shrinks the usable area
## inward and is automatically reduced if it would exceed what the shape allows.
static func random_point_in(node: Node2D, margin: float = 0.0) -> Vector2:
	margin = maxf(margin, 0.0)

	if node is CollisionPolygon2D:
		return _random_in_polygon(node.polygon, margin)

	if node is CollisionShape2D:
		var shape: Shape2D = node.shape
		if shape == null:
			push_warning("CollisionShape2D has no shape.")
			return Vector2.ZERO

		if shape is RectangleShape2D:
			var half: Vector2 = shape.size * 0.5
			var m := clampf(margin, 0.0, minf(half.x, half.y))
			var inner := half - Vector2(m, m)
			return Vector2(
				randf_range(-inner.x, inner.x),
				randf_range(-inner.y, inner.y))

		if shape is CircleShape2D:
			var r := maxf(shape.radius - margin, 0.0)
			# sqrt keeps the distribution uniform over the area
			return Vector2.from_angle(randf() * TAU) * (r * sqrt(randf()))

		if shape is CapsuleShape2D:
			return _random_in_capsule(shape, margin)

		if shape is ConvexPolygonShape2D:
			return _random_in_polygon(shape.points, margin)

	push_warning("Unsupported node or shape type for random_point_in().")
	return Vector2.ZERO


static func _random_in_capsule(shape: CapsuleShape2D, margin: float) -> Vector2:
	var seg_half := maxf(shape.height * 0.5 - shape.radius, 0.0)
	var r := maxf(shape.radius - margin, 0.0)
	if r <= 0.0:
		return Vector2(0.0, randf_range(-seg_half, seg_half))

	# Rejection sampling inside the bounding box (accepts roughly 80%+ of tries)
	var a := Vector2(0.0, -seg_half)
	var b := Vector2(0.0, seg_half)
	for i in 100:
		var p := Vector2(
			randf_range(-r, r),
			randf_range(-seg_half - r, seg_half + r))
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= r:
			return p
	return Vector2.ZERO


static func _random_in_polygon(points: PackedVector2Array, margin: float) -> Vector2:
	var polys := _inset_polygons(points, margin)

	# Triangulate (works for concave polygons) and pick a triangle weighted by area
	var tris: Array[PackedVector2Array] = []
	var areas: Array[float] = []
	var total := 0.0
	for poly: PackedVector2Array in polys:
		var idx := Geometry2D.triangulate_polygon(poly)
		for i in range(0, idx.size(), 3):
			var a := poly[idx[i]]
			var b := poly[idx[i + 1]]
			var c := poly[idx[i + 2]]
			var area := absf((b - a).cross(c - a)) * 0.5
			tris.append(PackedVector2Array([a, b, c]))
			areas.append(area)
			total += area

	if total <= 0.0:
		push_warning("Degenerate polygon.")
		return points[0] if points.size() > 0 else Vector2.ZERO

	var pick := randf() * total
	var chosen := tris.size() - 1
	for i in tris.size():
		pick -= areas[i]
		if pick <= 0.0:
			chosen = i
			break

	# Uniform random point inside the chosen triangle
	var t := tris[chosen]
	var r1 := sqrt(randf())
	var r2 := randf()
	return t[0] * (1.0 - r1) + t[1] * (r1 * (1.0 - r2)) + t[2] * (r1 * r2)


## Shrinks the polygon by `margin`. If that would erase it entirely,
## finds the largest margin that still leaves some area (binary search).
static func _inset_polygons(points: PackedVector2Array, margin: float) -> Array:
	if margin <= 0.0:
		return [points]
	var result := Geometry2D.offset_polygon(points, -margin)
	if not result.is_empty():
		return result

	var lo := 0.0
	var hi := margin
	var best: Array = [points]
	for i in 12:
		var mid := (lo + hi) * 0.5
		var r := Geometry2D.offset_polygon(points, -mid)
		if r.is_empty():
			hi = mid
		else:
			lo = mid
			best = r
	return best
