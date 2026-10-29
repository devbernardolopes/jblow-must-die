class_name Hud
extends CanvasLayer
## Shows map counts, attribution, the clock and weather line, the player state, and pick reports.

const FONT_REFERENCE_HEIGHT: float = 42.0
const MIN_FONT_SIZE: int = 14
const MAX_FONT_SIZE: int = 64
const INFO_FONT_SCALE: float = 0.8

@export var target: Entity = null

@export_category("Big Font")
@export var big_font: Font = null
@export var big_font_color: Color = Color.WHITE
@export var big_font_size: Color = Color.WHITE

@export_category("Regular Font")
@export var regular_font: Font = null
@export var regular_font_color: Color = Color.WHITE

@onready var ammo_count: Label = $HBoxContainer/AmmoCount

func _ready() -> void:
	var minimap_node := get_node_or_null(^"Minimap") as Minimap
	if minimap_node != null:
		minimap_node.target = target
	var labels = find_children("*")
	if labels and not labels.is_empty():
		for i in labels.size():
			if labels[i] is Label:
				var label: Label = labels[i] 
				if big_font:
					label.add_theme_font_override("font", big_font)
				label.add_theme_color_override("font_color", big_font_color)
				#label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.85))
	get_viewport().size_changed.connect(_update_font_size)
	_update_font_size()
	await get_tree().process_frame

func _process(_delta: float) -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		target = null
		return
	if ammo_count:
		ammo_count.text = "0"
		ammo_count.text = "%d" % target.get_ammo(target.current_weapon) # TODO: VERY IMPORTANT! Change this to subscribe to some signal or something so it updates in real time

func _update_font_size() -> void:
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var font_size: int = int(clampf(viewport_height / FONT_REFERENCE_HEIGHT, float(MIN_FONT_SIZE), float(MAX_FONT_SIZE)))
	var labels = find_children("*")
	if labels and not labels.is_empty():
		for i in labels.size():
			if labels[i] is Label:
				var label: Label = labels[i] 
				label.add_theme_font_size_override("font_size", font_size)
				#label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.12)))
