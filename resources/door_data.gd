class_name DoorData
extends Resource

enum KIND { SINGLE, DOUBLE }

@export var id: StringName = &""
@export var kind: KIND =  KIND.SINGLE 
@export var automatic: bool = false
@export var unlocks_with: Array[ItemData] = []
@export var visual: SpriteFrames = null
