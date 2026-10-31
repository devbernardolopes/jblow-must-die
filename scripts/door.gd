@tool
class_name Door
extends Path2D
## Authorable door, drawn in the World scene exactly like a Wall.
##
## The node itself is a fixed anchor: it never moves. The authored curve is the
## closed footprint, and the panels that actually move are DoorLeaf children.
## A leaf pivots or slides by animating its own `transform`, so rotation happens
## around a curve point and anything parented to the Door (the Interactable)
## stays put in world space.
##
## DoorData says what the door is (single/double, slide/swing). The node keeps
## the per-instance choices: hinge end, slide direction, swing side and speed.

signal opened
signal closed
signal state_changed(new_state: DoorState)

enum DoorState {
	CLOSED,
	OPENING,
	OPENED,
	CLOSING,
}

const MINIMAP_SOURCE_GROUP := &"minimap_source"
const MINIMAP_GROUP := &"minimap"
const MIN_DURATION: float = 0.01
const MIN_TRAVEL: float = 0.001
const MIN_POINTS: int = 2
const MIN_POLYGON_POINTS: int = 3

@export_group("Behavior")
@export var data: DoorData = null:
	set(value):
		data = value
		_rebuild()

## Panel travel speed in pixels per second. Duration is derived from the
## longest travel of any panel, so double doors finish together.
@export var open_speed: float = 256.0
## Open when the scene starts.
@export var starts_open: bool = false

@export_group("Placement")
## Single sliding doors: slide toward the curve start instead of its end.
@export var slide_reversed: bool = false
## Single swinging doors: hinge on the curve end instead of its start.
@export var hinge_at_end: bool = false
## Swinging doors: sweep to the other side of the wall.
@export var swing_reversed: bool = false

@export_group("Interaction")
@export var interaction_enabled: bool = true:
	set(value):
		interaction_enabled = value
		_sync_interactable()
## Interaction circle radius, in meters, centred on the doorway.
@export_range(0.0, 8.0, 0.1) var interaction_radius_m: float = 1.5:
	set(value):
		interaction_radius_m = maxf(value, 0.0)
		_sync_interactable()

@export_group("Visuals")
@export var disable_editor: bool = false

@export var bake_interval: float = 8.0:
	set(value):
		bake_interval = value
		_rebuild()

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

@export var pixel_art: bool = false:
	set(value):
		pixel_art = value
		_apply_style()

@export var solid: bool = true:
	set(value):
		solid = value
		_apply_style()

@export var casts_shadow: bool = true:
	set(value):
		casts_shadow = value
		_apply_style()

@export_flags_2d_render var occluder_light_mask: int = 1:
	set(value):
		occluder_light_mask = value
		_apply_style()

@export_group("Height illusion")
@export var side_texture: Texture2D = null:
	set(value):
		side_texture = value
		_apply_style()

@export_range(0.0, 0.5, 0.005) var height_factor: float = 0.06:
	set(value):
		height_factor = value
		_apply_style()

@export var preview_viewer_position: Vector2 = Vector2.ZERO:
	set(value):
		preview_viewer_position = value
		_apply_style()

## Runtime state. Use open(), close() and toggle() to change it.
var state: DoorState = DoorState.CLOSED
## 0 = fully closed, 1 = fully open.
var progress: float = 0.0
var leaves: Array[DoorLeaf] = []
var interactable: Interactable = null

var _connected_curve: Curve2D = null
var _rebuilding: bool = false
var _closed_transforms: Array[Transform2D] = []
var _open_transforms: Array[Transform2D] = []
var _leaf_lengths: Array[float] = []
var _duration: float = MIN_DURATION
var _target_progress: float = 0.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		disable_editor = false

	add_to_group(MINIMAP_SOURCE_GROUP)
	rebuild()
	progress = 1.0 if starts_open else 0.0
	_target_progress = progress
	_apply_progress()
	_set_state(DoorState.OPENED if starts_open else DoorState.CLOSED)
	call_deferred(&"_refresh_after_ready")


func _refresh_after_ready() -> void:
	_sync_interactable()
	_notify_minimap_changed()


