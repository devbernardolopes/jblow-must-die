extends ColorRect

@export var target: Node2D = null

func _ready() -> void:
	if target:
		if target.has_signal("damaged"):
			target.damaged.connect(_on_damaged)

func _on_damaged(_amount: float, _source: Node) -> void:
	var tween = create_tween()
	tween.tween_property(material, "shader_parameter/intensity", 1.0, 0.1)
	tween.tween_property(material, "shader_parameter/intensity", 0.0, 0.2)
	tween.play()
