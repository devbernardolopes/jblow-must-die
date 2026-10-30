@tool
class_name WeaponData
extends Resource

@export var name: StringName = &""
@export_enum("Melee", "Gun") var kind: String = "Melee"
@export var base_damage: float = 1.0
## Minimum time between attacks using this weapon
@export var cooldown_period: float = 0.25
## Magazine capacity for guns; 0 means unlimited.
@export var ammo_amount: int = 0
@export var hotkey: StringName = &""
@export var sort_order: int = 0

@export_category("Projectiles")
## Projectile spawned by guns; ignored by melee weapons.
@export var projectile: ProjectileData = null
## Projectiles spawned by one shot, for example shotgun pellets.
@export_range(1, 32) var projectile_count: int = 1
## Total spread of the projectile fan in degrees; 0 fires straight ahead.
@export_range(0.0, 180.0) var spread_degrees: float = 0.0
## Muzzle position in sprite pixels, relative to the entity origin.
@export var muzzle_offset: Vector2 = Vector2.ZERO
@export var red_dot_enabled: bool = false
@export var spent_shell: Texture2D = null

@export_category("Animation actions")
## Action id resolved against the equipped animation set when attacking.
@export var attack_action: StringName = &"melee_attack"
## Action id resolved against the equipped animation set when reloading.
@export var reload_action: StringName = &"reload"
@export var play_reload_for_each_bullet: bool = false

@export_category("Sounds")
@export var shoot_stream: AudioStream = null
@export var reload_stream: AudioStream = null
@export var dry_stream: AudioStream = null

func can_shoot() -> bool:
	return kind == "Gun" and projectile != null

func can_reload() -> bool:
	return kind == "Gun" and ammo_amount > 0 and not reload_action.is_empty()

## Damage of a single projectile; the weapon's base_damage is per shot.
func get_projectile_damage() -> float:
	if projectile_count <= 0:
		return base_damage
	return base_damage / float(projectile_count)