func _process(_delta: float) -> void:
	if disable_editor:
		return
	# Reconnect if the Curve resource was created/replaced in the Inspector.
	if curve != _connected_curve:
		if _connected_curve and _connected_curve.changed.is_connected(_rebuild):
			_connected_curve.changed.disconnect(_rebuild)
		_connected_curve = curve
		if curve:
			curve.changed.connect(_rebuild)
		_rebuild()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if state != DoorState.OPENING and state != DoorState.CLOSING:
		return
	progress = move_toward(progress, _target_progress, delta / _duration)
	_apply_progress()
	if not is_equal_approx(progress, _target_progress):
		return
	progress = _target_progress
	_apply_progress()
	if progress >= 1.0:
		_set_state(DoorState.OPENED)
		opened.emit()
	else:
		_set_state(DoorState.CLOSED)
		closed.emit()


# --- Public API ---

func open() -> void:
	if state == DoorState.OPENED or state == DoorState.OPENING:
		return
	_target_progress = 1.0
	_set_state(DoorState.OPENING)


func close() -> void:
	if state == DoorState.CLOSED or state == DoorState.CLOSING:
		return
	_target_progress = 0.0
	_set_state(DoorState.CLOSING)


func toggle() -> void:
	if state == DoorState.CLOSED or state == DoorState.CLOSING:
		open()
	else:
		close()


func is_open() -> bool:
	return state == DoorState.OPENED


func is_busy() -> bool:
	return state == DoorState.OPENING or state == DoorState.CLOSING


func _set_state(value: DoorState) -> void:
	if state == value:
		return
	state = value
	_sync_interactable()
	state_changed.emit(state)


# --- Building ---

## Rebuilds every panel from the authored curve. Safe to call at any time.
func rebuild() -> void:
	_rebuild()


func _rebuild() -> void:
	if _rebuilding or curve == null:
		return
	_rebuilding = true
	if not is_equal_approx(curve.bake_interval, bake_interval):
		curve.bake_interval = bake_interval
	_build_leaves(curve.get_baked_points())
	_duration = _compute_duration()
	_apply_progress()
	_sync_interactable()
	_notify_minimap_changed()
	_rebuilding = false


func _build_leaves(points: PackedVector2Array) -> void:
	if leaves.is_empty():
		_collect_existing_leaves()
	if points.size() < MIN_POINTS:
		_clear_leaves()
		return

	var spans: Array[PackedVector2Array] = []
	if _kind() == DoorData.Kind.DOUBLE:
		spans = _split_at_half(points)
	else:
		spans = [points]

	while leaves.size() > spans.size():
		var extra: DoorLeaf = leaves.pop_back()
		_closed_transforms.pop_back()
		_open_transforms.pop_back()
		_leaf_lengths.pop_back()
		extra.get_parent().remove_child(extra)
		extra.queue_free()

	while leaves.size() < spans.size():
		var leaf := DoorLeaf.new()
		leaf.name = "Leaf%d" % leaves.size()
		add_child(leaf, false, Node.INTERNAL_MODE_FRONT)
		leaves.append(leaf)
		_closed_transforms.append(Transform2D.IDENTITY)
		_open_transforms.append(Transform2D.IDENTITY)
		_leaf_lengths.append(0.0)

	for index: int in range(spans.size()):
		_configure_leaf(index, spans[index])


## Reuses panels that survived a script reload instead of stacking duplicates.
func _collect_existing_leaves() -> void:
	for child: Node in get_children(true):
		var leaf := child as DoorLeaf
		if leaf == null:
			continue
		leaves.append(leaf)
		_closed_transforms.append(Transform2D.IDENTITY)
		_open_transforms.append(Transform2D.IDENTITY)
		_leaf_lengths.append(0.0)


func _clear_leaves() -> void:
	for leaf: DoorLeaf in leaves:
		if is_instance_valid(leaf):
			leaf.get_parent().remove_child(leaf)
			leaf.queue_free()
	leaves.clear()
	_closed_transforms.clear()
	_open_transforms.clear()
	_leaf_lengths.clear()


