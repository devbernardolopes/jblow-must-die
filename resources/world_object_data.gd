class_name WorldObjectData
extends Resource

@export var id: StringName = &""
@export var pickable: bool = false
@export var breakable: bool = false
@export var movable: bool = false
@export var obstacle: bool = false
@export var visual: Texture2D = null

@export_group("Height illusion")
## Front view of the sides, authored at the same pixel density as `visual`.
@export var side_texture: Texture2D = null
## Roughly object height / camera height. 0 turns the effect off.
@export_range(0.0, 0.5, 0.005) var height_factor: float = 0.0
@export var side_tint: Color = Color.WHITE
@export var side_mapping: HeightIllusion.SideMapping = HeightIllusion.SideMapping.TILED
@export var pixel_art: bool = false
