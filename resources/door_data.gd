@tool
class_name DoorData
extends Resource
## Shared description of a door type. Per-instance placement lives on the Door
## node (hinge end, slide direction, swing side), because it depends on the level.

enum Kind {
	SINGLE,
	DOUBLE,
}

enum Motion {
	SLIDE,
	SWING,
}

@export var id: StringName = &""
@export var kind: Kind = Kind.SINGLE
@export var motion: Motion = Motion.SLIDE

@export_group("Interaction")
## Prompt while the door is closed or closing.
@export var prompt: String = "Open"
## Prompt while the door is open or opening.
@export var close_prompt: String = "Close"
## Opens by itself when an entity approaches. Not implemented yet.
@export var automatic: bool = false
## Items that unlock the door. Empty means it is never locked.
@export var unlocks_with: Array[ItemData] = []

@export_group("Motion")
## Swing doors only. Sign picks the side of the wall; the Door can flip it.
@export_range(-170.0, 170.0, 1.0) var open_angle_degrees: float = 90.0
## Slide doors only. Fraction of the panel length to travel; 1.0 clears the opening.
@export_range(0.0, 2.0, 0.01) var slide_ratio: float = 1.0
