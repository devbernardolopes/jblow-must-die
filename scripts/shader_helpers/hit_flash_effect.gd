extends ColorRect

func _ready() -> void:
	var parent = get_parent()
	if parent:
		if parent.has_signal("damaged"):
			parent.damaged.connect(_on_damaged)

func _on_damaged(_amount: float, _source: Node) -> void:
	if material:
		if material.shader:
			material.set_shader_parameter("active", true)
			var tween = create_tween()
			tween.tween_property(material, "shader_parameter/tint", 0.0, 0.2)
			tween.play()
