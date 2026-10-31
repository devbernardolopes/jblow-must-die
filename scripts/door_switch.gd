class_name DoorSwitch
extends Interactable
## A fixed interaction point that drives a Door somewhere else.
##
## Use it for a panel beside a door or a lever down the corridor: author the
## switch anywhere in the world and point it at the door. Unlike the door's
## built-in area, it has no relationship with the door's transform, so it never
## follows the moving panels.

@export var door: Door = null:
	set(value):
		if (
			door != null
			and is_instance_valid(door)
			and door.state_changed.is_connected(_on_door_state_changed)
		):
			door.state_changed.disconnect(_on_door_state_changed)
		door = value
		if (
			is_inside_tree()
			and door != null
			and not door.state_changed.is_connected(_on_door_state_changed)
		):
			door.state_changed.connect(_on_door_state_changed)
		_refresh_prompt()


func _ready() -> void:
	super()
	if not interacted.is_connected(_on_interacted):
		interacted.connect(_on_interacted)
	if door != null and not door.state_changed.is_connected(_on_door_state_changed):
		door.state_changed.connect(_on_door_state_changed)
	_refresh_prompt()


func _on_interacted(_actor: Entity) -> void:
	if door != null:
		door.toggle()


func _on_door_state_changed(_new_state: Door.DoorState) -> void:
	_refresh_prompt()


func _refresh_prompt() -> void:
	if door == null:
		return
	prompt_text = door.get_interaction_prompt()