func _configure_leaf(index: int, span: PackedVector2Array) -> void:
	var leaf: DoorLeaf = leaves[index]
	var last_index: int = span.size() - 1
	var pivot_index: int = 0
	if _kind() == DoorData.Kind.DOUBLE:
		# Double doors hinge on their outer ends and open toward the middle.
		pivot_index = 0 if index == 0 else last_index
	elif _motion() == DoorData.Motion.SWING and hinge_at_end:
		pivot_index = last_index

	var pivot: Vector2 = span[pivot_index]
	var local_points := PackedVector2Array()
	local_points.resize(span.size())
	for point_index: int in range(span.size()):
		local_points[point_index] = span[point_index] - pivot

	_apply_leaf_style(leaf)
	leaf.setup(local_points)
	_leaf_lengths[index] = leaf.get_length()

	var closed := Transform2D(0.0, pivot)
	var open := closed
	match _motion():
		DoorData.Motion.SWING:
			var side: float = -1.0 if swing_reversed else 1.0
			var angle: float = _open_angle_rad() * side
			if _kind() == DoorData.Kind.DOUBLE:
				if index == 1:
					angle = -angle
			elif pivot_index != 0:
				# Hinging on the far end reverses the local sweep, so rotate the
				# other way to keep the same side of the wall.
				angle = -angle
			open = Transform2D(angle, pivot)
		_:
			open = Transform2D(0.0, pivot + _slide_delta(span, pivot, index))

	_closed_transforms[index] = closed
	_open_transforms[index] = open


## Travel vector for one sliding panel, in Door-local space.
func _slide_delta(span: PackedVector2Array, _pivot: Vector2, index: int) -> Vector2:
	var tangent := Vector2.ZERO
	if span.size() >= MIN_POINTS:
		tangent = (span[span.size() - 1] - span[0])
		if tangent.length() > MIN_TRAVEL:
			tangent = tangent.normalized()
		else:
			tangent = Vector2.ZERO
	var length: float = _leaf_lengths[index]
	if _kind() == DoorData.Kind.DOUBLE:
		var inward: Vector2 = tangent if index == 0 else -tangent
		return -inward * length * _slide_ratio()
	var direction: float = -1.0 if slide_reversed else 1.0
	return tangent * length * _slide_ratio() * direction


func _compute_duration() -> float:
	var travel: float = 0.0
	for index: int in range(leaves.size()):
		if index >= _closed_transforms.size() or index >= _leaf_lengths.size():
			break
		if _motion() == DoorData.Motion.SWING:
			var angle: float = _open_transforms[index].get_rotation()
			travel = maxf(travel, absf(angle) * _leaf_lengths[index])
		else:
			travel = maxf(
				travel, (_open_transforms[index].origin - _closed_transforms[index].origin).length()
			)
	return maxf(travel / maxf(open_speed, 1.0), MIN_DURATION)


## Places every leaf at its current progress. Also used to snap the initial state.
func _apply_progress() -> void:
	var clamped: float = clampf(progress, 0.0, 1.0)
	for index: int in range(leaves.size()):
		if index >= _closed_transforms.size():
			break
		leaves[index].transform = _closed_transforms[index].interpolate_with(
			_open_transforms[index], clamped
		)


func _apply_style() -> void:
	for leaf: DoorLeaf in leaves:
		_apply_leaf_style(leaf)


func _apply_leaf_style(leaf: DoorLeaf) -> void:
	leaf.texture = texture
	leaf.texture_mode = texture_mode
	leaf.width = width
	leaf.pixel_art = pixel_art
	leaf.solid = solid
	leaf.casts_shadow = casts_shadow
	leaf.occluder_light_mask = occluder_light_mask
	leaf.side_texture = side_texture
	leaf.height_factor = height_factor
	leaf.preview_viewer_position = preview_viewer_position


# --- Interaction ---

func _sync_interactable() -> void:
	if not is_inside_tree():
		return
	if not interaction_enabled:
		if interactable != null:
			interactable.queue_free()
			interactable = null
		return
	if interactable == null or not is_instance_valid(interactable):
		interactable = _find_existing_interactable()
	if interactable == null:
		interactable = Interactable.new()
		interactable.name = "Interactable"
		add_child(interactable, false, Node.INTERNAL_MODE_FRONT)
	if not Engine.is_editor_hint() and not interactable.interacted.is_connected(_on_interacted):
		interactable.interacted.connect(_on_interacted)
	interactable.position = _interaction_anchor()
	interactable.set_radius_m(interaction_radius_m)
	interactable.prompt_text = get_interaction_prompt()


