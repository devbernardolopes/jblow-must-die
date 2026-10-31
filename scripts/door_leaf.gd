@tool
class_name DoorLeaf
extends Node2D
## One moving panel of a Door.
##
## A leaf only renders a panel: the Door owns the authored curve, splits it into
## panels and animates each leaf's `transform`. Geometry is expressed in this
## node's local space, so sliding is a translation and swinging is a rotation
## about this node's origin (the hinge).
##
## Rendering follows Wall: a Line2D for the top face, an offset outline for the
## collision and light occluders, and a fake height drawn as side quads toward
## the shared "door_viewer" (the follow camera).

const VIEWER_GROUP := &"door_viewer"
const MIN_EDGE_LENGTH: float = 0.001
const MIN_POLYGON_POINTS: int = 3

@export var texture: Texture2D = null:
	set(value):
		texture = value
		_apply_style()

@export var texture_mode: Line2D.LineTextureMode = Line2D.LineTextureMode.LINE_TEXTURE_TILE:
	set(value):
		texture_mode = value
		_apply_style()

@export var width: float = 128.0:
	set(value):
		width = value
		_apply_style()
		_rebuild()

@export var pixel_art: bool = false:
	set(value):
		pixel_art = value
		_apply_style()

@export var solid: bool = true:
	set(value):
		solid = value
		_rebuild_collision()

@export var casts_shadow: bool = true:
	set(value):
		casts_shadow = value
		_rebuild_occluders()

@export_flags_2d_render var occluder_light_mask: int = 1:
	set(value):
		occluder_light_mask = value
		_rebuild_occluders()

@export_group("Height illusion")

## Front view of the panel. Should tile horizontally.
@export var side_texture: Texture2D = null:
	set(value):
		side_texture = value
		_invalidate_height()

## How strongly the top shifts away from the viewer (fake height).
@export_range(0.0, 0.5, 0.005) var height_factor: float = 0.06:
	set(value):
		height_factor = value
		_invalidate_height()

## Editor-only: where the "eye" is when no viewer node exists in the edited scene.
@export var preview_viewer_position: Vector2 = Vector2.ZERO:
	set(value):
		preview_viewer_position = value
		_invalidate_height()

var line: Line2D = null
var body: AnimatableBody2D = null
var occluders: Node2D = null

var _base_points := PackedVector2Array()
var _length: float = 0.0
var _outline: Array[PackedVector2Array] = []
var _outer_sign: float = 1.0
var _viewer: Node2D = null
var _last_viewer := Vector2(NAN, NAN)  # local space; NAN = needs refresh, INF = no viewer


func _ready() -> void:
	_ensure_nodes()
	_apply_style()
	_rebuild()


func _process(_delta: float) -> void:
	_apply_height()


## Replaces the panel geometry. Points are in this node's local space.
func setup(points: PackedVector2Array) -> void:
	_base_points = points
	_length = _polyline_length(points)
	_ensure_nodes()
	_apply_style()
	_rebuild()


## Length of the panel centerline, in pixels. Used to derive travel distances.
func get_length() -> float:
	return _length


func _ensure_nodes() -> void:
	if line == null:
		line = Line2D.new()
		line.name = "Line"
		add_child(line, false, Node.INTERNAL_MODE_FRONT)
	if body == null:
		body = AnimatableBody2D.new()
		body.name = "Body"
		body.sync_to_physics = true
		body.collision_layer = PhysicsLayers.OBJECTS
		body.collision_mask = 0
		add_child(body, false, Node.INTERNAL_MODE_FRONT)
	if occluders == null:
		occluders = Node2D.new()
		occluders.name = "Occluders"
		add_child(occluders, false, Node.INTERNAL_MODE_FRONT)


func _apply_style() -> void:
	if line == null:
		return
	line.texture = texture
	line.texture_mode = texture_mode
	line.width = width
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	)
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	# Used by _draw() for the side faces
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	)


func _rebuild() -> void:
	if line == null:
		return
	line.points = _base_points
	_build_outline()
	_rebuild_collision()
	if not Engine.is_editor_hint():
		_rebuild_occluders()
	_invalidate_height()
	queue_redraw()


# --- Footprint outline (shared by collision and side faces) ---

