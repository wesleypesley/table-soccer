# Physics Fix Brief — for Claude (or any AI working on TableSoccer)

You are taking over physics debugging on a Godot 4.7 table-soccer game that mimics **Plato Table Soccer (Tactical mode)**. The game is 80% built and *mostly works*. Your job: find and fix the **remaining physics flaws** — nothing else. Do NOT redesign visuals, do NOT add features, do NOT restructure the codebase.

---

## 0. The ONE rule: verify everything empirically, never claim a fix without proof

Every change you make MUST be verified by:
1. **Restarting the game fresh** (stop → run) after EVERY code change. Godot caches script state; hot-reload masks bugs.
2. Running a **test harness via game_eval** (see §6) — one eval per fresh run, no exceptions.
3. Reporting **measured numbers** (positions, distances, velocities) — not "it looks right".

---

## 1. Project layout & how to drive it

- Project root: `C:\Users\Admin\TableSoccer`
- **Engine:** Godot 4.7.1 (project.godot: viewport 1080x1920, stretch `canvas_items`, aspect `keep`, MSAA 2D)
- **Scene construction is fully procedural** — no editor-placed nodes. Everything is built in `_ready()`.
- Files you care about:
  - `scripts/design.gd` — **Design tokens: THE single source of truth for geometry, physics feel, colors.** Read values from here; do NOT hardcode duplicates.
  - `scripts/board.gd` — physics core: walls, goal pockets, 10 caps, ball. `detect_goal()`, `reset_ball()`.
  - `scripts/turn_manager.gd` — match FSM (TURN_START / FLIGHT / MATCH_OVER), slingshot input, **the tether**, pass chains, release rules, timeout/forfeit. **NOTE: still duplicates CAP_RADIUS/BALL_RADIUS/PITCH_X/PITCH_Y — a known cleanup item, see §7.**
  - `scripts/pitch_draw.gd`, `cap_disc.gd`, `ball_disc.gd`, `cap_draw.gd`, `shadow_layer.gd`, `avatar_draw.gd`, `hud.gd` — **purely visual, zero physics. Leave them alone.**
- Node tree: `Main/Board` (the physics world, centered at 180,420 in canvas), `Main/TurnManager`, `Main/HUD`.
- Caps: `board.caps[]` — indices 0-4 = P0 (BLUE, bottom), 5-9 = P1 (RED, top). Ball: `board.ball`.
- **Board coordinates ≠ screen coordinates.** Board is offset (180,420) in the canvas. Input is already converted with `board.to_local()`. Use board-local coords in tests.

---

## 2. The core mechanic you must NOT break (this is the soul of the game)

**Ball capture / tether / pass chains** — user-corrected multiple times, verified through 4+ stress tests:

1. **Capture:** when a cap comes within `CAPTURE_DIST` (66px = 44 cap radius + 22 ball radius) of the ball, the ball **sticks** to that cap (only for the active player's caps, with passes left, excluding the striker).
2. **Tether:** the held ball stays a REAL `RigidBody2D` orbiting its holder at 66px. Every physics frame:
   - Project the ball onto the 66px circle at the nearest **clear** point.
   - Cancel only the RADIAL velocity component (relative to holder), keep the tangential = orbit spin.
   - If the direct orbit point is blocked (cap/wall), **sweep the target around the FULL circle** in small alternating steps (34 steps, ~5.7°/0.1 rad, nearest-first) to find a clear point — the ball slides around blockers and returns to orbit.
   - **Only apply the velocity constraint when the ball was re-placed (`placed == true`).** When blocked, leave velocity to the physics solver so the real rebound survives, then re-place once a gap opens.
3. **Release rule:** ANY opponent cap touching the HOLDER or the BALL breaks the tether → possession lost, turn passes. Implemented via `_on_ball_body_entered` → `_lose_possession.call_deferred()` (**must stay deferred** — see §8 crash history).
4. **Pass chains:** 3/5/∞ passes per turn (`pass_limit`, default 3). Catching a pass resets the turn timer. Striker can never receive its own pass.
5. **Speed clamps:** `MAX_BALL_SPEED 2600` (wall-tunnel guard), `HELD_BALL_SPEED 1500` (phase-through guard: 25px/frame < 44px cap radius).

**Failure history — do NOT re-tread these dead ends:**
- Teleport+velocity-overwrite → kills solver bounce → phase-through
- Manual spring force → unstable at high speed, ball through own holder
- `DampedSpringJoint2D` → no `enabled` property; too weak, ball settles 160px away
- Spring+clamp → ball through holder
- Hybrid `test_move` guard → doesn't detect pre-existing penetration, ball rests inside cap2
- Geometric checks + ALWAYS-on velocity constraint → ball dragged 262px away during a ram
- **CURRENT, VERIFIED:** geometric checks + full-circle sweep + velocity-constraint-only-when-placed. Evidence: max_d1=66.0 in all stress tests, min_d2=66.0 exact contact (no phase-through), held=true all frames, settles d1=66/d2=70.

---

## 3. Current verified physics state (don't "fix" what works)

| Behavior | Verified value |
| :--- | :--- |
| Ball orbits holder at | 66.0px exact, never through holder |
| Ball vs blocking cap | min 66.0px (genuine contact, no phase-through) |
| Ball held continuously | true all frames through rams/wall-jams |
| Ball after ram + wall clip | returns to 66px orbit (full-circle sweep) |
| Goal detect | ball center crosses goal line within GOAL_WIDTH → score |
| Goal pockets | caps/ball can NEVER leave the table (side+back walls behind each mouth) |
| Caps at max 1400px/s | contained by walls (no tunneling: 23px/frame < wall 20 + cap 44) |

---

## 4. Known remaining physics issues (your task list, in priority order)

### P1. Ball wall-penetration at high speed — OBSERVED, mechanism unclear, MUST TEST
- Observation: a teleport test (ball at 2600px/s straight at the left wall) showed the ball's center reached x=6.35 — the wall spans x −10..+10 (inner face at +10), ball radius 22 → center should stop at x≥32. It penetrated ~26px past the face **despite `continuous_cd = CCD_MODE_CAST_SHAPE`**. The ball did NOT fully escape (full escape needs center travel of wall 20 + 2×radius 44 = 64px/frame; 2600px/s = 43.3px/frame < 64 — the existing comment's math is correct for full escape), but it visibly clipped through the wall before the solver bounced it back.
- ⚠️ The teleport test was unnatural (teleported while sleeping). **Re-verify with a REAL launch**: cap at full pull speed striking the ball toward the wall (natural impulse chain). If real clipping reproduces:
  - Check why CCD doesn't catch it at the face (physics settings, body sleeping, `max_contacts_reported`, or the cap double-hit pushing the ball past the guard — see the MAX_BALL_SPEED comment about the 3840px/s double-hit).
  - Options: (a) verify/lower `MAX_BALL_SPEED` so per-frame travel stays under the penetration threshold, (b) fix CCD configuration, (c) thicker walls via `WALL_THICKNESS` token + re-render. Do NOT just raise the clamp without testing.
