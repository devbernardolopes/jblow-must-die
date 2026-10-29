class_name EntityAnimator
extends RefCounted
## Drives an AnimatedSprite2D from an EntityAnimationSet.
##
## Only three states exist: IDLE, MOVE and ACTION. Actions such as shoot,
## reload, melee_attack and attack are one-shot overlays described by data.

enum State {
	IDLE,
	MOVE,
	ACTION,
}

signal action_started(action_id: StringName)
signal action_triggered(action_id: StringName)
signal action_finished(action_id: StringName)

var state: State = State.IDLE

var _sprite: AnimatedSprite2D = null
var _animation_set: EntityAnimationSet = null
var _actions: Dictionary[StringName, EntityAnimationAction] = {}
var _current_action: EntityAnimationAction = null
var _current_action_id: StringName = &""
var _action_time_left: float = 0.0
var _trigger_fired: bool = false
var _moving: bool = false
var _warned: Dictionary[String, bool] = {}

func bind(sprite: AnimatedSprite2D) -> void:
	if _sprite == sprite:
		return
	if _sprite != null:
		if _sprite.frame_changed.is_connected(_on_frame_changed):
			_sprite.frame_changed.disconnect(_on_frame_changed)
		if _sprite.animation_finished.is_connected(_on_animation_finished):
			_sprite.animation_finished.disconnect(_on_animation_finished)
	_sprite = sprite
	if _sprite != null:
		_sprite.frame_changed.connect(_on_frame_changed)
		_sprite.animation_finished.connect(_on_animation_finished)

func apply_set(next_set: EntityAnimationSet) -> void:
	if _animation_set == next_set:
		return
	if _current_action != null:
		_finish_action()
	_animation_set = next_set
	_actions.clear()
	_warned.clear()
	_current_action = null
	_current_action_id = &""
	state = State.IDLE
	if _sprite != null:
		_sprite.sprite_frames = next_set.sprite_frames if next_set != null else null
	if next_set == null or next_set.sprite_frames == null:
		return
	_build_action_map(next_set)
	_play_locomotion()

func tick(delta: float, moving: bool) -> void:
	_moving = moving
	if _sprite == null or _animation_set == null:
		return
	if state == State.ACTION:
		_action_time_left -= delta
		if _action_time_left <= 0.0:
			_finish_action()
		return
	_play_locomotion()

func request_action(action_id: StringName) -> bool:
	if _sprite == null or _animation_set == null:
		return false
	var next_action := _actions.get(action_id) as EntityAnimationAction
	if next_action == null:
		_warn_once(
			"missing_action_%s" % action_id,
			"No animation action '%s' in set '%s'." % [action_id, _animation_set.id]
		)
		return false
	if state == State.ACTION and _current_action != null:
		if next_action.priority <= _current_action.priority:
			return false
	_start_action(next_action)
	return true

func cancel_action() -> void:
	if state != State.ACTION:
		return
	_finish_action()

func is_busy() -> bool:
	return state == State.ACTION

func locks_movement() -> bool:
	return state == State.ACTION and _current_action != null and _current_action.locks_movement

func get_state() -> State:
	return state

func get_action_id() -> StringName:
	return _current_action_id

func get_animation_set_id() -> StringName:
	return _animation_set.id if _animation_set != null else &""

func get_current_animation() -> StringName:
	return _sprite.animation if _sprite != null else &""

func _build_action_map(animation_set: EntityAnimationSet) -> void:
	var frames: SpriteFrames = animation_set.sprite_frames
	if frames == null:
		return
	for anim_name: String in frames.get_animation_names():
		var anim_id := StringName(anim_name)
		if anim_id == animation_set.idle_animation or anim_id == animation_set.move_animation:
			continue
		var derived := EntityAnimationAction.new()
		derived.id = anim_id
		derived.animation = anim_id
		_actions[anim_id] = derived
	for action: EntityAnimationAction in animation_set.actions:
		if action == null:
			continue
		if not frames.has_animation(action.animation):
			_warn_once(
				"missing_animation_%s" % action.id,
				"Action '%s' targets missing animation '%s'." % [action.id, action.animation]
			)
			continue
		_actions[action.id] = action

func _play_locomotion() -> void:
	if _sprite == null or _animation_set == null or _sprite.sprite_frames == null:
		return
	var target_animation: StringName = (
		_animation_set.move_animation if _moving else _animation_set.idle_animation
	)
	if not _sprite.sprite_frames.has_animation(target_animation):
		target_animation = (
			_animation_set.idle_animation if _moving else _animation_set.move_animation
		)
	state = State.MOVE if _moving else State.IDLE
	if not _sprite.sprite_frames.has_animation(target_animation):
		return
	if _sprite.animation == target_animation and _sprite.is_playing():
		return
	_sprite.play(target_animation)

func _start_action(action: EntityAnimationAction) -> void:
	_current_action = action
	_current_action_id = action.id
	state = State.ACTION
	_trigger_fired = false
	_action_time_left = _animation_duration(action.animation)
	_sprite.play(action.animation)
	action_started.emit(action.id)
	if action.trigger_frame == 0:
		_fire_trigger()

func _finish_action() -> void:
	var finished_id: StringName = _current_action_id
	_current_action = null
	_current_action_id = &""
	state = State.IDLE
	if not finished_id.is_empty():
		action_finished.emit(finished_id)
	_play_locomotion()

func _animation_duration(anim: StringName) -> float:
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(anim):
		return 0.0
	var frames: SpriteFrames = _sprite.sprite_frames
	var total: float = 0.0
	for index: int in range(frames.get_frame_count(anim)):
		total += frames.get_frame_duration(anim, index)
	var speed: float = frames.get_animation_speed(anim) * _sprite.speed_scale
	if speed <= 0.0:
		speed = 1.0
	return total / speed

func _on_frame_changed() -> void:
	if state != State.ACTION or _current_action == null or _trigger_fired:
		return
	if _sprite.frame == _current_action.trigger_frame:
		_fire_trigger()

func _on_animation_finished() -> void:
	if state != State.ACTION or _current_action == null:
		return
	if _sprite.animation == _current_action.animation:
		_finish_action()

func _fire_trigger() -> void:
	if _trigger_fired:
		return
	_trigger_fired = true
	action_triggered.emit(_current_action_id)

func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
