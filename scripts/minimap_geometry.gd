@tool
class_name MinimapGeometry
extends RefCounted
## One drawable shape for the minimap, in global world pixels.
##
## Sources build these; the Minimap only draws them. Adding a Kind (plus a
## color export on the Minimap) is how a new map feature is introduced.

enum Kind {
	AREA,
	WALL,
	DOOR,
	POI,
}

var kind: Kind = Kind.AREA
var points: PackedVector2Array = PackedVector2Array()
var closed: bool = false
var filled: bool = false
## Color.TRANSPARENT means "use the Minimap's default color for this kind".
var color: Color = Color.TRANSPARENT

## Middle point, used as the fog-of-war probe for the whole shape.
func get_probe_point() -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	return points[(points.size() - 1) >> 1]
