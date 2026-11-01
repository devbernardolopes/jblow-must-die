@tool
class_name FollowCamera
extends Camera2D
## Follows a target with a screen-space aim lead and a stable framing zoom.
##
## Speed does not change zoom by default: walking and running only move the
## camera. Optional sprint zoom is a slow state change, not a speed curve, so
## alternating walk/run/stop does not pump the world scale.

enum Mode {
	## Player-controlled zoom with the wheel and zoom actions.
	MANUAL,
	## Game-controlled zoom and look-ahead; all zoom input is ignored.
	AUTO,
}

const ZOOM_STEP: float = 1.15
const MIN_ZOOM: float = 0.20
const MAX_ZOOM: float = 2.0
const DEFAULT_LIMIT_PX: int = 10000000

@export var target: Node2D = null:
	set(v):
		if target == v:
			return
		_unbind_target()
		target = v
		_bind_target()
		if not Engine.is_editor_hint():
			snap_to_target()

## Zoom used by MANUAL mode and as the starting point when the camera enters
## the tree. AUTO mode eases to `base_zoom` instead.
@export var default_zoom: float = 0.40
@export var mode: Mode = Mode.AUTO

@export_group("Auto mode")
## Framing zoom. The target stays near the centre; this is the resting scale.
@export var base_zoom: float = 0.40
## Optional slow zoom-out while running. Off by default because continuous
## scale changes fight aiming and are uncomfortable during walk/run bursts.
@export var sprint_zoom_enabled: bool = false
@export var sprint_zoom: float = 0.38
## How long the target must keep running before the sprint zoom engages.
@export var sprint_hold_s: float = 0.6
## How long the sprint zoom holds after the run stops, so short stops do not
## immediately contract the view.
@export var sprint_release_s: float = 0.8
@export var sprint_min_speed_mps: float = 0.5

@export_group("Framing")
## Screen-space lead toward the target's facing. The entity keeps facing when
## it stops, so the lead does not collapse while the player is aiming.
@export var aim_lead_px: float = 44.0
## Extra screen-space lead in the direction of travel. A secondary term, so
## backpedalling still keeps the camera biased toward the aim direction.
@export var move_lead_px: float = 24.0
## Hard cap for the combined lead, expressed in screen pixels.
@export var max_lead_px: float = 64.0
## Response used when the lead grows or turns; fast enough to anticipate aim.
@export var lead_attack_response: float = 6.0
## Response used when the lead shrinks; slower so the camera settles instead
## of snapping back when the player stops.
@export var lead_release_response: float = 1.7
@export var lead_snap_px: float = 0.5
## Zoom smoothing response. The exponential is snapped once it is within
## `zoom_snap`, so the camera reaches an exact scale instead of creeping.
@export var zoom_response: float = 1.5
@export var zoom_snap: float = 0.001
## Fallback run speed for targets that are not entities.
@export var move_lead_reference_mps: float = 30.0

@export_group("Shake")
@export var shake_enabled: bool = true
## Trauma added by an attack action, damage and death. Offset is trauma².
@export var attack_shake: float = 0.35
@export var damage_shake: float = 0.6
@export var death_shake: float = 0.9
@export var max_shake_offset_px: float = 7.0
@export var shake_decay_per_s: float = 1.5
@export var shake_frequency: float = 18.0

var _manual_zoom: float = 0.40
var _zoom: float = 0.40
var _lead_m: Vector2 = Vector2.ZERO
var _bound_entity: Entity = null
var _sprint_active: bool = false
var _sprint_hold_s: float = 0.0
var _sprint_release_s: float = 0.0
var _trauma: float = 0.0
var _shake_time_s: float = 0.0
var _shake_offset_px: Vector2 = Vector2.ZERO
var _shake_noise: FastNoiseLite = FastNoiseLite.new()

func _init() -> void:
	_shake_noise.frequency = 1.0

func _ready() -> void:
	add_to_group(&"wall_viewer")
	add_to_group(&"door_viewer")

	if Engine.is_editor_hint():
		return

	visible = true
	enabled = true
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	# The follow position is written manually on the physics clock. Leaving
	# Camera2D smoothing on would smooth it a second time and make the target
	# drift behind the screen centre.
	position_smoothing_enabled = false
	process_physics_priority = 100

	_zoom = default_zoom if mode == Mode.MANUAL else _base_zoom()
	_manual_zoom = _zoom
	zoom = Vector2.ONE * _zoom
	_bind_target()
	snap_to_target()

