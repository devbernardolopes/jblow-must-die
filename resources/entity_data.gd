@tool
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

@export_category("Combat")
## Hit points before the entity dies; damage is subtracted per hit.
@export var max_health: float = 100.0

@export_category("Visuals")
@export var animation_sets: Array[EntityAnimationSet] = []
## Set used when no weapon set matches, for example on CPU-only entities.
@export var default_animation_set_id: StringName = &"default"

@export_category("Sounds")
@export var sound_set: EntitySoundSet = null

func get_animation_set(set_id: StringName) -> EntityAnimationSet:
	for candidate: EntityAnimationSet in animation_sets:
		if candidate != null and candidate.id == set_id:
			return candidate
	return null
