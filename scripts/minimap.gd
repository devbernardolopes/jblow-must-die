@tool
class_name Minimap
extends Control
## Player-centred minimap drawn into the HUD.
##
## Sources (Wall and MinimapSource) join the "minimap_source" group and return
## MinimapGeometry in global world pixels. The map draws them with a single
## transform, so the player stays centred without touching the geometry each
## frame. Fog of war plugs into the MinimapVisibility resource.

enum MapCorner {
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT,
}

enum Shape {
	CIRCLE,
	RECTANGLE,
}

const MINIMAP_SOURCE_GROUP := &"minimap_source"
const MINIMAP_GROUP := &"minimap"
const ENTITY_GROUP := &"entities"
const MIN_WORLD_RADIUS_M: float = 1.0
const MIN_REFRESH_HZ: float = 1.0
const MIN_MAP_SIZE: float = 1.0
const BORDER_SEGMENTS: int = 64
const CORNER_SEGMENTS: int = 8

@export_category("Layout")
@export var corner: MapCorner = MapCorner.TOP_RIGHT:
	set(value):
		corner = value
		_apply_layout()
		queue_redraw()
@export var map_size: Vector2 = Vector2(220.0, 220.0):
	set(value):
		map_size = value
		_apply_layout()
		queue_redraw()
@export var margin: Vector2 = Vector2(24.0, 24.0):
	set(value):
		margin = value
		_apply_layout()
		queue_redraw()
## Keeps the map from swallowing small screens: at most this fraction of the
## viewport's shorter side. The map shrinks uniformly, it never distorts.
@export_range(0.05, 1.0, 0.01) var max_viewport_fraction: float = 0.3:
	set(value):
		max_viewport_fraction = clampf(value, 0.05, 1.0)
		_apply_layout()
		queue_redraw()
@export var shape: Shape = Shape.CIRCLE:
	set(value):
		shape = value
		queue_redraw()
@export_range(0.0, 64.0, 1.0) var corner_radius: float = 0.0:
	set(value):
		corner_radius = value
		queue_redraw()

@export_category("View")
@export var target: Node2D = null
## Half of the visible world, measured from the centred player.
@export var world_radius_m: float = 200.0:
	set(value):
		world_radius_m = maxf(value, MIN_WORLD_RADIUS_M)
		queue_redraw()
## False keeps north up; true turns the map so the player faces up.
@export var rotate_with_player: bool = false:
	set(value):
		rotate_with_player = value
		queue_redraw()
@export_range(1.0, 120.0, 1.0) var refresh_hz: float = 30.0

@export_category("Walls and features")
@export_range(0.5, 8.0, 0.5) var line_width_px: float = 2.0
@export var wall_color: Color = Color(0.86, 0.88, 0.93, 1.0)
@export var area_color: Color = Color(0.30, 0.55, 0.85, 0.35)
@export var door_color: Color = Color(0.95, 0.72, 0.30, 1.0)
@export var poi_color: Color = Color(0.55, 0.90, 0.70, 1.0)

@export_category("Entities")
@export var show_other_entities: bool = false:
	set(value):
		show_other_entities = value
		queue_redraw()
@export var entity_color: Color = Color(0.95, 0.35, 0.32, 1.0)
@export_range(1.0, 12.0, 0.5) var entity_marker_radius_px: float = 3.0

@export_category("Player")
@export var player_color: Color = Color(0.95, 0.96, 1.0, 1.0)
@export_range(2.0, 24.0, 0.5) var player_marker_size_px: float = 7.0

@export_category("Chrome")
@export var background_color: Color = Color(0.02, 0.03, 0.05, 0.78)
@export var border_color: Color = Color(1.0, 1.0, 1.0, 0.45)
@export_range(0.0, 8.0, 0.5) var border_width_px: float = 2.0

@export_category("Fog of war")
## Null reveals everything. Assign a MinimapVisibility subclass to enable fog.
@export var visibility: MinimapVisibility = null

var _geometry: Array[MinimapGeometry] = []
var _refresh_accumulator: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	add_to_group(MINIMAP_GROUP)
	# Editor previews only redraw when something changes; no need to poll.
	set_process(not Engine.is_editor_hint())
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)
	_apply_layout()
	_connect_sources()
	rebuild_geometry()
	# Sources join their group from _ready(). Run once more after the current
	# ready pass so every authored wall is present regardless of tree order.
	call_deferred(&"rebuild_geometry")


