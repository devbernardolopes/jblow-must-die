# AGENTS.md

This is a Godot 4.7.2 project for a 2D top-down shooter game.
The underlying world rules follow D&D 5.5e (abilities: Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma).
This game is currently being developed and it is in very early stages. No one is playing it other than the solo human developer.

## Requirements

- Godot 4.7.2.
- GDScript.
- Statically typed (every function signature fully annotated; no untyped vars in new code; typed arrays and typed lambdas/Callables where practical).
- Fluid layout for all UI, must look good in desktop, mobile, and web.
- Keyboard and game controller support.
- Use snake case and screaming snake case for constants.
- All assets (images, musics, fonts, textures, and so on) will be provided by the human developer. Never fetch or generate binary assets. Code must work with missing art (fall back to flat colors / placeholder shapes).
- User-facing strings are plain English literals for now. Do not add i18n infrastructure.
- No secrets in the repo (no committed keys, tokens, or credentials).
- No commented-out dead code (git keeps history).
- Don't choose names for local variables that will shadow anything else (properties, methods, etc). Prefix with underscore if needed.

## Controls

- `Entity` never reads `Input`. Controllers translate devices into movement intent, action requests, weapon switches and aim.
- `MovementMode.OMNI` moves in screen space and turns `facing` toward the movement direction.
- `MovementMode.RELATIVE` keeps A/D as turning at `turn_rate_rad_s` and W/S as throttle along `facing`.
- `MovementMode.RELATIVE_MOUSE` also throttles with W/S, but A/D strafes sideways instead: positive X is the entity's own right. The cursor is the only steering input, so the keyboard never rotates the entity.
- Cursor aim is additive: `PlayerController` requests it on mouse motion in both relative modes, and `Entity` applies it as an instant `facing`/`rotation` change. It never touches velocity or throttle.
- In `RELATIVE`, cursor aim wins while the mouse is moving; once it is still, A/D turns normally again. In `RELATIVE_MOUSE`, `rotation` is always kept equal to `facing`.
- Cursor aim obeys the same gates as movement: `locked`, `is_staggered()` and movement-locking actions discard the request instead of queueing it.
- `is_moving` comes from the controller's intent, so aiming while standing still keeps the idle animation while strafing plays the move animation. `OMNI` ignores cursor aim.
- Aim requests are read once per physics tick through `EntityController.consume_aim_direction()`; a controller must never expose state that accumulates while gated.

## Animation Authoring

- Visuals are data-driven through `EntityAnimationSet` resources. A set has a stable `id`, one `SpriteFrames`, and the `idle`/`move` animation names.
- A set is selected by matching `WeaponData.name` against `EntityAnimationSet.id`. Entities without a weapon use `EntityData.default_animation_set_id`. A weapon with no matching set intentionally resolves to no set and logs a warning; do not silently fall back to another weapon's set.
- `EntityAnimator` is the only animation state machine, and it has exactly three states: `IDLE`, `MOVE`, `ACTION`. Do not add more states for individual attacks; those are one-shot actions.
- Every animation in the set that is not `idle`/`move` is auto-registered as an action under its own name. Add an `EntityAnimationAction` only when the defaults need changing: `id`, `animation`, `locks_movement`, `priority`, `trigger_frame`.
- Actions lock movement by default. Set `locks_movement = false` only for actions that should allow locomotion.
- A dry shot (attack action with an empty magazine) still plays its action, but as a non-locking overlay: `Entity.try_action()` requests it with `lock_movement = false` and skips the cooldown in both directions. The animation duration alone gates retriggering; real shots keep their movement lock and cooldown.
- `trigger_frame` is when gameplay happens (shots, hits, sounds). Keep timing in the animation resource and handle it in `Entity.action_triggered` instead of in controllers.
- `idle` and `move` must loop (`loop = 1`); action animations must not loop.
- Controllers never drive animations directly. They return an action id from `get_action_request()`; `Entity.try_action()` handles cooldown gating and the animator handles playback.
- `WeaponData.attack_action` and `reload_action` name the actions in the equipped set (handgun: `shoot`, `reload`; melee: `melee_attack`).
- Resource scripts referenced by the `@tool` `Entity` (for example `EntityData`) must also be `@tool`, otherwise the editor loads a placeholder instance and method calls fail.
- Guns need a `ProjectileData` plus an explicit `shoot` action with `trigger_frame` set, otherwise the animation plays but no projectile spawns.
- Weapon switching is ignored while an action is busy. Cooldowns are keyed by weapon and action, so swapping cannot reset them.
- Ammo is per entity, keyed by `WeaponData.name`. `base_damage` is per shot and is divided across `projectile_count`; reload refills when the reload action reaches its `trigger_frame`.

