@tool
class_name WeaponData
extends Resource

@export var name: StringName = &""
@export_enum("Melee", "Gun") var kind: String = "Melee"
@export var base_damage: float = 1.0
## Minimum time between attacks using this weapon 
@export var cooldown_period: float = 0.25
## How many projectiles this weapon can hold at a time (not applicable to melee) 
@export var ammo_amount: int = 0

@export_category("Animation actions")
## Action id resolved against the equipped animation set when attacking.
@export var attack_action: StringName = &"melee_attack"
## Action id resolved against the equipped animation set when reloading.
@export var reload_action: StringName = &"reload"

func can_reload() -> bool:
	return kind == "Gun" and not reload_action.is_empty()
