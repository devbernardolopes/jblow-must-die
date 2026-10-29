@tool
class_name Entity
extends CharacterBody2D

const TURN_RATE: float = 16.0
const COLLISION_RADIUS_M: float = 3.0
## How aligned the movement intent must be with the contact normal to push.
const PUSH_INTENT_DOT: float = 0.25
const PUSH_REJECT_INTERVAL_MS: int = 1500
## Ground friction that bleeds off momentum inherited from a moving vehicle, in m/s².
const INERTIA_DECELERATION_MPS2: float = 8.0
## Inherited speed above which the controller is ignored (the entity is staggered).
const INERTIA_CONTROL_SPEED_MPS: float = 1.0
const INERTIA_STOP_SPEED_MPS: float = 0.05

signal push_rejected(target: Node, required_strength: int)
signal action_triggered(action_id: StringName)

@export var data: EntityData = null:
	set(v):
		data = v
		_refresh_animation_set()

@export var speed_multiplier: float = 1.0

@export var frame_scale_multiplier: float = 1.0:
	set(v):
		frame_scale_multiplier = v
		if visual != null:
			visual.scale = Vector2.ONE * v

@export var collision_offset: Vector2 = Vector2.ZERO:
	set(v):
		collision_offset = v
		_configure_collision_shape()

@export var current_weapon: WeaponData = null:
	set(v):
		current_weapon = v
		_action_ready_msec.clear()
		_refresh_animation_set()

@export var available_weapons: Array[WeaponData] = []

var visual: AnimatedSprite2D = null
var animator: EntityAnimator = null
var collision: CollisionShape2D = null
var interaction: Area2D = null
var controller: EntityController = null

var facing: Vector2 = Vector2.RIGHT
## Frozen during screen transitions: velocity zero and the controller is not read.
var locked: bool = false
var _footstep_accumulated_m: float = 0.0
var _footstep_interval_m: float = 0.7
var _terrain_speed_factor: float = 1.0
#var _last_sample_pos_m: Vector2 = Vector2.ZERO
var _last_push_reject_target: Node = null
var _last_push_reject_msec: int = -PUSH_REJECT_INTERVAL_MS
## Momentum inherited from a moving vehicle, in m/s; decays with ground friction.
var _inertia_velocity_mps: Vector2 = Vector2.ZERO
var _action_ready_msec: Dictionary[StringName, int] = {}

func _ready() -> void:
	_refresh_animation_set()
	_configure_collision_shape()

	if not Engine.is_editor_hint():
		if controller == null:
			controller = _find_controller()
		if interaction == null:
			interaction = Area2D.new()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = PhysicsLayers.ENTITIES
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ENTITIES | PhysicsLayers.OBJECTS
	add_to_group(&"entities")

func _ensure_visual() -> void:
	if visual == null:
		visual = AnimatedSprite2D.new()
		add_child(visual)
	if animator == null:
		animator = EntityAnimator.new()
		animator.bind(visual)
		animator.action_triggered.connect(_on_animator_action_triggered)
	visual.scale = Vector2.ONE * frame_scale_multiplier

func _refresh_animation_set() -> void:
	_ensure_visual()
	animator.apply_set(_resolve_animation_set())

func _resolve_animation_set() -> EntityAnimationSet:
	if data == null or data.animation_sets.is_empty():
		return null
	if current_weapon != null:
		var weapon_set: EntityAnimationSet = data.get_animation_set(current_weapon.name)
		if weapon_set != null:
			return weapon_set
		push_warning("Entity has no animation set for weapon '%s'." % current_weapon.name)
		return null
	return data.get_animation_set(data.default_animation_set_id)

func _find_controller() -> EntityController:
	for child: Node in get_children():
		if child is EntityController:
			return child as EntityController
	return null

func set_controller(next_controller: EntityController) -> void:
	if controller == next_controller:
		return
	if controller != null:
		if controller.get_parent() == self:
			remove_child(controller)
		controller.queue_free()
	controller = next_controller
	if controller != null:
		if controller.get_parent() != null:
			controller.get_parent().remove_child(controller)
		add_child(controller)

