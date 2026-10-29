class_name WeaponData
extends Resource

@export var name: StringName = &""
@export_enum("Melee", "Gun") var kind: String = "Melee"
@export var base_damage: float = 1.0
## Minimum time between attacks using this weapon 
@export var cooldown_period: float = 0.25
## How many projectiles this weapon can hold at a time (not applicable to melee) 
@export var ammo_amount: int = 0
