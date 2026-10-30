@tool
class_name Wall
extends Path2D

const VIEWER_GROUP := &"wall_viewer"

@export var disable_editor: bool = false:
	set(v):
		disable_editor = v
		_apply_style()
		_rebuild()

@export var bake_interval: float = 8.0:
	set(v):
		bake_interval = v
		_rebuild()

@export var texture: Texture2D:
	set(v):
		texture = v
		_apply_style()

@export var texture_mode: Line2D.LineTextureMode = Line2D.LineTextureMode.LINE_TEXTURE_TILE:
	set(v):
		texture_mode = v
		_apply_style()

@export var width: float = 128.0:
	set(v):
		width = v
		_apply_style()
		_rebuild()

@export var pixel_art: bool = false:
	set(v):
		pixel_art = v
		_apply_style()

@export var solid: bool = true:
	set(v):
		solid = v
		_rebuild_collision()

@export var casts_shadow: bool = true:
	set(v):
		casts_shadow = v
		_rebuild_occluders()

@export_flags_2d_render var occluder_light_mask: int = 1:
	set(v):
		occluder_light_mask = v
		_rebuild_occluders()

@export_group("Height illusion")

## Front view of the wall. Should tile horizontally.
@export var side_texture: Texture2D:
	set(v):
		side_texture = v
		_invalidate_height()

## How strongly the top shifts away from the viewer (fake wall height).
@export_range(0.0, 0.5, 0.005) var height_factor: float = 0.06:
	set(v):
		height_factor = v
		_invalidate_height()

## Editor-only: where the "eye" is when no viewer node exists in the edited scene.
@export var preview_viewer_position: Vector2 = Vector2.ZERO:
	set(v):
		preview_viewer_position = v
		_invalidate_height()

var line: Line2D
var body: StaticBody2D
var occluders: Node2D
var _connected_curve: Curve2D
var _rebuilding: bool = false

var _base_points := PackedVector2Array()
var _outline: Array = []  # polygons around the wall footprint
var _outer_sign: float = 1.0
var _viewer: Node2D
var _last_viewer := Vector2(NAN, NAN)  # local space; NAN = needs refresh, INF = no viewer

func _ready() -> void:
	if not Engine.is_editor_hint():
		disable_editor = false

	add_to_group(&"minimap_source")
	call_deferred(&"_notify_minimap_changed")
	line = Line2D.new()
	line.name = "Line"
	add_child(line, false, Node.INTERNAL_MODE_FRONT)

	body = StaticBody2D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.OBJECTS
	body.collision_mask = 0
	add_child(body, false, Node.INTERNAL_MODE_FRONT)

	occluders = Node2D.new()
	occluders.name = "Occluders"
	add_child(occluders, false, Node.INTERNAL_MODE_FRONT)
	
	_apply_style()
	_rebuild()

## Tell an already-running minimap about a wall instanced after it.
func _notify_minimap_changed() -> void:
	if not is_inside_tree():
		return
	get_tree().call_group(&"minimap", &"rebuild_geometry")

func _process(_delta: float) -> void:
	if not disable_editor:
		# Reconnect if the Curve resource was created/replaced in the Inspector
		if curve != _connected_curve:
			if _connected_curve and _connected_curve.changed.is_connected(_rebuild):
				_connected_curve.changed.disconnect(_rebuild)
			_connected_curve = curve
			if curve:
				curve.changed.connect(_rebuild)
			_rebuild()
		_apply_height()

func _apply_style() -> void:
	if line == null:
		return
	line.texture = texture
	line.texture_mode = texture_mode
	line.width = width
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	# Used by _draw() for the side faces
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_PARENT_NODE

func _rebuild() -> void:
	if _rebuilding or line == null or curve == null:
		return
	_rebuilding = true
	if not is_equal_approx(curve.bake_interval, bake_interval):
		curve.bake_interval = bake_interval
	_base_points = curve.get_baked_points()
	line.points = _base_points
	_build_outline()
	_rebuild_collision()
	if not Engine.is_editor_hint():
		_rebuild_occluders()
	_invalidate_height()
	_invalidate_height()
	_rebuilding = false

## Centerline in global pixels, used by the minimap. This is the authored
## geometry, not the height-shifted visual.
func get_minimap_geometry() -> Array[MinimapGeometry]:
	var result: Array[MinimapGeometry] = []
	if curve == null:
		return result
	var local_points: PackedVector2Array = curve.get_baked_points()
	if local_points.size() < 2:
		return result
	var global_points := PackedVector2Array()
	global_points.resize(local_points.size())
	for index: int in range(local_points.size()):
		global_points[index] = global_transform * local_points[index]
	var geometry := MinimapGeometry.new()
	geometry.kind = MinimapGeometry.Kind.WALL
	geometry.closed = local_points[0].distance_to(local_points[local_points.size() - 1]) < 0.01
	geometry.points = global_points
	result.append(geometry)
	return result

