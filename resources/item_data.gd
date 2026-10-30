class_name ItemData
extends Resource

@export var id: StringName = &""
@export var name: String = ""
@export var consumable: bool = false

@export_category("Specifics")
@export var usable_on_weapons: Array[StringName] = []
## Used to know the amount of bullets this item holds (i.e. guns magazines)
@export var internal_amount: int = 0
