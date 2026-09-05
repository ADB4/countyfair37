# CONTRACTS.md — load-bearing names and numbers

The single list of things other code, tickets and docs depend on. If a story
changes anything on this page, that story's done-gate is: update this page,
grep the board for the old name, fix every consumer, *then* close.

**How this file is checked.** `tools/contract_check.py` reads every
backticked string under the *Current* heading and greps `scripts/`,
`scenes/` and `project.godot` for it (whitespace-normalised, literal).
Anything not found is drift. Every backticked string under the *Retired*
heading must be *absent*. *In progress* and *Planned* are documentation only
(checked with `--pending` at a story's done-gate); a story closing promotes
its lines from *In progress* to *Current* and its replaced names to
*Retired*. So: **backtick only greppable literals**; keep explanations in
plain prose.

Last verified: commit `432eb78` (CF37-60), Sep 5 2026.

---

## Current

### Engine and project

- Godot 4.6, Jolt: `3d/physics_engine="Jolt Physics"`
- Renderer is still Forward Plus (`config/features=PackedStringArray("4.6", "Forward Plus")`) until CF37-75 flips it; the shipping target is Compatibility (web).
- Physics layers: `3d_physics/layer_1="world"`, `3d_physics/layer_2="projectile"`, `3d_physics/layer_3="target"` (layer 3 = mask value 4)
- Input actions: `move_left` (A / ←), `move_right` (D / →), `throw` (LMB), `restart` (R), `pause` (Esc)

### Classes and files

- `class_name PlayerController` — `scripts/player_controller.gd`
- `class_name PieProjectile` — `scripts/pie_projectile.gd`
- `class_name TargetCharacter` — `scripts/target_character.gd` (becomes TargetBase in CF37-61, see *In progress*)
- `class_name DebugEval` — `scripts/debug_eval.gd`; hub is `scripts/main.gd` (no class_name)
- Scenes: `scenes/main.tscn`, `scenes/environment.tscn`, `scenes/pie_projectile.tscn`, `scenes/target_character.tscn`

### Signals (exact signatures)

- `signal charge_started`
- `signal charge_updated(ratio: float)`
- `signal charge_released` — emitted from both `_throw()` and `_cancel_charge()`; every cancel path routes through `_cancel_charge`, so one connection covers release *and* cancel
- `signal pie_thrown(pie: PieProjectile)`
- `signal pointer_lock_changed(captured: bool)`
- `signal splattered` — on the pie; DebugEval binds it for range-at-splat
- `signal hit(points: int, zone: String)` — gains a third `target` argument in CF37-61
- `signal hit_zone_entered(zone: String, body: Node3D)` — gains a third `target` argument in CF37-61

### Public methods

- `func launch_direction(charge_ratio: float) -> Vector3` — the **one** launch-direction function; `_throw()` and CF37-74's predictor both consume it. It adds `lob_angle_deg` × (1 − charge) of upward pitch on top of the player's aim pitch: charge gates speed *and* the lob offset; aim pitch stays the player's
- `func capture_mouse() -> void`, `func release_mouse() -> void`, `func reset_for_round() -> void`
- `func launch(direction: Vector3, speed: float) -> void`, `func is_splatted() -> bool`, `func splat() -> void`
- `func restart() -> void` on the hub
- DebugEval handlers: `func on_charge_updated(ratio: float)`, `func on_charge_released()`, `func on_pie_thrown(pie: PieProjectile)`, `func on_hit_zone_entered(zone: String, body: Node3D)`
- DebugEval keys: `KEY_L` prints the session summary, `KEY_C` clears the throw log

### Exports and defaults (change only on DebugEval evidence, recorded on the ticket)

PlayerController:
- Look: `mouse_sensitivity := 0.0022`, `yaw_limit_deg := 75.0`, `pitch_min_deg := -50.0`, `pitch_max_deg := 40.0`
- Movement: `move_speed := 3.0`, `min_x := -3.2`, `max_x := 3.2`
- Throw: `min_throw_speed := 8.0`, `max_throw_speed := 22.0`, `full_charge_time := 1.0`, `lob_angle_deg := 30.0`, `charge_buffer_time := 0.15`, `throw_cooldown := 0.25`
- Total hold for full charge = `charge_buffer_time` + `full_charge_time` = 1.15 s. The 0.15 s buffer is deliberate forgiveness.

PieProjectile:
- `spin := 7.0`, `bounciness := 0.45`, `surface_friction := 0.7`, `impact_damping := 0.5`, `crumbs_per_bounce := 5`, `splat_speed := 1.2`, `settle_timeout := 2.0`, `cleanup_delay := 2.0`, `lifetime := 6.0`
- Drag pinned off (CF37-60): `linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE`, `linear_damp = 0.0`. Every range figure on the board assumes this.

TargetCharacter:
- `head_points := 25`, `body_points := 10`, `head_damage := 15`, `body_damage := 10`
- `var defeated := false` — a **variable**; the knockout *signal* (CF37-15) must use a different name

DebugEval: `miss_timeout := 2.0`

Hub: `const ROUND_DURATION := 60`

### Scene geometry (metres, Y up, player looks toward −Z)

- Player root at z 5.5: `0, 0, 5.5`. Camera at y 1.7: `0, 1.7, 0`. SpawnPoint child of camera: `0.25, -0.18, -0.55`.
  - **Release height 1.52 m** (1.7 − 0.18). **The 0.25 m X offset is intentional** — the pie leaves off the camera axis; crosshair and landing point are allowed to disagree. No convergence, ever.
- Camera `fov = 45.3`
- Target at z −2: `0, 0, -2` (7.5 m from the player root).
- Ground top at y 0 (box `24, 0.4, 24` centred at y −0.2). Counter `9.5, 1.1, 0.6` at `0, 0.55, 4.3` (behind the player; top at 1.1 m). Backdrop `10, 4.2, 0.4` at z −6.5 (front face −6.3). Side walls `0.5, 4.2, 11.4` at x ±5 (inner faces ±4.75).
- Target body: `CapsuleShape3D` r 0.3 h 1.7 at y 0.85 (feet at y 0). Head zone `SphereShape3D` r 0.25 at y 1.378; body zone `BoxShape3D` `0.7, 1, 0.7` at y 0.6. Zones are `Area3D` with `collision_mask = 2`, `monitorable = false`. Body root `collision_layer = 4`.
- Pie: `CylinderShape3D` r 0.16 h 0.08; `collision_layer = 2`, `mass = 0.5`, `continuous_cd = true`. Pies mask layer 1 only — they never collide with the target body, only enter its zones.
- Range envelope from CF37-60 (drag-free, 1.52 m release, 8 m/s min speed): 7.90 m to floor, 7.39 m to body zone, 6.66 m to head zone. Peak-range angle ≈ 39.5°. The v²/g figure of 6.53 m quoted elsewhere is wrong (ground launch).

### Hub wiring (main.gd `_ready`, signals-not-references)

- `_player.pointer_lock_changed` → `_on_pointer_lock_changed`
- `_player.charge_updated` → `_on_charge_updated` and `_debug_eval.on_charge_updated`
- `_player.charge_released` → `_debug_eval.on_charge_released`
- `_player.pie_thrown` → `_debug_eval.on_pie_thrown`
- `_target.hit` → `_on_target_hit`
- `_target.hit_zone_entered` → `_debug_eval.on_hit_zone_entered`
- Round flow: READY → click captures pointer → `_start_round` → PLAYING → timer 0 → ROUND_OVER → click restarts. R restarts at any time.

---

## In progress — CF37-61 (promote to Current when it closes)

- Files: `scripts/target_base.gd` (`class_name TargetBase`), `scenes/target_base.tscn`; main clown `scripts/target_clown.gd` (`class_name TargetClown`), inherited `scenes/target_clown.tscn`
- Signals: `signal hit(points: int, zone: String, target: TargetBase)`, `signal hit_zone_entered(zone: String, body: Node3D, target: TargetBase)`
- DebugEval: `func on_hit_zone_entered(zone: String, body: Node3D, _target: TargetBase = null)`
- Exports: `archetype_id: StringName`, `movement_mode: MovementMode`, `path_min_x := -2.5`, `path_max_x := 2.5`, `patrol_speed := 1.5` (placeholders; CF37-12 owns the numbers)
- Enum: `enum MovementMode { STATIONARY, PATH }`
- Public: `func reset() -> void`; personality hook `func _patrol(_delta: float) -> void`; feedback hook `func _on_hit_feedback(_zone: String) -> void` (empty; CF37-15 fills it)
- Hub: `%TargetManager` Node3D at identity; `_wire_targets()` loops children at `_ready` only — later-added targets are not wired
- Scene: `TargetClown` instance at `0, 0, -2` (STATIONARY, `archetype_id = "clown"`); committed `DummyPath` instance of `target_base.tscn` at `0, 0, -3.5` (PATH, `archetype_id = "dummy"`), kept until CF37-62/63/64
- Path bounds are in TargetManager space; keep inside the walls (±4.75) or the body collides instead of turning
- Retire when this closes (move to *Retired*): `DodgeSensor`, `TargetCharacter`, `%TargetCharacter`

## Planned (named on tickets, not yet in code)

- CF37-74: `signal arc_predicted(points: PackedVector3Array, hit: Dictionary)`; `%ImpactMarker` under Main; `show_impact_marker` export on the marker; predictor split `integrate(origin, velocity, gravity, dt, max_steps) -> PackedVector3Array` (portable, CF37-57) + `find_contact(points, space_state, mask) -> Dictionary`; re-simulation at most every 0.1 s
- CF37-15: `signal knocked_out(target: TargetBase)`; `defeat_bonus`; `respawn_delay`; knockout keeps the node alive and calls `reset()`
- CF37-19: `class_name GameHud extends CanvasLayer` in `scripts/hud.gd`; `set_score`, `set_time` (m:ss, ceil), `set_debug_state`, `show_charge` / `set_charge` / `hide_charge`, `show_message` / `hide_message`; `show_debug_state` export. CF37-20 adds `show_toast(text)`.
- CF37-10: every Control in `hud.tscn` is `mouse_filter = IGNORE`; HUD root flagged unique in `main.tscn` as `%GameHud`
- CF37-75: `rendering/renderer/rendering_method="gl_compatibility"` (+ `.mobile`); `rendering/gl_compatibility/driver.windows`; LightmapGI is render-only on Compatibility (bake on Forward+)
- Six canonical animation names: `idle`, `walk`, `duck`, `cower`, `hit`, `taunt` (`duck` = drop into cover)

---

## Retired (must not appear in code; grep the board too)

- `TODO(you)` and `# was:` — pairing scaffolding; must never survive into a committed story. (Open: player_controller.gd lines 159/183/184 — CF37-74 cleans them.)