func _process(delta: float) -> void:
	_refresh_accumulator += delta
	if _refresh_accumulator < _refresh_interval():
		return
	_refresh_accumulator = 0.0
	queue_redraw()


# --- Layout ---------------------------------------------------------------

## Offsets are relative to the control's anchor, so the map stays pinned to its
## corner on every viewport size (desktop, mobile, web).
static func compute_offsets(value: MapCorner, size_px: Vector2, margin_px: Vector2) -> Rect2:
	var box := Vector2(maxf(size_px.x, MIN_MAP_SIZE), maxf(size_px.y, MIN_MAP_SIZE))
	var anchor: Vector2 = corner_anchor(value)
	var top_left := Vector2(
		-margin_px.x - box.x if anchor.x > 0.5 else margin_px.x,
		-margin_px.y - box.y if anchor.y > 0.5 else margin_px.y
	)
	return Rect2(top_left, box)


## Where the map lands in the parent, for tests and documentation.
static func compute_screen_rect(
	value: MapCorner, size_px: Vector2, margin_px: Vector2, parent_size: Vector2
) -> Rect2:
	var offsets: Rect2 = compute_offsets(value, size_px, margin_px)
	var anchor: Vector2 = corner_anchor(value)
	return Rect2(parent_size * anchor + offsets.position, offsets.size)


static func corner_anchor(value: MapCorner) -> Vector2:
	match value:
		MapCorner.TOP_RIGHT:
			return Vector2(1.0, 0.0)
		MapCorner.BOTTOM_LEFT:
			return Vector2(0.0, 1.0)
		MapCorner.BOTTOM_RIGHT:
			return Vector2(1.0, 1.0)
		_:
			return Vector2(0.0, 0.0)


## Shrinks the requested size uniformly until it fits the fraction cap, so the
## map stays proportional on phones, desktop and web without distorting.
static func fit_map_size(requested: Vector2, viewport_size: Vector2, fraction: float) -> Vector2:
	var box := Vector2(maxf(requested.x, MIN_MAP_SIZE), maxf(requested.y, MIN_MAP_SIZE))
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return box
	var limit: float = minf(viewport_size.x, viewport_size.y) * clampf(fraction, 0.05, 1.0)
	var longest: float = maxf(box.x, box.y)
	if longest <= limit:
		return box
	return box * (limit / longest)


func _effective_map_size() -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2.ZERO
	return fit_map_size(map_size, viewport_size, max_viewport_fraction)


func _apply_layout() -> void:
	if not is_inside_tree():
		return
	var offsets: Rect2 = compute_offsets(corner, _effective_map_size(), margin)
	var anchor: Vector2 = corner_anchor(corner)
	anchor_left = anchor.x
	anchor_right = anchor.x
	anchor_top = anchor.y
	anchor_bottom = anchor.y
	offset_left = offsets.position.x
	offset_top = offsets.position.y
	offset_right = offsets.end.x
	offset_bottom = offsets.end.y


func _map_box() -> Vector2:
	var box: Vector2 = size
	if box.x < MIN_MAP_SIZE or box.y < MIN_MAP_SIZE:
		box = _effective_map_size()
	return Vector2(maxf(box.x, MIN_MAP_SIZE), maxf(box.y, MIN_MAP_SIZE))


# --- Geometry sources -----------------------------------------------------

## Rebuilds the cached shapes. Sources can call this after changing their
## geometry (MinimapSource does it automatically through its setters).
func rebuild_geometry() -> void:
	_geometry.clear()
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(MINIMAP_SOURCE_GROUP):
			if not node.has_method(&"get_minimap_geometry"):
				continue
			var value: Variant = node.call(&"get_minimap_geometry")
			if value is not Array:
				continue
			for item: Variant in value:
				if item is MinimapGeometry:
					_geometry.append(item as MinimapGeometry)
	_geometry.sort_custom(
		func(first: MinimapGeometry, second: MinimapGeometry) -> bool:
			return first.kind < second.kind
	)
	queue_redraw()


## Read-only view of the cached shapes, for debugging and tests.
func get_geometry() -> Array[MinimapGeometry]:
	return _geometry


func _connect_sources() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(MINIMAP_SOURCE_GROUP):
		var wall := node as Wall
		if wall == null or wall.curve == null:
			continue
		if not wall.curve.changed.is_connected(_on_source_geometry_changed):
			wall.curve.changed.connect(_on_source_geometry_changed)


func _on_source_geometry_changed() -> void:
	rebuild_geometry()