func _find_existing_interactable() -> Interactable:
	for child: Node in get_children(true):
		if child is Interactable and child.is_internal():
			return child as Interactable
	return null


## Midpoint of the authored curve, in Door-local space. The Door never moves,
## so this stays fixed in the world while the panels slide or swing.
func _interaction_anchor() -> Vector2:
	if curve == null:
		return Vector2.ZERO
	var points: PackedVector2Array = curve.get_baked_points()
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]
	var total: float = DoorLeaf._polyline_length(points)
	if total <= MIN_TRAVEL:
		return points[0]
	var half: float = total * 0.5
	var walked: float = 0.0
	for index: int in range(points.size() - 1):
		var segment: Vector2 = points[index + 1] - points[index]
		var segment_length: float = segment.length()
		if segment_length < MIN_TRAVEL:
			continue
		if walked + segment_length >= half:
			return points[index] + segment.normalized() * (half - walked)
		walked += segment_length
	return points[points.size() - 1]


## Prompt an Interactable should show for the door's current state. Used by the
## built-in area and by external DoorSwitch mechanisms.
func get_interaction_prompt() -> String:
	if state == DoorState.CLOSED or state == DoorState.CLOSING:
		return data.prompt if data != null else "Open"
	return data.close_prompt if data != null else "Close"


func _on_interacted(_actor: Entity) -> void:
	toggle()


# --- Curve helpers ---

## Splits a polyline at half of its length. Returns one span when it cannot split.
func _split_at_half(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var spans: Array[PackedVector2Array] = []
	var total: float = DoorLeaf._polyline_length(points)
	if total <= MIN_TRAVEL or points.size() < MIN_POINTS:
		spans.append(points)
		return spans

	var half: float = total * 0.5
	var walked: float = 0.0
	var split_done: bool = false
	var first := PackedVector2Array([points[0]])
	var second := PackedVector2Array()
	var last: Vector2 = points[points.size() - 1]

	for index: int in range(points.size() - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var segment: Vector2 = b - a
		var segment_length: float = segment.length()
		if segment_length < MIN_TRAVEL:
			continue
		walked += segment_length
		if not split_done and walked >= half:
			var middle: Vector2 = b - segment.normalized() * (walked - half)
			first.append(middle)
			second.append(middle)
			split_done = true
			continue
		if split_done:
			second.append(b)
		else:
			first.append(b)

	if second.is_empty():
		second.append(last)
	if not second[second.size() - 1].is_equal_approx(last):
		second.append(last)
	if first.size() < MIN_POINTS:
		first.append(last)

	spans.append(first)
	spans.append(second)
	return spans


# --- Data helpers ---

func _kind() -> DoorData.Kind:
	return data.kind if data != null else DoorData.Kind.SINGLE


func _motion() -> DoorData.Motion:
	return data.motion if data != null else DoorData.Motion.SLIDE


func _open_angle_rad() -> float:
	return deg_to_rad(data.open_angle_degrees) if data != null else PI * 0.5


func _slide_ratio() -> float:
	return data.slide_ratio if data != null else 1.0


# --- Minimap ---

func _notify_minimap_changed() -> void:
	if not is_inside_tree():
		return
	get_tree().call_group(MINIMAP_GROUP, &"rebuild_geometry")


## Authored (closed) footprint in global pixels. Kept constant on purpose so the
## map always shows the doorway instead of the panels sliding across it.
func get_minimap_geometry() -> Array[MinimapGeometry]:
	var result: Array[MinimapGeometry] = []
	if curve == null:
		return result
	var local_points: PackedVector2Array = curve.get_baked_points()
	if local_points.size() < MIN_POINTS:
		return result
	var global_points := PackedVector2Array()
	global_points.resize(local_points.size())
	for index: int in range(local_points.size()):
		global_points[index] = global_transform * local_points[index]
	var geometry := MinimapGeometry.new()
	geometry.kind = MinimapGeometry.Kind.DOOR
	geometry.closed = (
		local_points[0].distance_to(local_points[local_points.size() - 1]) < 0.01
	)
	geometry.points = global_points
	result.append(geometry)
	return result
