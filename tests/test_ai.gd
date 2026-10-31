extends SceneTree
## Headless checks for AI intent, perception, melee damage and the zombie tree.
## No gameplay scene is started.

const ZOMBIE_DATA_PATH: String = "res://resources/entities/zombies/zombie.tres"
const HANDS_WEAPON_PATH: String = "res://resources/weapons/hands_weapon.tres"
const ZOMBIE_TREE_PATH: String = "res://ai/trees/zombie_melee.tres"
const ZOMBIE_SCENE_PATH: String = "res://scenes/entities/zombie.tscn"

var _failures: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	await _test_controller_intent()
	await _test_perception_vision()
	await _test_perception_memory()
	await _test_melee_damage()
	await _test_tree_and_scene()
	if _failures == 0:
		print("AI tests: PASS")
		quit(0)
	else:
		printerr("AI tests: %d failure(s)" % _failures)
		quit(1)

func _test_controller_intent() -> void:
	var world: Node2D = _make_world()
	var entity: Entity = _make_entity(world, &"enemy", Vector2.ZERO)
	var ai: AIController = AIController.new()
	entity.add_child(ai)
	entity.controller = ai
	await process_frame

	ai.movement_mode = EntityController.MovementMode.OMNI
	ai.set_move_direction(Vector2.RIGHT)
	_assert(
		ai.get_move_vector().is_equal_approx(Vector2.RIGHT),
		"OMNI returns the world-space move direction"
	)

	ai.movement_mode = EntityController.MovementMode.RELATIVE_MOUSE
	ai.set_aim_position(entity.global_position + Vector2.RIGHT * 100.0)
	ai.set_move_direction(Vector2.DOWN)
	_assert(
		ai.get_move_intent().is_equal_approx(Vector2(1.0, 0.0)),
		"RELATIVE_MOUSE projects movement onto strafe and throttle"
	)

	ai.set_aim_position(entity.global_position + Vector2.UP * 100.0)
	_assert(
		ai.consume_aim_direction().is_equal_approx(Vector2.UP),
		"aim direction points at the requested position"
	)
	_assert(
		ai.consume_aim_direction().is_equal_approx(Vector2.UP),
		"aim is held until the next tick resets it"
	)

	ai.request_action(&"melee_attack")
	ai.set_running(true)
	_assert(ai.get_action_request() == &"melee_attack", "action request is exposed")
	_assert(ai.wants_run(), "run request is exposed")

	ai.tick(0.016)
	_assert(ai.get_move_vector().is_zero_approx(), "tick resets movement intent")
	_assert(ai.get_action_request().is_empty(), "tick resets the action request")
	_assert(ai.consume_aim_direction().is_zero_approx(), "tick resets aim")
	world.queue_free()
	await process_frame

func _test_perception_vision() -> void:
	var world: Node2D = _make_world()
	var viewer: Entity = Entity.new()
	viewer.data = load(ZOMBIE_DATA_PATH) as EntityData
	viewer.team = &"enemy"
	var perception: AIPerception = AIPerception.new()
	perception.scan_interval_s = 10.0
	viewer.add_child(perception)
	world.add_child(viewer)

	var target: Entity = _make_entity(world, &"player", Vector2(200.0, 0.0))
	await physics_frame
	perception._scan()
	_assert(perception.get_target() == target, "sees a hostile target in front")
	_assert(perception.is_target_visible(), "reports the target as visible")

	target.global_position = Vector2(-200.0, 0.0)
	await physics_frame
	perception._scan()
	_assert(not perception.is_target_visible(), "does not see a target behind the view cone")
	_assert(perception.has_target(), "remembers the target after losing sight")

	target.global_position = Vector2(-140.0, 0.0)
	await physics_frame
	perception._scan()
	_assert(perception.is_target_visible(), "sees a target inside the awareness radius")

	var wall: StaticBody2D = _make_wall(Vector2(100.0, 0.0))
	world.add_child(wall)
	target.global_position = Vector2(200.0, 0.0)
	await physics_frame
	perception._scan()
	_assert(not perception.is_target_visible(), "walls block line of sight")
	wall.queue_free()

	perception._clear_target()
	var ally: Entity = _make_entity(world, &"enemy", Vector2(100.0, 0.0))
	await physics_frame
	perception._scan()
	_assert(perception.get_target() != ally, "same-team entities are ignored")
	world.queue_free()
	await process_frame

