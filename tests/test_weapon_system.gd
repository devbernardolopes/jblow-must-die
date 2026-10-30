extends SceneTree
## Headless checks for weapon cycling, per-weapon cooldowns and ammo. No gameplay scene.

var _failures: int = 0

class FakeController extends EntityController:
	var switch_request: int = 0

	func get_weapon_switch() -> int:
		return switch_request

func _init() -> void:
	_test_cycling()
	_test_busy_switch()
	_test_controller_switch()
	_test_missing_current_weapon()
	_test_add_and_remove()
	_test_ammo()
	_test_per_weapon_cooldown()
	_test_dry_fire()
	if _failures == 0:
		print("Weapon system tests: PASS")
		quit(0)
	else:
		printerr("Weapon system tests: %d failure(s)" % _failures)
		quit(1)

func _test_cycling() -> void:
	var entity := _make_entity([&"handgun", &"rifle", &"knife"], &"knife")
	_assert(entity.select_next_weapon(), "next selects a weapon")
	_assert(_weapon_name(entity) == &"handgun", "next wraps from the last to the first")
	_assert(entity.select_previous_weapon(), "previous selects a weapon")
	_assert(_weapon_name(entity) == &"knife", "previous wraps from the first to the last")
	_assert(entity.select_next_weapon(), "next selects again")
	_assert(_weapon_name(entity) == &"handgun", "cycling is deterministic")
	entity.free()

func _test_busy_switch() -> void:
	var entity := _make_entity([&"handgun", &"rifle"], &"handgun")
	_assert(entity.try_action(&"shoot"), "shoot starts")
	_assert(not entity.select_next_weapon(), "switching is ignored mid-shoot")
	_assert(_weapon_name(entity) == &"handgun", "current weapon is unchanged while busy")
	entity.animator.cancel_action()
	_assert(entity.select_next_weapon(), "switching works after the action ends")
	_assert(_weapon_name(entity) == &"rifle", "weapon changed after the action")
	entity.free()

func _test_controller_switch() -> void:
	var entity := _make_entity([&"handgun", &"rifle"], &"handgun")
	var controller := FakeController.new()
	controller.switch_request = 1
	entity.set_controller(controller)
	entity._try_weapon_switch()
	_assert(_weapon_name(entity) == &"rifle", "controller next request switches weapon")
	controller.switch_request = -1
	entity._try_weapon_switch()
	_assert(_weapon_name(entity) == &"handgun", "controller previous request switches weapon")
	entity.free()

func _test_missing_current_weapon() -> void:
	var entity := _make_entity([&"rifle", &"knife"], &"handgun")
	_assert(entity.select_next_weapon(), "next works when the current weapon is not listed")
	_assert(_weapon_name(entity) == &"rifle", "next starts at the first listed weapon")
	entity.current_weapon = _load_weapon(&"handgun")
	_assert(entity.select_previous_weapon(), "previous works when the current weapon is not listed")
	_assert(_weapon_name(entity) == &"knife", "previous starts at the last listed weapon")
	entity.free()

func _test_add_and_remove() -> void:
	var entity := _make_entity([], &"")
	_assert(entity.add_available_weapon(_load_weapon(&"handgun")), "weapon can be added")
	_assert(_weapon_name(entity) == &"handgun", "added weapon is equipped when empty")
	_assert(not entity.add_available_weapon(_load_weapon(&"handgun")), "duplicates are rejected")
	_assert(entity.add_available_weapon(_load_weapon(&"rifle")), "second weapon can be added")
	_assert(entity.remove_available_weapon(_load_weapon(&"handgun")), "current weapon can be removed")
	_assert(_weapon_name(entity) == &"rifle", "removing the current weapon selects the next one")
	_assert(entity.remove_available_weapon(_load_weapon(&"rifle")), "last weapon can be removed")
	_assert(entity.current_weapon == null, "removing every weapon clears the current one")
	entity.free()