func set_locked(value: bool) -> void:
	locked = value
	if locked:
		velocity = Vector2.ZERO
		_inertia_velocity_mps = Vector2.ZERO
		if animator != null:
			animator.cancel_action()

func get_speed_mps() -> float:
	return Units.px_to_m(velocity.length())

func get_velocity_mps() -> Vector2:
	return Units.to_m(velocity)

## Whether the controller is asking to run and the body is still under control.
func wants_run() -> bool:
	return controller != null and controller.wants_run() and not is_staggered()

## Attempts to start an animation action; returns whether it started.
func try_action(action_id: StringName) -> bool:
	if animator == null:
		return false
	var now: int = Time.get_ticks_msec()
	var ready_at: int = _action_ready_msec.get(action_id, 0)
	if now < ready_at:
		return false
	if not animator.request_action(action_id):
		return false
	var cooldown_s: float = 0.0
	if current_weapon != null and action_id == current_weapon.attack_action:
		cooldown_s = current_weapon.cooldown_period
	if cooldown_s > 0.0:
		_action_ready_msec[action_id] = now + int(ceilf(cooldown_s * 1000.0))
	return true

## Hook for spawning the weapon's projectile or hit effect.
func _fire() -> void:
	pass

func _on_animator_action_triggered(action_id: StringName) -> void:
	action_triggered.emit(action_id)
	if action_id == &"shoot":
		_fire()

## D&D ability score; average when the entity has no data resource.
func get_strength() -> int:
	return data.strength if data != null else 10

## Inherited momentum (world space, m/s) that decays with ground friction.
func apply_inertia(velocity_mps: Vector2) -> void:
	_inertia_velocity_mps = velocity_mps

## Momentum still being bled off; zero once the entity is fully under control.
func get_inertia_velocity_mps() -> Vector2:
	return _inertia_velocity_mps

## True while inherited momentum is high enough to override the controller.
func is_staggered() -> bool:
	return _inertia_velocity_mps.length() > INERTIA_CONTROL_SPEED_MPS

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if locked:
		velocity = Vector2.ZERO
		_inertia_velocity_mps = Vector2.ZERO
		move_and_slide()
		_tick_animator(delta, false)
		return
	if controller == null or data == null:
		velocity = Units.to_px(_inertia_velocity_mps)
		move_and_slide()
		_decay_inertia(delta)
		_tick_animator(delta, false)
		return
	_try_controller_action()
	_update_footstep(delta)
	var intent: Vector2 = _get_intent()
	var is_moving: bool = not is_staggered() and not intent.is_zero_approx()
	if animator != null and animator.locks_movement():
		intent = Vector2.ZERO
	var move_mode: EntityController.MovementMode = controller.movement_mode
	if move_mode == EntityController.MovementMode.RELATIVE:
		_resolve_relative(delta, intent)
	else:
		_resolve_omni(delta, intent)
	_decay_inertia(delta)
	_tick_animator(delta, is_moving)

func _tick_animator(delta: float, moving: bool) -> void:
	if animator != null:
		animator.tick(delta, moving)

func _try_controller_action() -> void:
	if controller == null:
		return
	var action_id: StringName = controller.get_action_request()
	if action_id.is_empty():
		return
	try_action(action_id)

func _get_intent() -> Vector2:
	if controller == null:
		return Vector2.ZERO
	if controller.movement_mode == EntityController.MovementMode.RELATIVE:
		return controller.get_move_intent()
	return controller.get_move_vector()

func _resolve_omni(delta: float, intent: Vector2) -> void:
	var move_vector: Vector2 = Vector2.ZERO
	if not is_staggered():
		move_vector = intent.limit_length(1.0)
	if move_vector != Vector2.ZERO:
		facing = move_vector.normalized()
		if visual != null:
			look_toward(facing, delta)
	var speed_mps: float = data.run_speed_mps if controller.wants_run() else data.walk_speed_mps
	velocity = (move_vector * Units.m_to_px(speed_mps * speed_multiplier * _terrain_speed_factor) + Units.to_px(_inertia_velocity_mps))
	move_and_slide()
	_push_contacts(move_vector)

