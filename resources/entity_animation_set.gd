@tool
class_name EntityAnimationSet
extends Resource
## Sprite bank plus the action definitions for one visual mode (usually a weapon).

## Stable key. Weapons use their WeaponData.name; CPU-only sets use
## EntityData.default_animation_set_id.
@export var id: StringName = &"default"
@export var sprite_frames: SpriteFrames = null

@export_group("Locomotion")
@export var idle_animation: StringName = &"idle"
@export var move_animation: StringName = &"move"

@export_group("Actions")
## Optional flags/overrides. Every other animation in sprite_frames is
## registered as an action automatically.
@export var actions: Array[EntityAnimationAction] = []

## Explicit action definition, if one was authored for this id.
func get_explicit_action(action_id: StringName) -> EntityAnimationAction:
	for action: EntityAnimationAction in actions:
		if action != null and action.id == action_id:
			return action
	return null
