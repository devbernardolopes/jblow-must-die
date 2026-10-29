@tool
class_name EntityAnimationAction
extends Resource
## One one-shot action played by an EntityAnimator (shoot, reload, melee, ...).

## Gameplay id used by controllers and weapons.
@export var id: StringName = &"attack"
## Animation name inside the owning EntityAnimationSet's SpriteFrames.
@export var animation: StringName = &"attack"
## Movement input is ignored while this action plays.
@export var locks_movement: bool = true
## Higher priority actions may interrupt lower priority ones.
@export_range(0, 10) var priority: int = 1
## Frame that emits action_triggered; -1 disables the trigger.
@export var trigger_frame: int = -1
