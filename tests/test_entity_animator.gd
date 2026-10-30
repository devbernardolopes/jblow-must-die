extends SceneTree
## Headless checks for EntityAnimator. No gameplay scene is started.

var _failures: int = 0

func _init() -> void:
	_test_locomotion_and_actions()
	_test_non_locking_action()
	_test_priority()
	_test_set_switch()
	_test_locomotion_replay()
	if _failures == 0:
		print("EntityAnimator tests: PASS")
		quit(0)
	else:
		printerr("EntityAnimator tests: %d failure(s)" % _failures)
		quit(1)

func _test_locomotion_and_actions() -> void:
	var sprite := AnimatedSprite2D.new()
	var animation_set := _make_set(&"test")
	var shoot := EntityAnimationAction.new()
	shoot.id = &"shoot"
	shoot.animation = &"shoot"
	shoot.trigger_frame = 1
	animation_set.actions = [shoot]
	var animator := EntityAnimator.new()
	animator.bind(sprite)
	animator.apply_set(animation_set)

	_assert(animator.get_state() == EntityAnimator.State.IDLE, "starts in idle")
	_assert(sprite.animation == &"idle", "idle animation plays")
	animator.tick(0.1, true)
	_assert(animator.get_state() == EntityAnimator.State.MOVE, "moves while intent is active")
	_assert(sprite.animation == &"move", "move animation plays")
	animator.tick(0.1, false)
	_assert(animator.get_state() == EntityAnimator.State.IDLE, "returns to idle")

	var triggered: Array[StringName] = []
	animator.action_triggered.connect(
		func(action_id: StringName) -> void: triggered.append(action_id)
	)
	_assert(animator.request_action(&"shoot"), "shoot starts")
	_assert(animator.is_busy(), "busy during action")
	_assert(animator.locks_movement(), "action locks movement")
	sprite.frame = 1
	_assert(triggered.size() == 1 and triggered[0] == &"shoot", "trigger frame emitted")

	animator.tick(0.11, true)
	animator.tick(0.11, true)
	_assert(animator.is_busy(), "still busy before the deadline")
	animator.tick(0.11, true)
	_assert(not animator.is_busy(), "action ends at the deadline")
	_assert(animator.get_state() == EntityAnimator.State.MOVE, "returns to move after action")
	sprite.free()

func _test_non_locking_action() -> void:
	var sprite := AnimatedSprite2D.new()
	var animation_set := _make_set(&"overlay")
	var shoot := EntityAnimationAction.new()
	shoot.id = &"shoot"
	shoot.animation = &"shoot"
	shoot.trigger_frame = 1
	animation_set.actions = [shoot]
	var animator := EntityAnimator.new()
	animator.bind(sprite)
	animator.apply_set(animation_set)
	animator.tick(0.1, true)
	_assert(sprite.animation == &"move", "starts from locomotion")

	_assert(animator.request_action(&"shoot", false), "non-locking action starts")
	_assert(animator.is_busy(), "non-locking action is busy")
	_assert(not animator.locks_movement(), "non-locking action allows movement")
	_assert(
		not animator.request_action(&"shoot", false),
		"non-locking action cannot retrigger mid-play"
	)
	animator.tick(0.1, true)
	_assert(animator.get_state() == EntityAnimator.State.ACTION, "still in action while moving")
	_assert(sprite.animation == &"shoot", "locomotion is suppressed during the action")

	animator.tick(0.25, true)
	_assert(not animator.is_busy(), "non-locking action ends with the animation")
	_assert(animator.get_state() == EntityAnimator.State.MOVE, "returns to move after the action")
	_assert(sprite.animation == &"move", "move animation resumes after the action")

	_assert(animator.request_action(&"shoot", false), "second non-locking action starts")
	animator.tick(0.1, false)
	animator.tick(0.25, false)
	_assert(animator.get_state() == EntityAnimator.State.IDLE, "returns to idle when not moving")
	_assert(sprite.animation == &"idle", "idle animation resumes")
	sprite.free()

func _test_priority() -> void:
	var sprite := AnimatedSprite2D.new()
	var animation_set := _make_set(&"priority")
	var low := EntityAnimationAction.new()
	low.id = &"low"
	low.animation = &"shoot"
	low.priority = 1
	var high := EntityAnimationAction.new()
	high.id = &"high"
	high.animation = &"shoot"
	high.priority = 5
	animation_set.actions = [low, high]
	var animator := EntityAnimator.new()
	animator.bind(sprite)
	animator.apply_set(animation_set)

	_assert(animator.request_action(&"low"), "low priority action starts")
	_assert(not animator.request_action(&"low"), "equal priority does not restart")
	_assert(animator.request_action(&"high"), "higher priority interrupts")
	_assert(not animator.request_action(&"low"), "lower priority is ignored")
	_assert(animator.get_action_id() == &"high", "high priority action is current")
	sprite.free()

func _test_set_switch() -> void:
	var sprite := AnimatedSprite2D.new()
	var set_a := _make_set(&"a")
	var set_b := _make_set(&"b", "2")
	var animator := EntityAnimator.new()
	animator.bind(sprite)
	animator.apply_set(set_a)
	animator.tick(0.1, true)
	_assert(sprite.animation == &"move", "set a move animation")

	animator.apply_set(set_b)
	_assert(animator.get_animation_set_id() == &"b", "set id switches")
	_assert(sprite.animation == &"move2", "set b move animation")
	_assert(animator.get_state() == EntityAnimator.State.MOVE, "locomotion state survives switch")
	sprite.free()

func _test_locomotion_replay() -> void:
	var sprite := AnimatedSprite2D.new()
	var animation_set := _make_set(&"replay")
	var animator := EntityAnimator.new()
	animator.bind(sprite)
	animator.apply_set(animation_set)
	animator.tick(0.1, true)
	_assert(sprite.is_playing(), "move is playing")

	sprite.stop()
	_assert(not sprite.is_playing(), "sprite stopped")
	animator.tick(0.1, true)
	_assert(sprite.is_playing(), "locomotion restarts after an external stop")
	sprite.free()

func _make_set(set_id: StringName, suffix: String = "") -> EntityAnimationSet:
	var animation_set := EntityAnimationSet.new()
	animation_set.id = set_id
	animation_set.idle_animation = StringName("idle" + suffix)
	animation_set.move_animation = StringName("move" + suffix)
	animation_set.sprite_frames = _make_frames(suffix)
	return animation_set

func _make_frames(suffix: String = "") -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	_add_animation(frames, StringName("idle" + suffix), true, 1)
	_add_animation(frames, StringName("move" + suffix), true, 3)
	_add_animation(frames, StringName("shoot" + suffix), false, 3)
	return frames

func _add_animation(
	frames: SpriteFrames, animation: StringName, loop: bool, frame_count: int
) -> void:
	frames.add_animation(animation)
	frames.set_animation_loop(animation, loop)
	frames.set_animation_speed(animation, 10.0)
	for _index: int in range(frame_count):
		frames.add_frame(animation, _make_texture(), 1.0)

func _make_texture() -> ImageTexture:
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  FAIL: " + message)