- Also verify the double-hit scenario from the comment: a cap rebounding off the wall can re-kick the ball at ~2× speed — confirm the clamp catches it before escape.

### P2. Constants refactor (cleanup, zero behavior change)
- `turn_manager.gd` redefines CAP_RADIUS/BALL_RADIUS/PITCH_X/PITCH_Y/HALF; `board.gd` redefines PITCH/GOAL_WIDTH/CAP_RADIUS/BALL_RADIUS. Both duplicate `design.gd`.
- Refactor: turn_manager reads `Design.CAP_RADIUS`, `Design.BALL_RADIUS`, `Design.PITCH` etc. Replace magic literals `42.0 / 678.0 / 1038.0` (= wall 20 + ball 22) with derived bounds. Replace three different `+6` margins with named constants. Name the sweep knobs (0.1 rad step, 34 iterations).
- **Verification:** game plays identically after refactor (run the §6 test suite before/after).

### P3. Ball restitution tuning — AGREED WITH USER, NEVER APPLIED
- Ball `mat.bounce` is currently **0.7** in board.gd. Per the design spec, real table-soccer ball ≈ **0.3**. The user agreed to 0.7 → 0.3 but we never applied it.
- ⚠️ This changes feel significantly: shots will die faster, rebounds weaker. **Talk to the user before applying** — they may want to feel it first. If applied, verify: passes still complete (striker closes gap before brake), capture still works, goals still reachable.

### P4. Launch-from-orbit-angle (skill piece, parked)
- When slingshotting a HOLDER, the launch direction should feel natural relative to the ball's orbit position — currently the ball is placed at `holder.position + d * (CAPTURE_DIST + 6.0)` along the pull direction. Consider: ball should start at the orbit point nearest the launch direction so the striker always kicks through the ball. Verify no double-hit (ball hit twice by the same cap in one launch).

### P5. Escape-fix A/B verification (commit 4429802, never verified)
- Commit `4429802` "Fix ball escape" changed wall geometry (goal mouth) + reset collisions + speed clamp. The specific escape sequence `(-3037, 1425)` was fixed but the fix was NEVER A/B verified (before/after reproduction). If you can reproduce an escape at high speed through walls/goal area, verify the current build contains it. Otherwise mark as verified-by-absence.

### P6. Cap-facing reset mechanic — PARKED BY USER, DO NOT IMPLEMENT
- The "cap faces opponent goal after capture" mechanic was designed and deliberately parked. **Do not build it.** If you notice the code touching it, leave it.

