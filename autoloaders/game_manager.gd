extends Node

#func _ready() -> void:
	#pass
#
#func _process(_delta: float) -> void:
	#pass

#func _shortcut_input(event: InputEvent) -> void:
	#pass
#
#func _unhandled_input(event: InputEvent) -> void:
	#pass
	
func _input(event: InputEvent) -> void:
	if event.is_action("menu"):
		## IMPORTANT: This doesn't work on iOS
		get_tree().quit()
