class_name EntityController
extends Node
## Base class for entity behavior. Subclasses provide movement intent and action requests.

enum MovementMode {
	## Screen-space eight-way movement; facing follows the movement direction.
	OMNI,
	## W/S throttle along the facing direction and A/D turn the entity.
	RELATIVE,
	## W/S throttle along facing, A/D strafe sideways, and the cursor sets facing.
	RELATIVE_MOUSE,
}

@export var movement_mode: MovementMode = MovementMode.OMNI
## Rotation speed in radians per second when in RELATIVE movement mode.
@export var turn_rate_rad_s: float = PI
## Speed factor applied when moving backwards in a relative movement mode.
@export var reverse_speed_factor: float = 0.5

## Called once per physics tick by the owning Entity, before intent is read.
## AI brains update their behavior tree here so decisions and intent share a tick.
func tick(_delta: float) -> void:
	pass

func get_move_vector() -> Vector2:
	return Vector2.ZERO

func get_move_intent() -> Vector2:
	return get_move_vector()

func wants_run() -> bool:
	return false

## Action id to try this frame, or &"" for none.
func get_action_request() -> StringName:
	return &""

## World-space direction the controller wants the entity to face this frame.
## Vector2.ZERO means "no cursor aim"; keyboard/analog turning still applies.
func consume_aim_direction() -> Vector2:
	return Vector2.ZERO

## -1 selects the previous weapon, +1 the next one, 0 leaves it alone.
func get_weapon_switch() -> int:
	return 0
