@tool
class_name MinimapVisibility
extends Resource
## Fog-of-war seam for the minimap.
##
## The base resource reveals everything. A future fog implementation overrides
## these methods and is assigned to Minimap.visibility; the renderer never
## changes. Keep the two concepts separate:
##
## - is_explored is persistent: walls, areas and doors stay on the map once found.
## - is_visible_now is transient: other entities only show while in view.

func is_explored(_world_position: Vector2) -> bool:
	return true


func is_visible_now(_world_position: Vector2) -> bool:
	return true