### P7. 3-strike forfeit final score
- Forfeit awards `score[winner] = WIN_GOALS` (5). Verify the final score shown is 5-0 (not 5-x where x was the loser's real score) and that kind-1050 `f:"true"` semantics are documented for later.

---

## 5. Constraints (hard rules)

1. **Do not touch visuals** — pitch_draw/cap_disc/ball_disc/cap_draw/shadow_layer/avatar_draw/hud are rendering-only and work. If a physics fix needs a visual change (e.g., wall thickness), change the token in `design.gd` and let the renderer follow.
2. **No canvas-item shaders.** Ever. They rendered invisible (VERTEX isn't local-space in fragment stage). Pure `_draw()` + baked ImageTextures only.
3. **Keep it modular** — every value comes from `design.gd` tokens; no new hardcoded magic numbers. The user's words: "keep it modular so that we dont fuck up."
4. **No teleports in tests; zero synthetic shortcuts.** Real formation positions, real game flow. Verify position read-backs. Discard polluted runs.
5. **Talk before big changes.** If a fix changes game feel (restitution, speed caps, capture radius), present it to the user first — they decide.
6. **Sounds/juice are deferred.** No audio, no particles unless asked.
7. **`_lose_possession` from `_on_ball_body_entered` MUST stay `call_deferred()`** — calling it synchronously from a physics signal crashes Godot natively (see §8).

---

## 6. Test harness (how to verify)

Via the godot-ai MCP: `editor_manage op=game_eval` with code like:

```gdscript
# ONE eval per FRESH run. Set a long timer so the FSM doesn't forfeit mid-test.
var board = get_tree().root.get_node("Main/Board")
var tm = get_tree().root.get_node("Main/TurnManager")
tm.turn_timer = 999.0
# ... your test ...
await get_tree().create_timer(0.5).timeout
return { ...measured values... }
```

Protocol:
1. **Stop** the game (`project_manage op=stop`), **run** fresh (`project_run mode=main`), THEN eval. Every change → restart → one eval.
2. **Never reuse a run for a second eval** — the FSM state is polluted. One eval per fresh run, max.
3. Park frozen test caps **≥100px apart** (they shove neighbors during setup if closer).
4. Dead-radial 1100-speed hits slam the ball into the holder — **hit tangentially** in tests.
5. Match can end mid-harness (state=3 MATCH_OVER) — set turn_timer high and check state.

Key measurements to report:
- `d1 = ball.distance_to(holder)` → expect 66.0 (never < 66 while held)
- `d2 = ball.distance_to(nearest other cap)` → expect ≥ 66.0 (no phase-through)
- `held = (tm.holder != null)` per frame → expect true throughout
- `ball.linear_velocity.length()` → never > MAX_BALL_SPEED
- `ball.position` bounds → never outside pitch + pockets

---

## 7. Reference: the tether algorithm (don't regress)

```gdscript
# In _physics_process, when holder != null and not _ball_in_flight:
if ball.linear_velocity.length() > HELD_BALL_SPEED:
    ball.linear_velocity = ball.linear_velocity.normalized() * HELD_BALL_SPEED
var rel = ball.position - holder.position
var dist = rel.length()
if dist > 0.01:
    var base_angle = rel.angle()
    var placed = false
    for sweep in range(34):                       # 34 steps, ~5.7° each, full circle
        var a = base_angle
        if sweep > 0:
            var dir_sign = 1.0 if sweep % 2 == 1 else -1.0
            a += dir_sign * (float(sweep) + 1.0) * 0.1   # alternating nearest-first
        var cand = holder.position + Vector2.from_angle(a) * CAPTURE_DIST
        var blocked = false
        for i in board.caps.size():
            if board.caps[i] == holder: continue
            if cand.distance_to(board.caps[i].position) < CAPTURE_DIST: blocked = true; break
        if not blocked and (cand.x < 42.0 or cand.x > 678.0 or cand.y < 42.0 or cand.y > 1038.0):
            blocked = true                       # wall bounds = wall 20 + ball 22
        if not blocked:
            ball.position = cand
            placed = true
            break
    if placed:                                    # ONLY when re-placed:
        var rel_v = ball.linear_velocity - holder.linear_velocity
        var radial = rel_v.dot(rel / dist) * (rel / dist)
        ball.linear_velocity = holder.linear_velocity + (rel_v - radial)
ball.angular_velocity = 0.0
```

---

## 8. Crash history (environment + code — know these)

- **`_lose_possession()` called synchronously from `body_entered`** → Godot native crash (silent process death, no script error, no WER record). FIXED with `call_deferred()`. Keep it.
- **Stale godot-ai MCP bridge** (v3.1.2 alongside v3.1.3) → silently killed the game session. Environment, not code. If the game dies with NO log/error: check for duplicate `godot-ai.exe`/`uvx.exe` processes and kill stale ones.
- **Stale editor parser-error state** can wedge the debugger → game freezes/kills silently. Full restart of editor + bridge clears it.
- Old `idx` parser error (typed `find()` returning Variant) was fixed — if you see "Cannot infer the type of idx", it's stale editor state, not live code.

---

## 9. When you're done

Report back with, for each task:
1. What you found (with measured numbers)
2. What you changed (file + lines)
3. How you verified (test scenario + resulting numbers)
4. Anything you deliberately did NOT do (and why)

Never say "fixed" without the measured evidence. If you can't reproduce an issue after honest attempts, say so — the user respects persistence but hates fake fixes.