## Minimap Authoring

- The minimap lives in `scenes/minimap.tscn` and is instanced under `Hud` in `scenes/world.tscn`. `Hud.target` feeds it the centred player.
- It is an immediate-mode `Control`: one `_draw()`, no SubViewport or second camera. `Minimap.map_transform()` converts world points to map-local pixels once per frame so the player lands on the centre.
- Anything on the map joins the `minimap_source` group and implements `get_minimap_geometry() -> Array[MinimapGeometry]`, returning shapes in **global world pixels**. `Wall` does this from its `Curve2D` centerline; `MinimapSource` does it for authored doors, areas and points of interest.
- Add a new map feature by adding a `MinimapGeometry.Kind`, a default color export on `Minimap`, and a source that emits it. Do not special-case drawing per node type.
- `MinimapSource` points are local to the node, so the shape follows its parent transform. Call `notify_minimap_changed()` after mutating points at runtime.
- Fog of war is the `MinimapVisibility` resource assigned to `Minimap.visibility`; `null` reveals everything. `is_explored` is persistent (walls and areas stay revealed), `is_visible_now` is transient (other entities only show while in view). Implement fog by subclassing it, not by editing the renderer.
- `Minimap.Corner` had to be named `MapCorner`: Godot 4.7 has a global `Corner` type that shadows a local enum of the same name and breaks parsing.
- Circular/rounded clipping happens in `Minimap._draw_geometry()`: world points are transformed to map-local pixels and clipped with `Geometry2D.intersect_polyline_with_polygon` / `intersect_polygons` against a generated circle or rounded-rectangle polygon. There is no clip shader; do not reintroduce one.

## Door Authoring

- Doors are authored like walls: a `Door` (`Path2D`, `@tool`) in the World scene whose curve is the closed footprint (two points). The Door node is a fixed anchor and never moves; only its `DoorLeaf` children animate.
- A leaf is one panel. It owns the `Line2D`, `AnimatableBody2D` collision and `LightOccluder2D`s in leaf-local space. Sliding sets the leaf transform; swinging rotates it about the leaf origin, which sits on a curve point (the hinge).
- `DoorData` describes the type: `kind` (SINGLE/DOUBLE), `motion` (SLIDE/SWING), prompts, key requirements, `open_angle_degrees` and `slide_ratio`. Per-instance placement lives on the node: `hinge_at_end`, `slide_reversed`, `swing_reversed`, `open_speed`, `starts_open`.
- Double doors split the baked curve at half its length; each half hinges or slides outward from its own outer end.
- Use `open()`, `close()` and `toggle()`. `state`, `progress`, `opened`, `closed` and `state_changed` are the runtime API. A single progress value makes reversal from any pose seamless; do not add per-state starting positions.
- Doors animate in `_physics_process` because the panels are `AnimatableBody2D` and must push entities on the physics clock.
- The built-in `Interactable` is an internal child placed at the curve midpoint, so it stays fixed while the panels move. `interaction_radius_m` is in meters. Never parent interaction nodes to a leaf.
- External mechanisms (levers, keypads) can live anywhere in the world and call `Door.open()` / `toggle()`; author a `DoorSwitch` and point its `door` at the Door for a ready-made fixed interaction point. Never animate the Door node itself.
- The minimap publishes the authored closed footprint as `MinimapGeometry.Kind.DOOR`; it does not follow the panels.

## AI Authoring

