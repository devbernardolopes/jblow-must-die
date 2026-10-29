extends SceneTree
## Headless validation of the authored animation sets and weapons.

var _failures: int = 0

func _init() -> void:
	var web_developer_ids: Array[StringName] = [&"handgun", &"knife", &"flashlight"]
	_check_entity_data(
		"res://resources/entities/web_developer/web_developer.tres", web_developer_ids, &"handgun"
	)
	var zombie_ids: Array[StringName] = [&"main"]
	_check_entity_data("res://resources/entities/zombies/zombie.tres", zombie_ids, &"main")

	_check_weapon("res://resources/weapons/handgun_weapon.tres", &"shoot", true)
	_check_weapon("res://resources/weapons/knife_weapon.tres", &"melee_attack", false)
	_check_weapon("res://resources/weapons/flashlight_weapon.tres", &"melee_attack", false)
	_check_weapon("res://resources/weapons/hands_weapon.tres", &"melee_attack", false)

	if _failures == 0:
		print("Animation resource tests: PASS")
		quit(0)
	else:
		printerr("Animation resource tests: %d failure(s)" % _failures)
		quit(1)

func _check_entity_data(path: String, expected_ids: Array[StringName], default_id: StringName) -> void:
	var data := load(path) as EntityData
	_assert(data != null, "loads %s" % path)
	if data == null:
		return
	_assert(
		data.animation_sets.size() == expected_ids.size(),
		"%s has %d animation set(s)" % [path, expected_ids.size()]
	)
	for set_id: StringName in expected_ids:
		var animation_set: EntityAnimationSet = data.get_animation_set(set_id)
		_assert(animation_set != null, "%s has set '%s'" % [path, set_id])
		if animation_set != null:
			_check_set(animation_set)
	_assert(
		data.get_animation_set(default_id) != null,
		"%s has default set '%s'" % [path, default_id]
	)

func _check_set(animation_set: EntityAnimationSet) -> void:
	var frames: SpriteFrames = animation_set.sprite_frames
	_assert(frames != null, "set '%s' has SpriteFrames" % animation_set.id)
	if frames == null:
		return
	_assert(
		frames.has_animation(animation_set.idle_animation),
		"set '%s' has idle animation" % animation_set.id
	)
	_assert(
		frames.has_animation(animation_set.move_animation),
		"set '%s' has move animation" % animation_set.id
	)
	_assert(
		frames.get_animation_loop(animation_set.idle_animation),
		"set '%s' idle animation loops" % animation_set.id
	)
	_assert(
		frames.get_animation_loop(animation_set.move_animation),
		"set '%s' move animation loops" % animation_set.id
	)

	for action: EntityAnimationAction in animation_set.actions:
		_assert(
			frames.has_animation(action.animation),
			"set '%s' action '%s' has animation '%s'" % [
				animation_set.id, action.id, action.animation
			]
		)

	var sprite := AnimatedSprite2D.new()
	var animator := EntityAnimator.new()
	animator.bind(sprite)
	animator.apply_set(animation_set)
	for action_id: StringName in _expected_actions(animation_set.id):
		_assert(
			animator.request_action(action_id),
			"set '%s' resolves action '%s'" % [animation_set.id, action_id]
		)
		animator.cancel_action()
	sprite.free()

	if animation_set.id == &"handgun":
		var shoot := animation_set.get_explicit_action(&"shoot")
		_assert(shoot != null and shoot.trigger_frame == 1, "handgun shoot triggers on frame 1")
	if animation_set.id == &"main":
		var attack := animation_set.get_explicit_action(&"attack")
		_assert(attack != null and attack.trigger_frame == 4, "zombie attack triggers on frame 4")

func _expected_actions(set_id: StringName) -> Array[StringName]:
	var actions: Array[StringName] = []
	match set_id:
		&"handgun":
			actions = [&"shoot", &"reload", &"melee_attack"]
		&"knife", &"flashlight":
			actions = [&"melee_attack"]
		&"main":
			actions = [&"attack"]
	return actions

func _check_weapon(path: String, expected_attack: StringName, expected_can_reload: bool) -> void:
	var weapon := load(path) as WeaponData
	_assert(weapon != null, "loads %s" % path)
	if weapon == null:
		return
	_assert(
		weapon.attack_action == expected_attack,
		"%s attack action is '%s'" % [path, expected_attack]
	)
	_assert(
		weapon.can_reload() == expected_can_reload,
		"%s can_reload is %s" % [path, expected_can_reload]
	)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