func _exit_tree() -> void:
	_unbind_target()

func snap_to_target() -> void:
	if Engine.is_editor_hint():
		return
	if target == null or not is_instance_valid(target):
		return
	_lead_m = Vector2.ZERO
	_trauma = 0.0
	_shake_offset_px = Vector2.ZERO
	global_position = target.global_position
	reset_smoothing()

func set_mode(value: Mode) -> void:
	if mode == value:
		return
	if mode == Mode.MANUAL:
		_manual_zoom = _zoom
	mode = value
	if mode == Mode.MANUAL:
		_lead_m = Vector2.ZERO
		_zoom = _manual_zoom
		zoom = Vector2.ONE * _zoom

## Restricts the camera to a rectangle given in global meters.
func set_limits_m(rect_m: Rect2) -> void:
	var top_left: Vector2 = Units.to_px(rect_m.position)
	var bottom_right: Vector2 = Units.to_px(rect_m.position + rect_m.size)
	limit_left = roundi(top_left.x)
	limit_top = roundi(top_left.y)
	limit_right = roundi(bottom_right.x)
	limit_bottom = roundi(bottom_right.y)

func clear_limits() -> void:
	limit_left = -DEFAULT_LIMIT_PX
	limit_top = -DEFAULT_LIMIT_PX
	limit_right = DEFAULT_LIMIT_PX
	limit_bottom = DEFAULT_LIMIT_PX

## Adds trauma to the camera shake. `amount` is clamped into 0..1.
func shake(amount: float) -> void:
	if not shake_enabled:
		return
	_trauma = clampf(_trauma + maxf(amount, 0.0), 0.0, 1.0)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_follow(delta)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_current():
		return
	if mode != Mode.MANUAL:
		return
	if Input.is_action_just_pressed("zoom_in"):
		_zoom_by(ZOOM_STEP)
	if Input.is_action_just_pressed("zoom_out"):
		_zoom_by(1.0 / ZOOM_STEP)