func _build_outline() -> void:
	_outline.clear()
	if _base_points.size() < 2:
		return
	var points := _base_points.duplicate()
	# First point == last point means a closed loop.
	var closed := (
		points.size() > 2 and points[0].distance_to(points[points.size() - 1]) < 0.01
	)
	if closed:
		points = points.slice(0, points.size() - 1)
	var end_type := Geometry2D.END_JOINED if closed else Geometry2D.END_BUTT
	for poly: PackedVector2Array in Geometry2D.offset_polyline(
		points, width * 0.5, Geometry2D.JOIN_MITER, end_type
	):
		_outline.append(poly)

	# Outer polygons share one orientation, holes have the opposite one.
	# The biggest polygon is always an outer one, so it defines the convention.
	var best: float = 0.0
	for poly: PackedVector2Array in _outline:
		var area: float = _signed_area(poly)
		if absf(area) > absf(best):
			best = area
	_outer_sign = signf(best) if best != 0.0 else 1.0


static func _signed_area(poly: PackedVector2Array) -> float:
	var area: float = 0.0
	for index: int in range(poly.size()):
		var point: Vector2 = poly[index]
		var next: Vector2 = poly[(index + 1) % poly.size()]
		area += point.x * next.y - next.x * point.y
	return area * 0.5


static func _polyline_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for index: int in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
	return total


# --- Collision ---

func _rebuild_collision() -> void:
	if body == null:
		return
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	if not solid:
		return
	for poly: PackedVector2Array in _outline:
		if poly.size() < MIN_POLYGON_POINTS:
			continue
		var segments := PackedVector2Array()
		for index: int in range(poly.size()):
			segments.append(poly[index])
			segments.append(poly[(index + 1) % poly.size()])
		var shape := ConcavePolygonShape2D.new()
		shape.segments = segments
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)


# --- Light occluders ---

func _rebuild_occluders() -> void:
	if occluders == null:
		return

	var polygons: Array[PackedVector2Array] = []
	if casts_shadow:
		for poly: PackedVector2Array in _outline:
			if poly.size() >= MIN_POLYGON_POINTS:
				polygons.append(poly)

	# Reuse existing nodes instead of recreating them on every curve tweak.
	while occluders.get_child_count() > polygons.size():
		var extra: Node = occluders.get_child(occluders.get_child_count() - 1)
		occluders.remove_child(extra)
		extra.queue_free()
	while occluders.get_child_count() < polygons.size():
		var node := LightOccluder2D.new()
		node.occluder = OccluderPolygon2D.new()
		occluders.add_child(node)

	for index: int in range(polygons.size()):
		var node := occluders.get_child(index) as LightOccluder2D
		if node == null:
			continue
		node.occluder_light_mask = occluder_light_mask
		node.occluder.polygon = polygons[index]


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


func _offset(point: Vector2, viewer: Vector2) -> Vector2:
	return (point - viewer) * height_factor


func _apply_height() -> void:
	if line == null:
		return
	var viewer_global := _viewer_global()
	var local_viewer := to_local(viewer_global) if viewer_global.is_finite() else Vector2.INF
	if local_viewer == _last_viewer:
		return  # the panel and the viewer are at the same place as last time
	_last_viewer = local_viewer

	if local_viewer.is_finite():
		var shifted := PackedVector2Array()
		shifted.resize(_base_points.size())
		for index: int in range(_base_points.size()):
			shifted[index] = _base_points[index] + _offset(_base_points[index], local_viewer)
		line.points = shifted
	else:
		line.points = _base_points
	queue_redraw()


func _draw() -> void:
	if side_texture == null or not _last_viewer.is_finite():
		return
	var texture_width := float(side_texture.get_width())
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for poly: PackedVector2Array in _outline:
		var count: int = poly.size()
		var u: float = 0.0  # running length, so the texture tiles continuously
		for index: int in range(count):
			var a: Vector2 = poly[index]
			var b: Vector2 = poly[(index + 1) % count]
			var edge := b - a
			var edge_length := edge.length()
			if edge_length < MIN_EDGE_LENGTH:
				continue  # degenerate edge from the offset, nothing to draw
			var u0: float = u / texture_width
			u += edge_length
			var u1: float = u / texture_width
			# Normal pointing away from the solid
			var normal: Vector2 = Vector2(edge.y, -edge.x) / edge_length * _outer_sign
			if normal.dot(_last_viewer - (a + b) * 0.5) <= 0.0:
				continue  # back face, hidden behind the panel
			var quad := PackedVector2Array([
				a,
				b,
				b + _offset(b, _last_viewer),
				a + _offset(a, _last_viewer),
			])
			var uvs := PackedVector2Array([
				Vector2(u0, 1),
				Vector2(u1, 1),
				Vector2(u1, 0),
				Vector2(u0, 0),
			])
			draw_primitive(quad, white, uvs, side_texture)