func _test_perception_memory() -> void:
	var world: Node2D = _make_world()
	var viewer: Entity = Entity.new()
	viewer.data = load(ZOMBIE_DATA_PATH) as EntityData
	viewer.team = &"enemy"
	var perception: AIPerception = AIPerception.new()
	perception.scan_interval_s = 10.0
	perception.memory_duration_s = 0.05
	viewer.add_child(perception)
	world.add_child(viewer)
	var target: Entity = _make_entity(world, &"player", Vector2(200.0, 0.0))
	await physics_frame
	perception._scan()
	_assert(perception.has_target(), "acquires a target before memory expiry")

	target.global_position = Vector2(-200.0, 0.0)
	await physics_frame
	perception._scan()
	perception._physics_process(0.1)
	_assert(not perception.has_target(), "memory expires after the duration")
	world.queue_free()
	await process_frame

func _test_melee_damage() -> void:
	var world: Node2D = _make_world()
	var attacker: Entity = _make_entity(world, &"enemy", Vector2.ZERO)
	attacker.current_weapon = load(HANDS_WEAPON_PATH) as WeaponData
	attacker.facing = Vector2.RIGHT
	var target: Entity = _make_entity(world, &"player", Vector2(100.0, 0.0))
	await physics_frame

	var damage: float = attacker.current_weapon.base_damage
	var start_health: float = target.health
	attacker._melee_hit()
	_assert(
		is_equal_approx(target.health, start_health - damage),
		"melee damages a hostile target inside the arc"
	)

	var health_after_hit: float = target.health
	target.global_position = Vector2(-100.0, 0.0)
	attacker._melee_hit()
	_assert(is_equal_approx(target.health, health_after_hit), "melee misses behind the entity")

	target.global_position = Vector2(100.0, 0.0)
	target.team = &"enemy"
	attacker._melee_hit()
	_assert(is_equal_approx(target.health, health_after_hit), "melee ignores allies")

	target.team = &"player"
	target.global_position = Vector2(400.0, 0.0)
	attacker._melee_hit()
	_assert(is_equal_approx(target.health, health_after_hit), "melee misses beyond its reach")

	target.global_position = Vector2(100.0, 0.0)
	target.take_damage(999.0, attacker)
	_assert(target.dead, "lethal damage marks the entity dead")
	_assert(not target.is_alive(), "dead entities are not alive")
	world.queue_free()
	await process_frame

func _test_tree_and_scene() -> void:
	_assert(ClassDB.class_exists(&"BTPlayer"), "LimboAI is loaded")
	var tree: BehaviorTree = load(ZOMBIE_TREE_PATH) as BehaviorTree
	_assert(tree != null, "loads the zombie behavior tree")
	_assert(tree.root_task != null, "zombie behavior tree has a root task")

	var scene: PackedScene = load(ZOMBIE_SCENE_PATH) as PackedScene
	_assert(scene != null, "loads the zombie scene")
	if scene == null:
		return
	var world: Node2D = _make_world()
	var zombie: Entity = scene.instantiate() as Entity
	world.add_child(zombie)
	await process_frame
	await physics_frame
	var ai: AIController = zombie.controller as AIController
	_assert(ai != null, "zombie is driven by an AIController")
	if ai == null:
		world.queue_free()
		await process_frame
		return
	var player: BTPlayer = ai.get_node_or_null("BTPlayer") as BTPlayer
	_assert(player != null, "AIController instantiates its BTPlayer")
	if player != null:
		var board: Blackboard = player.get_blackboard()
		_assert(board != null, "BTPlayer owns a blackboard")
		if board != null:
			_assert(board.has_var(&"self_entity"), "blackboard receives the entity")
			_assert(board.has_var(&"health_ratio"), "blackboard receives health")
			_assert(board.has_var(&"target"), "blackboard receives the target")
	world.queue_free()
	await process_frame

func _make_world() -> Node2D:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	return world

func _make_entity(world: Node2D, team: StringName, position: Vector2) -> Entity:
	var entity: Entity = Entity.new()
	entity.data = load(ZOMBIE_DATA_PATH) as EntityData
	entity.team = team
	entity.position = position
	world.add_child(entity)
	return entity

func _make_wall(position: Vector2) -> StaticBody2D:
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.OBJECTS
	wall.collision_mask = 0
	wall.global_position = position
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(32.0, 512.0)
	shape.shape = rectangle
	wall.add_child(shape)
	return wall

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
