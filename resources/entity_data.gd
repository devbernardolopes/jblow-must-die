class_name EntityData
extends Resource

@export var walk_speed_mps: float = 12.5
@export var run_speed_mps: float = 35.5

@export_category("Abilities")
@export_range(0.00, 30.00) var strength: int = 10
@export_range(0.00, 30.00) var dexterity: int = 10
@export_range(0.00, 30.00) var constitution: int = 10
@export_range(0.00, 30.00) var intelligence: int = 10
@export_range(0.00, 30.00) var wisdom: int = 10
@export_range(0.00, 30.00) var charisma: int = 10

@export_category("Visuals")
@export var animation_set: Array[EntityAnimationSet] = []:
	set(v):
		animation_set = v

@export_category("Sounds")
@export var sound_set: EntitySoundSet = null

@export_category("Controls")
#@export var controller: EntityController = null