func _test_ammo() -> void:
	var entity := _make_entity([&"handgun"], &"handgun")
	var handgun := entity.current_weapon
	var capacity: int = entity.get_ammo_capacity(handgun)
	_assert(entity.get_ammo(handgun) == capacity, "ammo starts at magazine capacity")
	_assert(entity.try_action(&"shoot"), "shoot starts with ammo")
	entity._on_animator_action_triggered(&"shoot")
	_assert(entity.get_ammo(handgun) == capacity - 1, "shooting consumes one round")
	entity.animator.cancel_action()

	_assert(entity.try_action(&"reload"), "reload starts when not full")
	entity._on_animator_action_triggered(&"reload")
	_assert(entity.get_ammo(handgun) == capacity, "reload trigger refills the magazine")
	entity.animator.cancel_action()
	_assert(not entity.try_action(&"reload"), "reload is refused when full")

	for _index: int in range(capacity):
		entity._consume_ammo(handgun)
	_assert(entity.is_out_of_ammo(handgun), "gun is empty after consuming every round")
	_assert(entity.try_action(&"reload"), "empty gun can still reload")
	entity._on_animator_action_triggered(&"reload")
	_assert(entity.get_ammo(handgun) == capacity, "reload refills an empty magazine")
	entity.animator.cancel_action()

	var knife := _load_weapon(&"knife")
	_assert(not entity.is_out_of_ammo(knife), "melee weapons never run out of ammo")
	entity.free()

func _test_dry_fire() -> void:
	var entity := _make_entity([&"handgun"], &"handgun")
	var handgun := entity.current_weapon
	handgun.cooldown_period = 10.0
	for _index: int in range(entity.get_ammo_capacity(handgun)):
		entity._consume_ammo(handgun)
	_assert(entity.is_out_of_ammo(handgun), "gun is empty before the dry fire")
	_assert(entity.try_action(&"shoot"), "dry fire still plays the shoot animation")
	_assert(entity.animator.is_busy(), "dry fire is busy")
	_assert(not entity.animator.locks_movement(), "dry fire does not lock movement")
	_assert(not entity.try_action(&"shoot"), "dry fire cannot retrigger mid-animation")
	entity.animator.cancel_action()
	_assert(entity.try_action(&"shoot"), "dry fire does not write a cooldown")
	entity.animator.cancel_action()

	entity.current_weapon = _load_weapon(&"knife")
	_assert(entity.try_action(&"melee_attack"), "melee attack starts")
	entity.free()

func _test_per_weapon_cooldown() -> void:
	var entity := _make_entity([&"handgun", &"rifle"], &"handgun")
	entity.current_weapon.cooldown_period = 10.0
	_assert(entity.try_action(&"shoot"), "first shot starts")
	entity.animator.cancel_action()
	_assert(not entity.try_action(&"shoot"), "cooldown blocks an immediate second shot")

	_assert(entity.select_next_weapon(), "switch to the other weapon during cooldown")
	_assert(entity.try_action(&"shoot"), "cooldown does not transfer between weapons")
	entity.animator.cancel_action()

	_assert(entity.select_previous_weapon(), "switch back to the first weapon")
	_assert(not entity.try_action(&"shoot"), "cooldown survives switching away and back")
	entity.free()

func _make_entity(weapon_names: Array[StringName], current_name: StringName) -> Entity:
	var entity := Entity.new()
	entity.data = load("res://resources/entities/web_developer/web_developer.tres") as EntityData
	var weapons: Array[WeaponData] = []
	for weapon_name: StringName in weapon_names:
		var weapon := _load_weapon(weapon_name)
		if weapon != null:
			weapons.append(weapon)
	entity.available_weapons = weapons
	if not current_name.is_empty():
		entity.current_weapon = _load_weapon(current_name)
	return entity

func _load_weapon(weapon_name: StringName) -> WeaponData:
	var weapon := load("res://resources/weapons/%s_weapon.tres" % weapon_name) as WeaponData
	if weapon == null:
		return null
	return weapon.duplicate() as WeaponData

func _weapon_name(entity: Entity) -> StringName:
	return entity.current_weapon.name if entity.current_weapon != null else &""

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