func _update_follow(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	if mode == Mode.AUTO:
		_update_sprint(delta)
		_zoom = _smooth_scalar(_zoom, _desired_zoom(), zoom_response, delta, zoom_snap)
		var next_zoom: Vector2 = Vector2.ONE * _zoom
		if not zoom.is_equal_approx(next_zoom):
			zoom = next_zoom

	var lead_goal: Vector2 = _desired_lead_m() if mode == Mode.AUTO else Vector2.ZERO
	var lead_response: float = lead_attack_response
	if lead_goal.length() < _lead_m.length():
		lead_response = lead_release_response
	_lead_m = _smooth_vector(_lead_m, lead_goal, lead_response, delta)

	_update_shake(delta)
	var shake_world_px: Vector2 = _shake_offset_px / maxf(zoom.x, 0.001)
	global_position = target.global_position + Units.to_px(_lead_m) + shake_world_px

func _desired_zoom() -> float:
	var value: float = sprint_zoom if _sprint_active else base_zoom
	return clampf(value, MIN_ZOOM, MAX_ZOOM)

func _base_zoom() -> float:
	return clampf(base_zoom, MIN_ZOOM, MAX_ZOOM)

## The lead is authored in screen pixels so its apparent size is stable across
## zoom levels. Even a fully zoomed-out camera keeps the target near centre.
func _desired_lead_m() -> Vector2:
	var velocity_mps: Vector2 = _target_velocity_mps()
	var speed_mps: float = velocity_mps.length()
	var speed_ratio: float = clampf(speed_mps / maxf(_target_reference_speed_mps(), 0.1), 0.0, 1.0)
	var move_direction: Vector2 = velocity_mps / speed_mps if speed_mps > 0.001 else Vector2.ZERO
	var lead_px: Vector2 = (
		_target_aim_direction() * aim_lead_px
		+ move_direction * move_lead_px * speed_ratio
	)
	if lead_px.length() > max_lead_px:
		lead_px = lead_px.normalized() * max_lead_px
	return lead_px / maxf(zoom.x * Units.PX_PER_METER, 0.001)

func _target_aim_direction() -> Vector2:
	var entity: Entity = target as Entity
	if entity == null or entity.facing.is_zero_approx():
		return Vector2.ZERO
	return entity.facing.normalized()

func _target_velocity_mps() -> Vector2:
	var entity: Entity = target as Entity
	if entity == null:
		return Vector2.ZERO
	return entity.get_velocity_mps()

func _target_reference_speed_mps() -> float:
	var entity: Entity = target as Entity
	if entity != null and entity.data != null:
		return maxf(entity.data.run_speed_mps * absf(entity.speed_multiplier), 0.1)
	return maxf(move_lead_reference_mps, 0.1)

func _update_sprint(delta: float) -> void:
	if not sprint_zoom_enabled:
		_sprint_active = false
		_sprint_hold_s = 0.0
		_sprint_release_s = 0.0
		return

	var entity: Entity = target as Entity
	var is_running: bool = false
	if entity != null:
		is_running = entity.wants_run() and entity.get_speed_mps() > sprint_min_speed_mps
	else:
		is_running = _target_velocity_mps().length() > sprint_min_speed_mps

	if is_running:
		_sprint_release_s = 0.0
		_sprint_hold_s = minf(_sprint_hold_s + delta, sprint_hold_s)
		if _sprint_hold_s >= sprint_hold_s:
			_sprint_active = true
		return

	_sprint_hold_s = 0.0
	if not _sprint_active:
		return
	_sprint_release_s += delta
	if _sprint_release_s >= sprint_release_s:
		_sprint_active = false

func _smooth_scalar(current: float, goal: float, response: float, delta: float, snap: float) -> float:
	var next: float = lerpf(current, goal, 1.0 - exp(-maxf(response, 0.01) * delta))
	return goal if absf(next - goal) <= snap else next

func _smooth_vector(current: Vector2, goal: Vector2, response: float, delta: float) -> Vector2:
	var factor: float = 1.0 - exp(-maxf(response, 0.01) * delta)
	var next: Vector2 = current.lerp(goal, factor)
	var remaining_px: float = Units.to_px(next - goal).length() * zoom.x
	return goal if remaining_px <= lead_snap_px else next

func _update_shake(delta: float) -> void:
	if not shake_enabled:
		_trauma = 0.0
		_shake_offset_px = Vector2.ZERO
		return

	_shake_time_s += delta * maxf(shake_frequency, 0.1)
	_trauma = maxf(_trauma - maxf(shake_decay_per_s, 0.0) * delta, 0.0)
	if _trauma <= 0.0001:
		_shake_offset_px = Vector2.ZERO
		return

	var strength: float = _trauma * _trauma
	_shake_offset_px = Vector2(
		_shake_noise.get_noise_2d(_shake_time_s, 0.0),
		_shake_noise.get_noise_2d(0.0, _shake_time_s + 100.0)
	) * max_shake_offset_px * strength

func _bind_target() -> void:
	if Engine.is_editor_hint():
		return
	var entity: Entity = target as Entity
	if entity == _bound_entity:
		return
	_unbind_target()
	_bound_entity = entity
	if entity == null:
		return
	if not entity.action_triggered.is_connected(_on_target_action_triggered):
		entity.action_triggered.connect(_on_target_action_triggered)
	if not entity.damaged.is_connected(_on_target_damaged):
		entity.damaged.connect(_on_target_damaged)
	if not entity.died.is_connected(_on_target_died):
		entity.died.connect(_on_target_died)

func _unbind_target() -> void:
	if _bound_entity == null:
		return
	if is_instance_valid(_bound_entity):
		if _bound_entity.action_triggered.is_connected(_on_target_action_triggered):
			_bound_entity.action_triggered.disconnect(_on_target_action_triggered)
		if _bound_entity.damaged.is_connected(_on_target_damaged):
			_bound_entity.damaged.disconnect(_on_target_damaged)
		if _bound_entity.died.is_connected(_on_target_died):
			_bound_entity.died.disconnect(_on_target_died)
	_bound_entity = null

func _on_target_action_triggered(action_id: StringName) -> void:
	if _bound_entity == null or _bound_entity.current_weapon == null:
		return
	if action_id == _bound_entity.current_weapon.attack_action:
		shake(attack_shake)

func _on_target_damaged(_amount: float, _source: Node) -> void:
	shake(damage_shake)

func _on_target_died(_source: Node) -> void:
	shake(death_shake)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_current() or mode != Mode.MANUAL:
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed:
		return
	if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_by(ZOOM_STEP)
		get_viewport().set_input_as_handled()
	elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_by(1.0 / ZOOM_STEP)
		get_viewport().set_input_as_handled()

func _zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_manual_zoom = _zoom
	zoom = Vector2.ONE * _zoom

func _is_current() -> bool:
	return get_viewport().get_camera_2d() == self
