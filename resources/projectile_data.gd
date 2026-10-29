@tool
class_name ProjectileData
extends Resource
## Everything a Projectile needs to fly, collide and disappear.

## Variants to pick from at spawn. (A single SpriteFrames can also hold several
## animations, e.g. "fly" and "impact", so the array is only for true variants.)
@export var sprite_frames: Array[SpriteFrames] = []
@export var animation: StringName = &"default"
## Optional animation played where the projectile dies; empty frees it at once.
@export var impact_animation: StringName = &""
## Drawn when sprite_frames is empty, so projectiles work before art arrives.
@export var placeholder_color: Color = Color(1.0, 0.85, 0.35)
@export var speed: float = 7000.0
@export var lifetime: float = 2.0
@export var radius: float = 8.0
## Fallback damage for projectiles spawned outside a weapon.
@export var damage: float = 1.0
@export var max_bounces: int = 0
@export var pierce: int = 0
@export var rotate_to_direction: bool = true
@export var scale_adjustment: float = 0.05
