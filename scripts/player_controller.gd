class_name PlayerController
extends EntityController
## Reads the shared movement actions, so keyboard, gamepad, and touch all work.

@onready var _entity: Entity = get_parent() as Entity

func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func get_move_intent() -> Vector2:
	var x: float = Input.get_axis("move_left", "move_right")
	var y: float = Input.get_axis("move_down", "move_up")
	return Vector2(x, y)

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
