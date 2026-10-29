extends SceneTree
## Headless validation of the authored animation sets, weapons and projectiles.

var _failures: int = 0

func _init() -> void:
	var web_developer_ids: Array[StringName] = [
		&"handgun", &"knife", &"flashlight", &"rifle", &"shotgun"
	]
	_check_entity_data(
		"res://resources/entities/web_developer/web_developer.tres", web_developer_ids, &"handgun"
	)
	var zombie_ids: Array[StringName] = [&"hands"]
	_check_entity_data("res://resources/entities/zombies/zombie.tres", zombie_ids, &"hands")

	_check_weapon("res://resources/weapons/handgun_weapon.tres", &"shoot", true, true)
	_check_weapon("res://resources/weapons/rifle_weapon.tres", &"shoot", true, true)
	_check_weapon("res://resources/weapons/shotgun_weapon.tres", &"shoot", true, true)
	_check_weapon("res://resources/weapons/knife_weapon.tres", &"melee_attack", false, false)
	_check_weapon("res://resources/weapons/flashlight_weapon.tres", &"melee_attack", false, false)
	_check_weapon("res://resources/weapons/hands_weapon.tres", &"melee_attack", false, false)

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

	_check_action_triggers(animation_set)

func _check_action_triggers(animation_set: EntityAnimationSet) -> void:
	var set_id: StringName = animation_set.id
	if set_id == &"handgun" or set_id == &"rifle" or set_id == &"shotgun":
		var shoot := animation_set.get_explicit_action(&"shoot")
		_assert(
			shoot != null and shoot.trigger_frame == 1,
			"set '%s' shoot triggers on frame 1" % set_id
		)
		var reload := animation_set.get_explicit_action(&"reload")
		_assert(
			reload != null and reload.trigger_frame > 0,
			"set '%s' reload refills on a trigger frame" % set_id
		)
	if set_id == &"hands":
		var attack := animation_set.get_explicit_action(&"attack")
		_assert(
			attack != null and attack.trigger_frame == 4,
			"zombie attack triggers on frame 4"
		)

func _expected_actions(set_id: StringName) -> Array[StringName]:
	var actions: Array[StringName] = []
	match set_id:
		&"handgun", &"rifle", &"shotgun":
			actions = [&"shoot", &"reload", &"melee_attack"]
		&"knife", &"flashlight":
			actions = [&"melee_attack"]
		&"hands":
			actions = [&"attack"]
	return actions

func _check_weapon(
	path: String,
	expected_attack: StringName,
	expected_can_reload: bool,
	expected_can_shoot: bool
) -> void:
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
	_assert(
		weapon.can_shoot() == expected_can_shoot,
		"%s can_shoot is %s" % [path, expected_can_shoot]
	)
	if expected_can_shoot:
		_assert(weapon.projectile != null, "%s has a projectile" % path)
		_assert(weapon.projectile_count >= 1, "%s spawns at least one projectile" % path)
		_assert(
			not weapon.muzzle_offset.is_zero_approx(),
			"%s has a muzzle offset" % path
		)
	else:
		_assert(weapon.projectile == null, "%s is not projectile based" % path)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
