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

@export var data: EntityData = null:
	set(v):
		data = v
		setup_visual()

@export var current_animation: StringName = &"idle":
	set(v):
		current_animation = v
		setup_visual()

@export var speed_multiplier: float = 1.0

@export var frame_scale_multiplier: float = 1.0:
	set(v):
		frame_scale_multiplier = v
		setup_visual()

@export var collision_offset: Vector2 = Vector2.ZERO:
	set(v):
		collision_offset = v
		_configure_collision_shape()

@export var current_weapon: WeaponData = null

var visual: AnimatedSprite2D = null
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

func setup_visual() -> void:
	if not visual:
		visual = AnimatedSprite2D.new()
		add_child(visual)
	if data and data.animation_set and not data.animation_set.is_empty():
		visual.sprite_frames = data.animation_set[0].sprite_frames
		visual.scale = Vector2.ONE * frame_scale_multiplier
		if visual.sprite_frames.has_animation(current_animation):
			visual.play(current_animation)
		#else:
			#current_animation = &"idle"

func _ready() -> void:
	setup_visual()
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

func get_speed_mps() -> float:
	return Units.px_to_m(velocity.length())

func get_velocity_mps() -> Vector2:
	return Units.to_m(velocity)

## Whether the controller is asking to run and the body is still under control.
func wants_run() -> bool:
	return controller != null and controller.wants_run() and not is_staggered()

func wants_attack() -> bool:
	return controller != null and controller.wants_attack() and not is_staggered()

func _fire() -> void:
	pass
	#var dir := (aim_target - muzzle.global_position).normalized()
	#Projectile.spawn(current_weapon.projectile, muzzle.global_position, facing, self)

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
	if not Engine.is_editor_hint():
		if locked:
			velocity = Vector2.ZERO
			_inertia_velocity_mps = Vector2.ZERO
			move_and_slide()
			return
		if controller == null or data == null:
			velocity = Units.to_px(_inertia_velocity_mps)
			move_and_slide()
			_decay_inertia(delta)
			return
		#_update_terrain(delta)
		_update_footstep(delta)
		var move_mode: EntityController.MovementMode = controller.movement_mode
		if move_mode == EntityController.MovementMode.RELATIVE:
			_resolve_relative(delta)
		else:
			_resolve_omni(delta)
		_decay_inertia(delta)

func _resolve_omni(delta: float) -> void:
	var move_vector: Vector2 = Vector2.ZERO
	if not is_staggered():
		move_vector = controller.get_move_vector().limit_length(1.0)
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
	
func _resolve_relative(delta: float) -> void:
	var intent: Vector2 = Vector2.ZERO
	if not is_staggered():
		intent = controller.get_move_intent().limit_length(1.0)
	var turn_input: float = intent.x
	var throttle_input: float = intent.y
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
	#var throttle_magnitude: float = absf(throttle_input)
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
			#if data != null and data.sound_set != null and data.sound_set.footstep_stream != null:
				#AudioManager.play_at(global_position / Units.PX_PER_METER, data.sound_set.footstep_stream)

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
