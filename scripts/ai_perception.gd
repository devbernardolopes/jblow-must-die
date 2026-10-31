class_name AIPerception
extends Node2D
## Produces perception data for an AIController. It never writes to the blackboard.
##
## Candidates come from the `entities` group, are filtered by team and distance,
## then checked against the view cone and finally against walls with a raycast.
## Scans are staggered per entity and cached, so tree conditions stay cheap.

## Walls live on OBJECTS in this project; WORLD is kept for future layers.
const LOS_MASK: int = PhysicsLayers.WORLD | PhysicsLayers.OBJECTS

## Maximum distance at which a target can be seen, in meters.
@export var view_distance_m: float = 25.0
## Radius around the entity where targets are noticed without the view cone.
## Keep this larger than the combined collision radii so close targets register.
@export var awareness_radius_m: float = 10.0
## Full width of the view cone in degrees, centred on facing.
@export_range(0.0, 360.0) var fov_degrees: float = 100.0
## Eye offset in meters, relative to the entity and rotated with facing.
@export var eye_offset_m: Vector2 = Vector2.ZERO
## Seconds between scans; each entity starts with a random phase offset.
@export_range(0.02, 1.0, 0.01) var scan_interval_s: float = 0.15
## How long a lost target is remembered, in seconds.
@export var memory_duration_s: float = 4.0
## Caps raycasts per scan; candidates are sorted nearest first.
@export_range(1, 32) var max_raycasts: int = 6
## Draws the view cone and awareness radius in debug builds.
@export var debug_draw: bool = false

## Current best target, or null when nothing is visible or remembered.
var target: Entity = null
## True when the target was seen during the last scan.
var target_visible: bool = false
## Last position the target was seen at; survives briefly after losing sight.
var last_known_position: Vector2 = Vector2.ZERO
## Seconds since the target was last seen; INF when there is no memory.
var time_since_seen: float = INF

var _entity: Entity = null
var _scan_accumulator: float = 0.0

func _ready() -> void:
	_entity = get_parent() as Entity
	_scan_accumulator = randf() * maxf(scan_interval_s, 0.0)

func _physics_process(delta: float) -> void:
	if _entity == null or not is_instance_valid(_entity) or _entity.dead:
		return
	if target != null and (not is_instance_valid(target) or not target.is_alive()):
		_clear_target()
	if target != null and not target_visible:
		time_since_seen += delta
		if time_since_seen > memory_duration_s:
			_clear_target()
	if debug_draw:
		queue_redraw()
	_scan_accumulator += delta
	if _scan_accumulator < scan_interval_s:
		return
	_scan_accumulator = 0.0
	_scan()

## Returns the remembered target while it is still valid, or null.
func get_target() -> Entity:
	if target != null and (not is_instance_valid(target) or not target.is_alive()):
		_clear_target()
	return target

func has_target() -> bool:
	return get_target() != null

## Live target position when available, otherwise the last known position.
func get_target_position() -> Vector2:
	var current: Entity = get_target()
	if current != null:
		return current.global_position
	return last_known_position

func is_target_visible() -> bool:
	return target_visible and get_target() != null

## World-space eye position, offset from the entity origin along facing.
func eye_origin() -> Vector2:
	if _entity == null or not is_instance_valid(_entity):
		return global_position
	return _entity.global_position + Units.to_px(eye_offset_m).rotated(_entity.facing.angle())

func _scan() -> void:
	if _entity == null or not is_instance_valid(_entity) or not is_inside_tree():
		return
	var origin: Vector2 = eye_origin()
	var view_distance_px: float = Units.m_to_px(maxf(view_distance_m, 0.0))
	var view_squared: float = view_distance_px * view_distance_px
	var awareness_px: float = Units.m_to_px(maxf(awareness_radius_m, 0.0))
	var awareness_squared: float = awareness_px * awareness_px
	var half_fov_rad: float = deg_to_rad(clampf(fov_degrees, 0.0, 360.0) * 0.5)
	var candidates: Array[Entity] = []
	for node: Node in get_tree().get_nodes_in_group(&"entities"):
		var candidate: Entity = node as Entity
		if candidate == null or candidate == _entity or not candidate.is_alive():
			continue
		if not _entity.is_hostile_to(candidate):
			continue
		candidates.append(candidate)
	candidates.sort_custom(_is_nearer)
	var raycasts_left: int = maxi(max_raycasts, 0)
	var found: Entity = null
	for candidate: Entity in candidates:
		var offset: Vector2 = candidate.global_position - origin
		var distance_squared: float = offset.length_squared()
		if distance_squared > view_squared:
			continue
		var in_awareness: bool = distance_squared <= awareness_squared
		if not in_awareness and absf(_entity.facing.angle_to(offset)) > half_fov_rad:
			continue
		if raycasts_left <= 0:
			break
		raycasts_left -= 1
		if _entity.has_line_of_sight(origin, candidate.global_position, LOS_MASK):
			found = candidate
			break
	if found != null:
		_set_target(found)
		return
	target_visible = false
	if target == null:
		time_since_seen = INF

func _set_target(next_target: Entity) -> void:
	target = next_target
	target_visible = true
	time_since_seen = 0.0
	last_known_position = next_target.global_position

func _clear_target() -> void:
	target = null
	target_visible = false
	time_since_seen = INF

func _is_nearer(a: Entity, b: Entity) -> bool:
	var origin: Vector2 = _entity.global_position
	return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)

func _draw() -> void:
	if not debug_draw or not OS.is_debug_build() or _entity == null:
		return
	var origin: Vector2 = to_local(eye_origin())
	var radius: float = Units.m_to_px(maxf(view_distance_m, 0.0))
	var half_fov_rad: float = deg_to_rad(clampf(fov_degrees, 0.0, 360.0) * 0.5)
	var color: Color = (
		Color(1.0, 0.85, 0.2, 0.18) if target_visible else Color(0.8, 0.8, 0.8, 0.12)
	)
	var points: PackedVector2Array = PackedVector2Array([origin])
	var steps: int = 20
	var facing_angle: float = _entity.facing.angle()
	for index: int in range(steps + 1):
		var angle: float = (
			facing_angle - half_fov_rad + 2.0 * half_fov_rad * float(index) / float(steps)
		)
		points.append(origin + Vector2.RIGHT.rotated(angle) * radius)
	draw_colored_polygon(points, color)
	draw_circle(
		origin,
		Units.m_to_px(maxf(awareness_radius_m, 0.0)),
		Color(0.2, 0.6, 1.0, 0.08)
	)
