@tool
class_name HeightIllusion
extends Node2D
## Fake height for a top-down object, using the same perspective trick as Wall
## and DoorLeaf: every point is pushed away from the viewer in proportion to its
## distance from it, p' = p + (p - viewer) * height_factor.
##
## - The top face (`top`, usually a Sprite2D) is scaled about the viewer, which
##   is exactly that mapping applied to every point of the sprite.
## - The side faces are drawn here, between the footprint at ground level and the
##   footprint at full height, only for the edges that face the viewer.
##
## Everything is expressed in this node's local space, so the owner can be moved,
## rotated or scaled freely. Keep this node's own transform at identity.
##
## At runtime the component only updates while its bounds are near the screen. It
## creates a VisibleOnScreenNotifier2D for that (not in the editor, where the
## notifier would draw a gizmo rectangle on every object).

enum SideMapping {
	## The texture repeats continuously along the whole perimeter (barrels, rocks).
	TILED,
	## Every footprint edge shows the whole texture once (crates, boxes).
	PER_EDGE,
}

const VIEWER_GROUP := &"door_viewer"
const MIN_EDGE_LENGTH: float = 0.001
const MIN_POLYGON_POINTS: int = 3
const CIRCLE_SEGMENTS: int = 32
const CAPSULE_ARC_SEGMENTS: int = 12
const MIN_SCALE: float = 0.001
const FALLBACK_HALF_EXTENT: float = 32.0

## Number of components currently updating every frame. Handy to verify the
## on-screen gating, e.g. print it from a debug label.
static var active_count: int = 0

static var _shared_viewer: Node2D = null
static var _viewer_lookup_frame: int = -1

## Perspective strength, roughly object height / camera height. 0 disables the effect.
@export_range(0.0, 0.5, 0.005) var height_factor: float = 0.0:
	set(value):
		height_factor = maxf(value, 0.0)
		_params_changed()

## Front view of the object's sides. Authored at the same pixel density as the top.
@export var side_texture: Texture2D = null:
	set(value):
		side_texture = value
		_params_changed()

## Multiplies the side texture. Without a side texture the sides are filled with it.
@export var side_tint: Color = Color.WHITE:
	set(value):
		side_tint = value
		_params_changed()

@export var side_mapping: SideMapping = SideMapping.TILED:
	set(value):
		side_mapping = value
		_params_changed()

@export var pixel_art: bool = false:
	set(value):
		pixel_art = value
		_apply_filter()
		_params_changed()

## Editor only: where the "eye" is when no node of the viewer group exists.
@export var preview_viewer_position: Vector2 = Vector2.ZERO:
	set(value):
		preview_viewer_position = value
		_params_changed()

## How far past its bounds, in global pixels, an object still counts as on screen.
## Covers camera movement and the frame it takes the notifier to report.
@export var cull_margin: float = 128.0:
	set(value):
		cull_margin = maxf(value, 0.0)
		_update_notifier_rect()

## The node shifted and scaled as the top face. Its transform at the time it is
## assigned is its resting transform.
var top: Node2D = null:
	set = set_top

var _footprint := PackedVector2Array()
var _outer_sign: float = 1.0
var _top_rest := Transform2D.IDENTITY
var _last_viewer := Vector2(NAN, NAN)  # local space; NAN = needs refresh, INF = no effect
var _notifier: VisibleOnScreenNotifier2D = null
var _screen_active: bool = false


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_apply_filter()
	if Engine.is_editor_hint():
		_screen_active = true
	else:
		_ensure_notifier()
	_update_notifier_rect()
	_refresh_processing()
	# One update regardless of the gating, so nothing pops in at its first frame.
	_invalidate()
	_update_height()


func _exit_tree() -> void:
	if _screen_active and not Engine.is_editor_hint():
		active_count -= 1
	_screen_active = false


func _process(_delta: float) -> void:
	_update_height()


# --- Public API ---

## Sets the node used as the top face and remembers its resting transform.
func set_top(node: Node2D) -> void:
	top = node
	if top == null:
		return
	_top_rest = top.transform
	# Repeat would bleed the opposite texture edge into the sprite border.
	top.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_invalidate()
	_update_notifier_rect()


