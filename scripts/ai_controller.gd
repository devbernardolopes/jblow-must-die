class_name AIController
extends EntityController
## Brain for non-player entities. The behavior tree only expresses intent;
## Entity remains the only place that turns intent into movement and actions.

## Tree authored in the LimboAI editor; the controller instantiates its player.
@export var behavior_tree: BehaviorTree = null
## Optional explicit perception node; otherwise the first child of the entity is used.
@export var perception: AIPerception = null
## Whether movement tasks ask the entity to run.
@export var run: bool = false
## Patrol route in world pixels; an empty route disables the patrol branch.
@export var patrol_points: Array[Vector2] = []

## World-space direction requested by the tree during the current tick.
var _move_direction: Vector2 = Vector2.ZERO
## World-space point the tree wants the entity to face during the current tick.
var _aim_position: Vector2 = Vector2.ZERO
var _has_aim: bool = false
var _action_request: StringName = &""
var _entity: Entity = null
var _bt_player: BTPlayer = null
var _blackboard: Blackboard = null

func _ready() -> void:
	_entity = get_parent() as Entity
	if perception == null and _entity != null:
		perception = _find_perception()
	_ensure_bt_player()
	_sync_static_blackboard()

func _find_perception() -> AIPerception:
	for child: Node in _entity.get_children():
		if child is AIPerception:
			return child as AIPerception
	return null

func _ensure_bt_player() -> void:
	if _bt_player != null or behavior_tree == null:
		return
	_bt_player = BTPlayer.new()
	_bt_player.name = "BTPlayer"
	_bt_player.behavior_tree = behavior_tree
	_bt_player.update_mode = BTPlayer.MANUAL
	_bt_player.agent_node = NodePath("../..")
	_bt_player.set_scene_root_hint(_scene_root())
	_blackboard = Blackboard.new()
	_bt_player.blackboard = _blackboard
	add_child(_bt_player)

## Headless tests have no current scene, so fall back to the entity itself.
func _scene_root() -> Node:
	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return _entity

## Runs the behavior tree before Entity reads intent for this physics tick.
func tick(delta: float) -> void:
	_reset_intent()
	if _entity == null or not is_instance_valid(_entity) or _entity.dead:
		return
	_sync_blackboard()
	if _bt_player != null:
		_bt_player.update(delta)

## Called by tasks to request world-space movement this tick.
func set_move_direction(direction: Vector2) -> void:
	_move_direction = direction.limit_length(1.0)

## Called by tasks to request that the entity faces a world-space point.
func set_aim_position(world_position: Vector2) -> void:
	_aim_position = world_position
	_has_aim = true

## Called by tasks to request an action id; Entity gates cooldown and busy state.
func request_action(action_id: StringName) -> void:
	_action_request = action_id

func set_running(value: bool) -> void:
	run = value

func get_move_vector() -> Vector2:
	return _move_direction

## Projects the world-space move direction onto the entity's facing and right side,
## so relative movement modes get correct throttle and strafe values.
func get_move_intent() -> Vector2:
	var forward: Vector2 = _facing_direction()
	var right: Vector2 = forward.rotated(PI * 0.5)
	return Vector2(_move_direction.dot(right), _move_direction.dot(forward)).limit_length(1.0)

func wants_run() -> bool:
	return run

func get_action_request() -> StringName:
	return _action_request

func consume_aim_direction() -> Vector2:
	if not _has_aim or _entity == null or not is_instance_valid(_entity):
		return Vector2.ZERO
	var offset: Vector2 = _aim_position - _entity.global_position
	if offset.is_zero_approx():
		return Vector2.ZERO
	return offset.normalized()

func _facing_direction() -> Vector2:
	if _has_aim and _entity != null and is_instance_valid(_entity):
		var offset: Vector2 = _aim_position - _entity.global_position
		if not offset.is_zero_approx():
			return offset.normalized()
	if _entity != null and is_instance_valid(_entity):
		return _entity.facing
	return Vector2.RIGHT

func _reset_intent() -> void:
	_move_direction = Vector2.ZERO
	_has_aim = false
	_action_request = &""

func _get_blackboard() -> Blackboard:
	if _blackboard != null:
		return _blackboard
	if _bt_player != null:
		_blackboard = _bt_player.get_blackboard()
	return _blackboard

func _sync_static_blackboard() -> void:
	var board: Blackboard = _get_blackboard()
	if board == null or _entity == null:
		return
	board.set_var(&"home_position", _entity.global_position)
	board.set_var(&"patrol_points", patrol_points)
	board.set_var(&"patrol_index", 0)
	board.set_var(&"patrol_point", _entity.global_position)

func _sync_blackboard() -> void:
	var board: Blackboard = _get_blackboard()
	if board == null or _entity == null:
		return
	var current_target: Entity = null
	var visible_now: bool = false
	var target_position: Vector2 = _entity.global_position
	if perception != null:
		current_target = perception.get_target()
		visible_now = perception.is_target_visible()
		target_position = perception.get_target_position()
	board.set_var(&"self_entity", _entity)
	board.set_var(&"self_position", _entity.global_position)
	board.set_var(&"health_ratio", _entity.get_health_ratio())
	board.set_var(&"target", current_target)
	board.set_var(&"has_target", current_target != null)
	board.set_var(&"target_visible", visible_now)
	board.set_var(&"target_position", target_position)
	board.set_var(&"target_distance", _entity.global_position.distance_to(target_position))