# --- Projection -----------------------------------------------------------

static func world_to_map(
	world_position: Vector2,
	player_position: Vector2,
	map_scale: float,
	map_rotation: float,
	center: Vector2
) -> Vector2:
	return center + (world_position - player_position).rotated(map_rotation) * map_scale


## World pixels to control-local pixels. The player lands exactly on center.
static func map_transform(
	player_position: Vector2, map_scale: float, map_rotation: float, center: Vector2
) -> Transform2D:
	var origin: Vector2 = center - (player_position * map_scale).rotated(map_rotation)
	return Transform2D(map_rotation, Vector2.ONE * map_scale, 0.0, origin)


# --- Clipping -------------------------------------------------------------

## Convex polygon approximating a circle, used to clip map geometry.
static func circle_polygon(
	center: Vector2, radius: float, segments: int = BORDER_SEGMENTS
) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var count: int = maxi(segments, 3)
	if radius <= 0.0:
		return polygon
	polygon.resize(count)
	for index: int in range(count):
		var angle: float = TAU * float(index) / float(count)
		polygon[index] = center + Vector2(cos(angle), sin(angle)) * radius
	return polygon


## Convex polygon for a (rounded) rectangle whose top-left corner is at the origin.
static func rounded_rect_polygon(
	size_px: Vector2, radius_px: float, segments_per_corner: int = CORNER_SEGMENTS
) -> PackedVector2Array:
	var box := Vector2(maxf(size_px.x, 0.0), maxf(size_px.y, 0.0))
	if box.x <= 0.0 or box.y <= 0.0:
		return PackedVector2Array()
	var radius: float = clampf(radius_px, 0.0, minf(box.x, box.y) * 0.5)
	if radius <= 0.0:
		return PackedVector2Array([
			Vector2.ZERO,
			Vector2(box.x, 0.0),
			Vector2(box.x, box.y),
			Vector2(0.0, box.y),
		])
	var steps: int = maxi(segments_per_corner, 1)
	var corners: Array[Vector2] = [
		Vector2(box.x - radius, radius),
		Vector2(box.x - radius, box.y - radius),
		Vector2(radius, box.y - radius),
		Vector2(radius, radius),
	]
	var start_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	var polygon := PackedVector2Array()
	for corner_index: int in range(corners.size()):
		var corner_center: Vector2 = corners[corner_index]
		var start_angle: float = start_angles[corner_index]
		for step: int in range(steps + 1):
			var angle: float = start_angle + (PI * 0.5) * float(step) / float(steps)
			polygon.append(corner_center + Vector2(cos(angle), sin(angle)) * radius)
	return polygon


## Clip polygon in map-local pixels for the current shape and inset.
##
## An empty result means the rectangular control clip (clip_contents) already
## does the job. Strokes pass half their width as the inset so the stroke's
## outer edge lands on the border instead of spilling past it.
func _clip_polygon(inset_px: float) -> PackedVector2Array:
	var box: Vector2 = _map_box()
	if shape == Shape.CIRCLE:
		return circle_polygon(box * 0.5, minf(box.x, box.y) * 0.5 - inset_px)
	if corner_radius <= 0.0:
		return PackedVector2Array()
	var inner := box - Vector2.ONE * (inset_px * 2.0)
	if inner.x <= 0.0 or inner.y <= 0.0:
		return PackedVector2Array()
	var polygon: PackedVector2Array = rounded_rect_polygon(
		inner, maxf(corner_radius - inset_px, 0.0)
	)
	if inset_px <= 0.0:
		return polygon
	for index: int in range(polygon.size()):
		polygon[index] += Vector2.ONE * inset_px
	return polygon


func _world_scale(box: Vector2) -> float:
	var radius_px: float = minf(box.x, box.y) * 0.5
	var world_radius_px: float = Units.m_to_px(maxf(world_radius_m, MIN_WORLD_RADIUS_M))
	return radius_px / world_radius_px


func _map_rotation(player: Node2D) -> float:
	if not rotate_with_player:
		return 0.0
	return -_facing(player).angle() - PI * 0.5


## Entities expose "facing"; any other Node2D falls back to east.
func _facing(player: Node2D) -> Vector2:
	var value: Variant = player.get(&"facing")
	if value is Vector2:
		var direction: Vector2 = value as Vector2
		if not direction.is_zero_approx():
			return direction.normalized()
	return Vector2.RIGHT