## Ground footprint, in this node's local space. Any simple polygon works.
func set_footprint(points: PackedVector2Array) -> void:
	_footprint = points
	_outer_sign = signf(_signed_area(points))
	if _outer_sign == 0.0:
		_outer_sign = 1.0
	_update_notifier_rect()
	_invalidate()
	_update_height()


func get_footprint() -> PackedVector2Array:
	return _footprint


## Call after changing the top texture so the culling bounds follow it.
func refresh() -> void:
	_update_notifier_rect()
	_invalidate()
	_update_height()


## Footprint polygon of a collision shape, transformed into the owner's local space.
## Handles rectangle, circle, capsule and convex polygon shapes.
static func footprint_from_shape(
	shape: Shape2D, shape_transform: Transform2D = Transform2D.IDENTITY
) -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape == null:
		return points
	if shape is RectangleShape2D:
		var half: Vector2 = (shape as RectangleShape2D).size * 0.5
		points.append(Vector2(-half.x, -half.y))
		points.append(Vector2(half.x, -half.y))
		points.append(Vector2(half.x, half.y))
		points.append(Vector2(-half.x, half.y))
	elif shape is CircleShape2D:
		var circle_radius: float = (shape as CircleShape2D).radius
		for index: int in range(CIRCLE_SEGMENTS):
			points.append(Vector2.from_angle(TAU * index / CIRCLE_SEGMENTS) * circle_radius)
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		var radius: float = capsule.radius
		var half_middle: float = maxf(capsule.height * 0.5 - radius, 0.0)
		# Top half circle, left to right, then bottom half circle, right to left.
		for index: int in range(CAPSULE_ARC_SEGMENTS + 1):
			var top_angle: float = PI + PI * index / CAPSULE_ARC_SEGMENTS
			points.append(Vector2(0.0, -half_middle) + Vector2.from_angle(top_angle) * radius)
		for index: int in range(CAPSULE_ARC_SEGMENTS + 1):
			var bottom_angle: float = PI * index / CAPSULE_ARC_SEGMENTS
			points.append(Vector2(0.0, half_middle) + Vector2.from_angle(bottom_angle) * radius)
	elif shape is ConvexPolygonShape2D:
		points = (shape as ConvexPolygonShape2D).points
	else:
		push_warning("HeightIllusion: %s has no footprint conversion." % shape.get_class())
	return shape_transform * points


## Footprint polygon of a CollisionPolygon2D (or any polygon), in the owner's local space.
static func footprint_from_polygon(
	polygon: PackedVector2Array, polygon_transform: Transform2D = Transform2D.IDENTITY
) -> PackedVector2Array:
	return polygon_transform * polygon


# --- Internals ---

static func _signed_area(poly: PackedVector2Array) -> float:
	var area: float = 0.0
	for index: int in range(poly.size()):
		var point: Vector2 = poly[index]
		var next: Vector2 = poly[(index + 1) % poly.size()]
		area += point.x * next.y - next.x * point.y
	return area * 0.5


func _apply_filter() -> void:
	texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	)


func _invalidate() -> void:
	_last_viewer = Vector2(NAN, NAN)


func _params_changed() -> void:
	_invalidate()
	if not is_inside_tree():
		return
	_refresh_processing()
	if _screen_active:
		_update_height()


func _refresh_processing() -> void:
	set_process(_screen_active and height_factor > 0.0)


# --- Screen gating ---

func _ensure_notifier() -> void:
	if _notifier != null:
		return
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.name = "ScreenGate"
	add_child(_notifier, false, Node.INTERNAL_MODE_FRONT)
	_notifier.screen_entered.connect(_set_screen_active.bind(true))
	_notifier.screen_exited.connect(_set_screen_active.bind(false))


func _set_screen_active(value: bool) -> void:
	if _screen_active == value:
		return
	_screen_active = value
	active_count += 1 if value else -1
	_refresh_processing()
	if value:
		# Catch up immediately instead of waiting for the next _process.
		_invalidate()
		_update_height()