# --- Footprint outline (shared by collision and side faces) ---

func _build_outline() -> void:
	_outline = []
	var pts := _base_points
	if pts.size() < 2:
		return
	# First point == last point means a closed loop (a room)
	var closed := pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.01
	if closed:
		pts = pts.slice(0, pts.size() - 1)
	var end_type := Geometry2D.END_JOINED if closed else Geometry2D.END_BUTT
	_outline = Geometry2D.offset_polyline(pts, width * 0.5, Geometry2D.JOIN_MITER, end_type)

	# Outer polygons share one orientation, holes have the opposite one.
	# The biggest polygon is always an outer one, so it defines the convention.
	var best := 0.0
	for poly in _outline:
		var a := _signed_area(poly)
		if absf(a) > absf(best):
			best = a
	_outer_sign = signf(best) if best != 0.0 else 1.0

static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

# --- Collision ---

func _rebuild_collision() -> void:
	if body == null:
		return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	if not solid:
		return
	for poly in _outline:
		var segs := PackedVector2Array()
		for i in poly.size():
			segs.append(poly[i])
			segs.append(poly[(i + 1) % poly.size()])
		var shape := ConcavePolygonShape2D.new()
		shape.segments = segs
		var cs := CollisionShape2D.new()
		cs.shape = shape
		body.add_child(cs)

# --- Light occluders ---

func _rebuild_occluders() -> void:
	if occluders == null:
		return

	var polys: Array = []
	if casts_shadow:
		for poly: PackedVector2Array in _outline:
			if poly.size() >= 3:
				polys.append(poly)

	# Reuse existing nodes instead of recreating them on every curve tweak
	while occluders.get_child_count() > polys.size():
		var extra := occluders.get_child(occluders.get_child_count() - 1)
		occluders.remove_child(extra)
		extra.queue_free()
	while occluders.get_child_count() < polys.size():
		var node := LightOccluder2D.new()
		node.occluder = OccluderPolygon2D.new()
		occluders.add_child(node)

	for i in polys.size():
		var node := occluders.get_child(i) as LightOccluder2D
		node.occluder_light_mask = occluder_light_mask
		node.occluder.polygon = polys[i]

# --- Height illusion ---

func _invalidate_height() -> void:
	_last_viewer = Vector2(NAN, NAN)

func _viewer_global() -> Vector2:
	if _viewer == null or not is_instance_valid(_viewer):
		_viewer = get_tree().get_first_node_in_group(VIEWER_GROUP) as Node2D
	if _viewer:
		return _viewer.global_position
	if Engine.is_editor_hint():
		return preview_viewer_position
	return Vector2.INF

func _offset(p: Vector2, viewer: Vector2) -> Vector2:
	return (p - viewer) * height_factor

func _apply_height() -> void:
	if line == null:
		return
	var g := _viewer_global()
	var local_v := to_local(g) if g.is_finite() else Vector2.INF
	if local_v == _last_viewer:
		return  # viewer hasn't moved, nothing to do
	_last_viewer = local_v

	if local_v.is_finite():
		var shifted := PackedVector2Array()
		shifted.resize(_base_points.size())
		for i in _base_points.size():
			shifted[i] = _base_points[i] + _offset(_base_points[i], local_v)
		line.points = shifted
	else:
		line.points = _base_points
	queue_redraw()

func _draw() -> void:
	if side_texture == null or not _last_viewer.is_finite():
		return
	var tex_w := float(side_texture.get_width())
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for poly in _outline:
		var n: int = poly.size()
		var u := 0.0  # running length, so the texture tiles continuously along the wall
		for i in n:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % n]
			var edge := b - a
			var _len := edge.length()
			if _len < 0.001:
				continue  # degenerate edge from the offset, nothing to draw
			var u0 := u / tex_w
			u += _len
			var u1 := u / tex_w
			# Normal pointing away from the solid
			var normal := Vector2(edge.y, -edge.x) / _len * _outer_sign
			if normal.dot(_last_viewer - (a + b) * 0.5) <= 0.0:
				continue  # back face, hidden behind the wall
			var quad := PackedVector2Array([
				a, b,
				b + _offset(b, _last_viewer),
				a + _offset(a, _last_viewer),
			])
			var uvs := PackedVector2Array([
				Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0),
			])
			draw_primitive(quad, white, uvs, side_texture)