func look_toward(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx():
		return
	facing = direction.normalized()
	rotation = lerp_angle(rotation, facing.angle(), minf(1.0, delta * TURN_RATE))

func _resolve_relative(delta: float, intent: Vector2) -> void:
	var move_intent: Vector2 = Vector2.ZERO
	if not is_staggered():
		move_intent = intent.limit_length(1.0)
	var turn_input: float = move_intent.x
	var throttle_input: float = move_intent.y
	if absf(turn_input) > 0.001:
		var turn_rate: float = controller.turn_rate_rad_s
		if turn_rate < 0.0:
			turn_rate = 0.0
		facing = facing.rotated(turn_input * turn_rate * delta)
	if visual != null and (absf(turn_input) > 0.001 or absf(throttle_input) > 0.001):
		look_toward(facing, delta)
	var speed_mps: float = data.run_speed_mps if controller.wants_run() else data.walk_speed_mps
	var move_speed_factor: float = 1.0
	if throttle_input < 0.0:
		var reverse_factor: float = controller.reverse_speed_factor
		if reverse_factor < 0.0:
			reverse_factor = 0.0
		move_speed_factor = reverse_factor
	var move_vector: Vector2 = facing * throttle_input
	velocity = ((move_vector * Units.m_to_px(speed_mps * speed_multiplier * _terrain_speed_factor * move_speed_factor)) + Units.to_px(_inertia_velocity_mps))
	move_and_slide()
	_push_contacts(move_vector)

## Bleeds off inherited momentum at ground-friction rate, so a body thrown from a
## moving vehicle is displaced by v²/(2a) before it comes to rest.
func _decay_inertia(delta: float) -> void:
	if _inertia_velocity_mps.is_zero_approx():
		return
	_inertia_velocity_mps = _inertia_velocity_mps.move_toward(Vector2.ZERO, INERTIA_DECELERATION_MPS2 * delta)
	if _inertia_velocity_mps.length() < INERTIA_STOP_SPEED_MPS:
		_inertia_velocity_mps = Vector2.ZERO

func _push_contacts(intent: Vector2) -> void:
	if data == null or intent.length_squared() <= 0.0001:
		return
	var intent_dir: Vector2 = intent.normalized()
	for index: int in range(get_slide_collision_count()):
		var _collision: KinematicCollision2D = get_slide_collision(index)
		if _collision == null:
			continue
		var into: Vector2 = -_collision.get_normal()
		if into.length_squared() <= 0.0001:
			continue
		into = into.normalized()
		if intent_dir.dot(into) < PUSH_INTENT_DOT:
			continue

## Emits push_rejected at most once per target per interval.
func _report_push_rejected(target: Node, required_strength: int) -> void:
	var now: int = Time.get_ticks_msec()
	if (target == _last_push_reject_target and now - _last_push_reject_msec < PUSH_REJECT_INTERVAL_MS):
		return
	_last_push_reject_target = target
	_last_push_reject_msec = now
	push_rejected.emit(target, required_strength)

## Tracks movement meters accumulated per frame for rhythmic footstep playback.
func _update_footstep(delta: float) -> void:
	var is_moving: bool = not velocity.is_zero_approx()
	if not is_moving:
		return
	var speed_mps: float = get_speed_mps()
	if speed_mps > 0.001:
		_footstep_accumulated_m += speed_mps * delta
		if _footstep_accumulated_m >= _footstep_interval_m:
			_footstep_accumulated_m -= _footstep_interval_m

func _configure_collision_shape() -> void:
	if collision == null:
		collision = CollisionShape2D.new()
		add_child(collision)

	var circle := collision.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		collision.shape = circle
	circle.radius = Units.m_to_px(COLLISION_RADIUS_M)
	collision.position = Vector2.ONE * collision_offset
	collision.debug_color = Color.from_hsv(0.4, 0.9, 0.3, 0.5)