## Bounds the notifier watches: the footprint plus the top sprite. The raised top
## and the sides always sit further from the viewer than the footprint, so a
## margin is only needed for camera movement and reporting latency.
func _update_notifier_rect() -> void:
	if _notifier == null or not is_inside_tree():
		return
	var bounds := Rect2()
	var has_bounds: bool = false
	for point: Vector2 in _footprint:
		if has_bounds:
			bounds = bounds.expand(point)
		else:
			bounds = Rect2(point, Vector2.ZERO)
			has_bounds = true
	var sprite := top as Sprite2D
	if sprite != null and sprite.texture != null:
		var top_rect: Rect2 = _top_rest * sprite.get_rect()
		bounds = bounds.merge(top_rect) if has_bounds else top_rect
		has_bounds = true
	if not has_bounds:
		var half := Vector2.ONE * FALLBACK_HALF_EXTENT
		bounds = Rect2(-half, half * 2.0)
	# The margin is in global pixels; the rect is in local space.
	var scale_abs := global_transform.get_scale().abs()
	var local_scale: float = maxf(minf(scale_abs.x, scale_abs.y), MIN_SCALE)
	_notifier.rect = bounds.grow(cull_margin / local_scale)


# --- Height illusion ---

func _viewer_global() -> Vector2:
	# One group lookup per frame for all instances, not one per instance.
	if not is_instance_valid(_shared_viewer) or not _shared_viewer.is_inside_tree():
		var frame: int = Engine.get_process_frames()
		if frame != _viewer_lookup_frame:
			_viewer_lookup_frame = frame
			_shared_viewer = get_tree().get_first_node_in_group(VIEWER_GROUP) as Node2D
	if is_instance_valid(_shared_viewer):
		return _shared_viewer.global_position
	if Engine.is_editor_hint():
		return preview_viewer_position
	return Vector2.INF


func _update_height() -> void:
	if not is_inside_tree():
		return
	var local_viewer := Vector2.INF
	if height_factor > 0.0:
		var global_viewer := _viewer_global()
		if global_viewer.is_finite():
			local_viewer = to_local(global_viewer)
	if local_viewer == _last_viewer:
		return  # the object and the viewer are where they were last time
	_last_viewer = local_viewer
	if top != null:
		top.transform = _top_transform(local_viewer)
	queue_redraw()


## Scale by (1 + h) about the viewer, applied on top of the resting transform.
func _top_transform(local_viewer: Vector2) -> Transform2D:
	if not local_viewer.is_finite():
		return _top_rest
	var k: float = 1.0 + height_factor
	var about_viewer := Transform2D(
		Vector2(k, 0.0), Vector2(0.0, k), -local_viewer * height_factor
	)
	return about_viewer * _top_rest


func _offset(point: Vector2, viewer: Vector2) -> Vector2:
	return (point - viewer) * height_factor


func _draw() -> void:
	if not _last_viewer.is_finite() or _footprint.size() < MIN_POLYGON_POINTS:
		return
	var texture_width: float = 1.0
	if side_texture != null:
		texture_width = maxf(float(side_texture.get_width()), 1.0)
	var colors := PackedColorArray([side_tint, side_tint, side_tint, side_tint])
	var count: int = _footprint.size()
	var run: float = 0.0  # running perimeter length, so TILED continues across corners
	for index: int in range(count):
		var a: Vector2 = _footprint[index]
		var b: Vector2 = _footprint[(index + 1) % count]
		var edge := b - a
		var edge_length: float = edge.length()
		if edge_length < MIN_EDGE_LENGTH:
			continue  # degenerate edge, nothing to draw
		var u0: float = run / texture_width
		run += edge_length
		var u1: float = run / texture_width
		# Normal pointing away from the solid
		var normal := Vector2(edge.y, -edge.x) / edge_length * _outer_sign
		if normal.dot(_last_viewer - (a + b) * 0.5) <= 0.0:
			continue  # back face, hidden behind the top
		if side_mapping == SideMapping.PER_EDGE:
			u0 = 0.0
			u1 = 1.0
			# Seen from outside, u should run to the viewer's right so art is not mirrored.
			if edge.dot(Vector2(normal.y, -normal.x)) < 0.0:
				u0 = 1.0
				u1 = 0.0
		var quad := PackedVector2Array([
			a,
			b,
			b + _offset(b, _last_viewer),
			a + _offset(a, _last_viewer),
		])
		var uvs := PackedVector2Array([
			Vector2(u0, 1.0),
			Vector2(u1, 1.0),
			Vector2(u1, 0.0),
			Vector2(u0, 0.0),
		])
		draw_primitive(quad, colors, uvs, side_texture)