- Non-player entities use `AIController` (`EntityController` subclass) as the brain and actuator. `Entity` stays unaware of who drives it; `EntityController.tick(delta)` runs at the start of `Entity._physics_process`.
- `AIController` owns a `BTPlayer` with `update_mode = MANUAL`, so tree decisions and intent share the same physics tick. It also owns the `Blackboard`.
- `AIPerception` is a `Node2D` child of `Entity` that produces data only: target, visibility, last known position, memory. The controller syncs it to the blackboard every tick.
- Custom tasks live in `ai/tasks`; extend `EntityBTAction` / `EntityBTCondition`. Use `BTDynamicSelector` / `BTDynamicSequence` when a higher-priority branch must preempt a running one (flee over combat).
- Use `BTParallel` for simultaneous aim/chase/attack. Its children keep returning `RUNNING`, and `num_successes_required` must exceed the child count.
- Blackboard keys: `self_entity`, `self_position`, `health_ratio`, `target`, `has_target`, `target_visible`, `target_position`, `target_distance`, `home_position`, `patrol_points`, `patrol_index`, `patrol_point`.
- Teams are opt-in: `is_hostile_to()` is false when either team is empty. Projectiles pass the shooter as the damage source.
- Melee uses `Entity.melee_reach_m` / `melee_arc_degrees`, a line-of-sight ray, and the weapon's `base_damage`; it is triggered from the attack animation's `trigger_frame`.
- Behavior trees are authored as `.tres` under `ai/trees`. `ai/trees/zombie_melee.tres` is the reference tree (flee, combat, patrol).
- `AIPerception.awareness_radius_m` must stay larger than the combined collision radii (entities are 4 m radius each), otherwise close targets are pushed out of awareness.

## Testing

All **gameplay** testing is manual by the human after every iteration: do not run the main game scene.
The testing devices is:

1. Samsung Odyssey laptop running Omarchy Quattro in 1920 x 1080 @ 60 Hz.

Agents must validate scripts without running gameplay. Use the headless harness.
Never ship a script with parse or compile errors.

Headless validation commands:

```sh
godot --headless --path . --import
godot --headless --path . --check-only --script res://scripts/entity_animator.gd
godot --headless --path . --script res://tests/test_entity_animator.gd
godot --headless --path . --script res://tests/test_animation_resources.gd
godot --headless --path . --script res://tests/test_entity_animation_integration.gd
godot --headless --path . --script res://tests/test_weapon_system.gd
godot --headless --path . --script res://tests/test_projectiles.gd
godot --headless --path . --script res://tests/test_player_controller.gd
godot --headless --path . --script res://tests/test_minimap.gd
godot --headless --path . --script res://tests/test_door.gd
godot --headless --path . --script res://tests/test_ai.gd
```

`--import` must report no errors before the tests; the resource test also validates authored `.tres` animation sets, so extend it when adding a set or weapon.

## Agent Workflow Notes (learned the hard way — keep current)

- While the agent writes files, keep those files **closed** in the Godot script editor: an open buffer can silently revert external writes on focus/undo/save.
- After every script write, **read the file back from disk** — never trust the write receipt alone.
- `node_set_property` cannot coerce strings to bool/int — set non-string properties in GDScript instead.
- `input_map` calls must be **sequential** (parallel bursts wedge the backend lock); `project_manage settings_set` accepts invalid keys without complaint (verify setting names against engine docs).
- Godot 4 API differs from Godot 3 memory (e.g. `ScrollContainer.horizontal_scroll_mode`). When unsure about a property or method, check the Godot 4.7 docs instead of guessing.
- Editor-log ghosts: the log buffer re-emits stale diagnostics on scans — confirm errors against current file contents (grep) before treating them as live.
- Never reference `EditorInterface` directly from a script that is shipped in a game: editor classes are stripped from export templates and the script then fails to load. Access it only under `Engine.is_editor_hint()` through `Engine.get_singleton(&"EditorInterface")`.
- Godot generates `.gd.uid` sidecars; keep them tracked so scenes and references stay stable.

## Commit Convention

When there are changes to commit, AI agents should suggest an one-line commit message at the end of their response following conventional commit format: `type(scope): description`. Use types like `feat`, `fix`, `refactor`, `docs`, `chore` and keep descriptions concise but descriptive — focus on the "why" rather than the "what". This message must be in own line to facilitate copying.