func _refresh_interval() -> float:
	return 1.0 / maxf(refresh_hz, MIN_REFRESH_HZ)


func _on_viewport_resized() -> void:
	_apply_layout()
	queue_redraw()


# --- Drawing --------------------------------------------------------------

func _draw() -> void:
	var box: Vector2 = _map_box()
	_draw_background(box)
	var player: Node2D = _resolve_target()
	if player != null:
		_draw_geometry(player)
		_draw_entities(player)
		_draw_player(player)
	else:
		_draw_placeholder()
	_draw_border()


func _draw_background(box: Vector2) -> void:
	if shape == Shape.CIRCLE:
		var radius: float = minf(box.x, box.y) * 0.5
		if radius <= 0.0:
			return
		draw_circle(box * 0.5, radius, background_color, true, -1.0, true)
		return
	if corner_radius <= 0.0:
		draw_rect(Rect2(Vector2.ZERO, box), background_color)
		return
	var polygon: PackedVector2Array = rounded_rect_polygon(box, corner_radius)
	if polygon.size() >= 3:
		draw_colored_polygon(polygon, background_color)


func _resolve_target() -> Node2D:
	if target != null and is_instance_valid(target):
		return target
	# Editor preview: Hud owns the player reference, so borrow it when unset.
	var parent := get_parent()
	if parent != null and "target" in parent:
		var value: Variant = parent.get("target")
		if value is Node2D and is_instance_valid(value):
			return value as Node2D
	return null


func _draw_geometry(player: Node2D) -> void:
	if _geometry.is_empty():
		return
	var box: Vector2 = _map_box()
	var map_scale: float = _world_scale(box)
	if map_scale <= 0.0:
		return
	var center: Vector2 = box * 0.5
	var transform: Transform2D = map_transform(
		player.global_position, map_scale, _map_rotation(player), center
	)
	# Fills reach the border; strokes stop half a line short so their outer
	# edge lands on it instead of spilling over.
	var fill_clip: PackedVector2Array = _clip_polygon(0.0)
	var stroke_clip: PackedVector2Array = _clip_polygon(line_width_px * 0.5)
	for geometry: MinimapGeometry in _geometry:
		if geometry.points.size() < 2 or not _is_geometry_revealed(geometry):
			continue
		var color: Color = _geometry_color(geometry)
		var local_points: PackedVector2Array = _to_local(geometry.points, transform)
		if geometry.filled and geometry.points.size() >= 3:
			_draw_filled_geometry(local_points, color, fill_clip)
			continue
		_draw_line_geometry(local_points, geometry.closed, color, stroke_clip)


func _draw_filled_geometry(
	points: PackedVector2Array, color: Color, clip: PackedVector2Array
) -> void:
	if clip.is_empty():
		draw_colored_polygon(points, color)
		return
	if not _intersects_clip(points, clip, 0.0):
		return
	if _is_inside_clip(points, clip):
		draw_colored_polygon(points, color)
		return
	var parts: Array[PackedVector2Array] = Geometry2D.intersect_polygons(points, clip)
	for part: PackedVector2Array in parts:
		if part.size() >= 3:
			draw_colored_polygon(part, color)


func _draw_line_geometry(
	points: PackedVector2Array, closed: bool, color: Color, clip: PackedVector2Array
) -> void:
	var line: PackedVector2Array = _closed_line(points, closed)
	if clip.is_empty():
		draw_polyline(line, color, line_width_px, true)
		return
	var half_width: float = line_width_px * 0.5
	if not _intersects_clip(line, clip, half_width):
		return
	if _is_inside_clip(line, clip):
		draw_polyline(line, color, line_width_px, true)
		return
	var parts: Array[PackedVector2Array] = Geometry2D.intersect_polyline_with_polygon(line, clip)
	for part: PackedVector2Array in parts:
		if part.size() >= 2:
			draw_polyline(part, color, line_width_px, true)


static func _to_local(points: PackedVector2Array, transform: Transform2D) -> PackedVector2Array:
	var local_points := PackedVector2Array()
	local_points.resize(points.size())
	for index: int in range(points.size()):
		local_points[index] = transform * points[index]
	return local_points


