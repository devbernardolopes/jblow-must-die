class_name PlayerController
extends EntityController
## Reads the shared movement actions, so keyboard, gamepad, and touch all work.

## Cursor aim turns the entity while the mouse is moving in a relative mode.
@export var mouse_aim_enabled: bool = true

@onready var _entity: Entity = get_parent() as Entity

var _aim_pending: bool = false

func _input(event: InputEvent) -> void:
	if not mouse_aim_enabled or not _uses_cursor_aim():
		return
	var motion := event as InputEventMouseMotion
	if motion == null or motion.relative.is_zero_approx():
		return
	_aim_pending = true

## Both relative modes steer with the cursor; OMNI follows movement instead.
func _uses_cursor_aim() -> bool:
	return (
		movement_mode == MovementMode.RELATIVE
		or movement_mode == MovementMode.RELATIVE_MOUSE
	)

func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func get_move_intent() -> Vector2:
	var x: float = Input.get_axis("move_left", "move_right")
	var y: float = Input.get_axis("move_down", "move_up")
	return Vector2(x, y)

## Returns the world direction to the cursor once, then clears the request.
func consume_aim_direction() -> Vector2:
	var was_pending: bool = _aim_pending
	_aim_pending = false
	if not was_pending or not mouse_aim_enabled:
		return Vector2.ZERO
	if not _uses_cursor_aim():
		return Vector2.ZERO
	if _entity == null or not is_instance_valid(_entity) or not _entity.is_inside_tree():
		return Vector2.ZERO
	var offset: Vector2 = _entity.get_global_mouse_position() - _entity.global_position
	if offset.is_zero_approx():
		return Vector2.ZERO
	return offset.normalized()

func wants_run() -> bool:
	return Input.is_action_pressed("run")

func get_action_request() -> StringName:
	if Input.is_action_just_pressed("reload"):
		return _reload_action()
	if Input.is_action_just_pressed("action_02"):
		return _attack_action()
	if Input.is_action_just_pressed("action_01"):
		return &"melee_attack"
	return &""

func get_weapon_switch() -> int:
	if Input.is_action_just_pressed("next_weapon"):
		return 1
	if Input.is_action_just_pressed("previous_weapon"):
		return -1
	return 0

func _attack_action() -> StringName:
	if _entity == null or _entity.current_weapon == null:
		return &"melee_attack"
	return _entity.current_weapon.attack_action

func _reload_action() -> StringName:
	if _entity == null or _entity.current_weapon == null:
		return &""
	if not _entity.current_weapon.can_reload():
		return &""
	return _entity.current_weapon.reload_action
