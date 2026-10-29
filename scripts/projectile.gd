class_name Projectile
extends CharacterBody2D

const SCENE := preload("res://scenes/projectile.tscn")

var data: ProjectileData
var shooter: Node2D
var team: StringName = &""

var _life: float
var _bounces_left: int
var _pierce_left: int
var _hit: Array[Node] = []

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var wall_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hit_shape: CollisionShape2D = $Hitbox/CollisionShape2D

static func spawn(p_data: ProjectileData, pos: Vector2, dir: Vector2, p_shooter: Node2D) -> Projectile:
	var p: Projectile = SCENE.instantiate()
	p.data = p_data
	p.shooter = p_shooter
	p.team = p_shooter.get("team") if p_shooter.get("team") != null else &""
	# Dedicated container so projectiles don't move with the entity that fired them
	var root := p_shooter.get_tree().get_first_node_in_group(&"projectiles_root")
	if root == null:
		root = p_shooter.get_tree().current_scene
	root.add_child(p)
	p.global_position = pos
	p.velocity = dir.normalized() * p_data.speed
	p._orient()
	return p

func _ready() -> void:
	_life = data.lifetime
	_bounces_left = data.max_bounces
	_pierce_left = data.pierce

	# New shape instances per projectile, otherwise they'd share one resource
	var s1 := CircleShape2D.new()
	s1.radius = data.radius
	wall_shape.shape = s1
	var s2 := CircleShape2D.new()
	s2.radius = data.radius
	hit_shape.shape = s2

	if not data.sprite_frames.is_empty():
		sprite.sprite_frames = data.sprite_frames.pick_random()
		sprite.play(data.animation)

	hitbox.body_entered.connect(_on_hitbox_body_entered)

func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint():
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return

		var hit := move_and_collide(velocity * delta)
		if hit == null:
			return

		if _bounces_left > 0:
			_bounces_left -= 1
			var n := hit.get_normal()
			velocity = velocity.bounce(n)
			_orient()
			move_and_collide(hit.get_remainder().bounce(n))  # spend leftover motion
		else:
			_die()

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body == shooter or body in _hit:
		return
	if team != &"" and body.get("team") == team:
		return  # friendly, ignore completely
	_hit.append(body)

	if body.has_method("take_damage"):
		body.take_damage(data.damage, self)

	if data.pierce < 0:
		return  # passes through everything
	if _pierce_left > 0:
		_pierce_left -= 1
	else:
		_die()

func _orient() -> void:
	if data.rotate_to_direction:
		sprite.rotation = velocity.angle()

func _die() -> void:
	# Later: stop moving, play an "impact" animation, then free
	queue_free()