static func _closed_line(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	if not closed or points.size() < 3:
		return points
	if points[0].is_equal_approx(points[points.size() - 1]):
		return points
	var loop: PackedVector2Array = points.duplicate()
	loop.append(points[0])
	return loop


static func _points_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for index: int in range(1, points.size()):
		bounds = bounds.expand(points[index])
	return bounds


## Cheap reject for geometry nowhere near the clip polygon.
static func _intersects_clip(
	points: PackedVector2Array, clip: PackedVector2Array, margin_px: float
) -> bool:
	if points.is_empty() or clip.size() < 3:
		return false
	return _points_bounds(points).grow(margin_px).intersects(_points_bounds(clip), true)


## Both clip shapes are convex, so an AABB is inside when its four corners are.
static func _is_inside_clip(points: PackedVector2Array, clip: PackedVector2Array) -> bool:
	if points.is_empty() or clip.size() < 3:
		return false
	var bounds: Rect2 = _points_bounds(points)
	var corners: Array[Vector2] = [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	]
	for corner: Vector2 in corners:
		if not Geometry2D.is_point_in_polygon(corner, clip):
			return false
	return true


func _draw_entities(player: Node2D) -> void:
	for marker: Vector2 in collect_entity_markers(player):
		draw_circle(marker, entity_marker_radius_px, entity_color)


## Screen-space positions of the other entities, culled to the map.
func collect_entity_markers(player: Node2D) -> Array[Vector2]:
	var markers: Array[Vector2] = []
	if not show_other_entities or player == null or not is_inside_tree():
		return markers
	var box: Vector2 = _map_box()
	var map_scale: float = _world_scale(box)
	var map_rotation: float = _map_rotation(player)
	var center: Vector2 = box * 0.5
	var radius_px: float = minf(box.x, box.y) * 0.5
	for node: Node in get_tree().get_nodes_in_group(ENTITY_GROUP):
		var entity := node as Node2D
		if entity == null or entity == player or not entity.is_inside_tree():
			continue
		if visibility != null and not visibility.is_visible_now(entity.global_position):
			continue
		var marker: Vector2 = world_to_map(
			entity.global_position, player.global_position, map_scale, map_rotation, center
		)
		if marker.distance_to(center) > radius_px - entity_marker_radius_px:
			continue
		markers.append(marker)
	return markers


func _draw_player(player: Node2D) -> void:
	var center: Vector2 = _map_box() * 0.5
	var angle: float = -PI * 0.5 if rotate_with_player else _facing(player).angle()
	var forward: Vector2 = Vector2.RIGHT.rotated(angle)
	var side: Vector2 = Vector2.DOWN.rotated(angle)
	var size_px: float = player_marker_size_px
	var triangle := PackedVector2Array([
		center + forward * size_px,
		center - forward * size_px * 0.7 + side * size_px * 0.7,
		center - forward * size_px * 0.7 - side * size_px * 0.7,
	])
	draw_colored_polygon(triangle, player_color)


func _draw_placeholder() -> void:
	var center: Vector2 = _map_box() * 0.5
	var size_px: float = player_marker_size_px
	var triangle := PackedVector2Array([
		center + Vector2(size_px, 0.0),
		center + Vector2(-size_px * 0.7, size_px * 0.7),
		center + Vector2(-size_px * 0.7, -size_px * 0.7),
	])
	draw_colored_polygon(triangle, Color(player_color, player_color.a * 0.5))


func _draw_border() -> void:
	if border_width_px <= 0.0:
		return
	var box: Vector2 = _map_box()
	if shape == Shape.CIRCLE:
		var radius: float = minf(box.x, box.y) * 0.5 - border_width_px * 0.5
		if radius <= 0.0:
			return
		draw_arc(box * 0.5, radius, 0.0, TAU, BORDER_SEGMENTS, border_color, border_width_px, true)
	elif corner_radius > 0.0:
		var outline: PackedVector2Array = rounded_rect_polygon(box, corner_radius)
		if outline.size() >= 3:
			outline.append(outline[0])
			draw_polyline(outline, border_color, border_width_px, true)
	else:
		draw_rect(Rect2(Vector2.ZERO, box), border_color, false, border_width_px)


func _is_geometry_revealed(geometry: MinimapGeometry) -> bool:
	if visibility == null or geometry.points.is_empty():
		return true
	return visibility.is_explored(geometry.get_probe_point())


func _geometry_color(geometry: MinimapGeometry) -> Color:
	if geometry.color.a > 0.0:
		return geometry.color
	match geometry.kind:
		MinimapGeometry.Kind.WALL:
			return wall_color
		MinimapGeometry.Kind.DOOR:
			return door_color
		MinimapGeometry.Kind.POI:
			return poi_color
		_:
			return area_color
