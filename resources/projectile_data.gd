class_name ProjectileData
extends Resource

## Variants to pick from at spawn. (A single SpriteFrames can also hold several
## animations, e.g. "fly" and "impact", so the array is only for true variants.)
@export var sprite_frames: Array[SpriteFrames] = []
@export var animation: StringName = &"default"
@export var speed: float = 300.0
@export var lifetime: float = 2.0
@export var radius: float = 3.0
@export var damage: float = 1.0
@export var max_bounces: int = 0        # 1 = ricochets off walls once
@export var pierce: int = 0             # extra entities it passes through; -1 = infinite
@export var rotate_to_direction: bool = true
