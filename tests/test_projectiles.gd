extends SceneTree
## Headless checks for muzzle spawning, pellet spread, damage and team. No gameplay scene.

var _failures: int = 0

class FakeTarget extends Node2D:
	var team: StringName = &"enemy"
	var damage_taken: float = 0.0

	func take_damage(amount: float, _source: Node) -> void:
		damage_taken += amount

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	_test_shotgun()
	_test_handgun()
	_test_missing_art_placeholder()
	_test_rifle_and_damage()
	if _failures == 0:
		print("Projectile tests: PASS")
		quit(0)
	else:
		printerr("Projectile tests: %d failure(s)" % _failures)
		quit(1)

func _test_shotgun() -> void:
	var entity := _make_entity(&"shotgun")
	var container: Node2D = _make_container()
	var start_ammo: int = entity.get_ammo(entity.current_weapon)
	entity._fire()

	_assert(container.get_child_count() == 8, "shotgun spawns 8 pellets")
	_assert(entity.get_ammo(entity.current_weapon) == start_ammo - 1, "one shot uses one round")
	var min_angle: float = INF
	var max_angle: float = -INF
	for child: Node in container.get_children():
		var projectile := child as Projectile
		_assert(projectile != null, "spawned child is a projectile")
		if projectile == null:
			continue
		_assert(projectile.team == &"player", "projectile inherits the shooter's team")
		_assert(
			is_equal_approx(projectile.damage, 2.5),
			"shotgun damage is split across the pellets"
		)
		_assert(
			is_equal_approx(projectile.velocity.length(), 4500.0),
			"pellet uses the projectile speed"
		)
		_assert(
			projectile.global_position.distance_to(Vector2(233, 148)) < 0.01,
			"projectile starts at the weapon muzzle"
		)
		_assert(projectile.sprite.visible, "projectile shows its authored sprite")
		var angle: float = projectile.velocity.angle()
		min_angle = minf(min_angle, angle)
		max_angle = maxf(max_angle, angle)
	_assert(
		absf((max_angle - min_angle) - deg_to_rad(22.0)) < 0.01,
		"pellet fan covers the configured spread"
	)
	_assert(
		min_angle >= -deg_to_rad(11.0) - 0.01 and max_angle <= deg_to_rad(11.0) + 0.01,
		"pellet fan is centered on the muzzle direction"
	)

	for _index: int in range(5):
		entity._consume_ammo(entity.current_weapon)
	_assert(entity.is_out_of_ammo(entity.current_weapon), "shotgun is empty")
	_assert(entity.try_action(&"shoot"), "empty shotgun plays the dry-fire animation")
	_assert(not entity.animator.locks_movement(), "dry fire does not lock movement")
	_assert(container.get_child_count() == 8, "empty shotgun spawns nothing")
	entity.animator.cancel_action()

	container.free()
	entity.free()

func _test_handgun() -> void:
	var entity := _make_entity(&"handgun")
	var container: Node2D = _make_container()
	entity._fire()
	_assert(container.get_child_count() == 1, "handgun spawns one projectile")
	var projectile := container.get_child(0) as Projectile
	_assert(projectile != null, "handgun projectile exists")
	if projectile != null:
		_assert(is_equal_approx(projectile.damage, 10.0), "handgun deals its full damage")
		_assert(
			is_equal_approx(projectile.velocity.length(), 7000.0),
			"handgun uses its projectile speed"
		)
		var circle := projectile.wall_shape.shape as CircleShape2D
		_assert(
			circle != null and is_equal_approx(circle.radius, 8.0),
			"collision radius comes from the projectile data"
		)
	container.free()
	entity.free()

func _test_missing_art_placeholder() -> void:
	var entity := Entity.new()
	entity.data = load("res://resources/entities/web_developer/web_developer.tres") as EntityData
	entity.team = &"player"
	var weapon := load("res://resources/weapons/handgun_weapon.tres").duplicate() as WeaponData
	var placeholder := (weapon.projectile as ProjectileData).duplicate() as ProjectileData
	placeholder.sprite_frames.clear()
	placeholder.radius = 3.0
	weapon.projectile = placeholder
	entity.current_weapon = weapon
	entity.position = Vector2(100, 100)
	entity.rotation = 0.0
	root.add_child(entity)
	entity._refresh_muzzle()
	var container: Node2D = _make_container()
	entity._fire()

	_assert(container.get_child_count() == 1, "placeholder shot spawns one projectile")
	var projectile := container.get_child(0) as Projectile
	_assert(
		projectile != null and not projectile.sprite.visible,
		"missing art keeps the sprite hidden"
	)
	if projectile != null:
		var circle := projectile.wall_shape.shape as CircleShape2D
		_assert(
			circle != null and is_equal_approx(circle.radius, 3.0),
			"placeholder uses the projectile radius"
		)
	container.free()
	entity.free()

func _test_rifle_and_damage() -> void:
	var entity := _make_entity(&"rifle")
	var container: Node2D = _make_container()
	entity._fire()
	_assert(container.get_child_count() == 1, "rifle spawns one projectile")
	var projectile := container.get_child(0) as Projectile
	_assert(projectile != null, "rifle projectile exists")
	if projectile == null:
		container.free()
		entity.free()
		return
	_assert(is_equal_approx(projectile.damage, 50.0), "rifle deals its full damage")

	var enemy := FakeTarget.new()
	projectile._on_hitbox_body_entered(enemy)
	_assert(is_equal_approx(enemy.damage_taken, 50.0), "projectile damages a hostile body")

	var friendly := FakeTarget.new()
	friendly.team = &"player"
	projectile._on_hitbox_body_entered(friendly)
	_assert(is_equal_approx(friendly.damage_taken, 0.0), "projectile ignores its own team")

	projectile._on_hitbox_body_entered(enemy)
	_assert(is_equal_approx(enemy.damage_taken, 50.0), "piercing projectile hits each body once")

	enemy.free()
	friendly.free()
	container.free()
	entity.free()

func _make_entity(weapon_name: StringName) -> Entity:
	var entity := Entity.new()
	entity.data = load("res://resources/entities/web_developer/web_developer.tres") as EntityData
	entity.team = &"player"
	entity.current_weapon = load(
		"res://resources/weapons/%s_weapon.tres" % weapon_name
	) as WeaponData
	entity.position = Vector2(100, 100)
	entity.rotation = 0.0
	root.add_child(entity)
	entity._refresh_muzzle()
	return entity

func _make_container() -> Node2D:
	var container := Node2D.new()
	root.add_child(container)
	container.add_to_group(&"projectiles_root")
	return container

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
