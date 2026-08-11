# Physics Brief — Work Summary

Response to `PHYSICS_BRIEF_FOR_CLAUDE.md`, structured per its §9. Every claim
below is backed by a measured number from `tests/run_all.sh`; nothing is marked
fixed on the strength of "it looks right".

**Commits:** `733243f` (harness + diagnosis), `0ad6c69` (fixes + refactor).

---

## 0. Status at a glance

| | Task | Status |
| :--- | :--- | :--- |
| P1 | Ball wall-penetration at high speed | **Partial** — escape fixed, 27px clipping open |
| P2 | Constants refactor | **Done**, A/B proven identical |
| P3 | Ball restitution 0.7 → 0.3 | **Awaiting user decision** |
| P4 | Launch-from-orbit-angle | Parked, per brief |
| P5 | Escape-fix A/B verification | **Done** — reproduced, then fixed |
| P6 | Cap-facing reset | Not built, per brief |
| P7 | 3-strike forfeit final score | **Done** + a second bug found and fixed |

Two bugs were found that are **not** in the brief's list. One is fixed
(cumulative timeout counter); one is open and needs a decision (tether drift).

---

## 1. How verification works now

The brief's protocol (§6) assumes a Windows box driving the game through the
godot-ai MCP bridge. This work was done in a Linux GitHub Codespace, where that
bridge is unavailable: it is an editor plugin, and there is no display.

Instead: **Godot 4.7.1 `--headless`**, which steps physics normally and stubs
only rendering. `tests/run_all.sh` runs **one case per fresh OS process**, which
enforces §6's *"never reuse a run for a second eval"* structurally rather than
by remembering to restart.

Test-setup discipline (§5.4, §6.3):

- No ball teleports. Possession is always established through the game's own
  `_attach_ball`; shots go through `_launch_puck` / `_launch_cap` — the same
  functions player input calls.
- Caps are parked only where §6.3 sanctions it, kept ≥100px apart.
- Turn timer pinned high so the FSM cannot forfeit mid-case.

**Known gap in this method:** there are no rendered frames and no real touch
input. Physics numbers are trustworthy; nothing here is visually confirmed.
Closing that needs the xvfb + editor + MCP setup.

```
tests/run_all.sh              # all cases, fresh process each
godot --headless tests/run.tscn -- wall_double     # one case
```

---

## 2. P1 — wall penetration (PARTIAL)

### What was found

Two distinct failures were conflated under one heading. They have different
mechanisms and only one is fixed.

**(a) Escape — ball leaves the table entirely.** Reproduced with a real
max-power launch, no teleport:

```
f1  x=16.8   vx=-2303      already inside the wall
f2  x=55.6   vx=+1612      rebounds out
f3  x=-33.4  vx=-3212      ESCAPED
    final_ball_pos (-4104, 540)   — gone, never returns
```

Root cause: `MAX_BALL_SPEED` is enforced once per frame in `_physics_process`,
which runs **before** the solver. A wall-rebound double-hit therefore reaches
**3211.8 px/s inside a step against a 2600 clamp**, and the ball covers **89px
in that frame** while wall(20) + diameter(44) = 64. The containment arithmetic
in the `MAX_BALL_SPEED` comment assumes the clamp bounds in-step velocity. It
does not.

**(b) Clipping — 27px penetration on a single clean impact.** Ball centre
reaches **x=5.01** where contact geometry puts the floor at **32.0**.

The brief speculated this was an artefact of teleporting a sleeping body. **That
hypothesis is ruled out** — the trace shows `sleep=false` on every frame of a
fully natural launch chain. The penetration is real and reproduces naturally.

### What was changed

`scripts/design.gd:21` — new `WALL_COLLISION_DEPTH := 240.0`, physics-only.

`scripts/board.gd:74-79` (perimeter) and `102-112` (goal pockets) — walls are
now built **inner-face-first**: the face the ball strikes stays exactly where
`WALL_THICKNESS` puts it, and the body extends outward into off-pitch space
where nothing is drawn. Left/right overshoot the pitch ends so corners seal.

The renderer is untouched: `pitch_draw.gd` still draws `WALL_THICKNESS`.

### How it was verified

`wall_double`, before vs after — physics identical up to the double-hit, then
the deep wall catches the ball instead of passing it:

| frame | before | after |
| :--- | :--- | :--- |
| f3 | x=-33.4 vx=-3212 | x=-33.4 vx=-3212 *(identical)* |
| f4 | x=-76.3, leaving | **x=49.0 vx=+1820, back in play** |
| final | (-4104, 540) off table | (571, 219) `RECOVERED_INTO_PLAY YES` |

`wall_max` is **numerically identical** before and after — min_x 5.01,
penetration 26.99, speed_at_min 2041.4, final (207.0398, 540.0). That is the
proof that inner faces really are unchanged and no bounce was altered.

### What was deliberately NOT done

**(b) is still open.** Wall depth does not address it — that is solver contact
resolution, not tunnelling. The remedies each carry a cost the user should weigh:

- raise `physics_ticks_per_second` 60 → 120: halves per-frame travel, doubles
  physics CPU, subtly shifts damping behaviour;
- tune solver contact bias: global engine behaviour;
- lower `MAX_BALL_SPEED`: direct feel change.

Brief §5.5 and P1's own *"Do NOT just raise the clamp without testing"* put this
with the user.

---

## 3. P5 — escape A/B verification (DONE)

Commit `4429802` was never A/B verified. It is now, and it **does not contain
this case** — the escape above reproduces on the pre-fix build. Not
verified-by-absence; verified by reproduction, then by fix.

---

## 4. P7 — forfeit scoring (DONE, plus a second bug)

SRS 02 §4.F: *"3 **consecutive** timeouts (45s total) results in instant
forfeit — opponent awarded **5–0** technical win."* Both halves were violated.

**Bug 1 — the score was not 5-0.** The forfeiting player's real goals were left
in place, so a forfeit displayed **5-2**.
Fixed at `scripts/turn_manager.gd:534`. Verified: `final_score [0, 5]`.

**Bug 2 (not in the brief) — the counter was cumulative, not consecutive.**
`consecutive_timeouts` was never cleared, so timeouts spread across an entire
match still forced a forfeit.
Fixed at `scripts/turn_manager.gd:255` — committing an action clears the streak.
Verified: `[1,0]` after a timeout, `[0,0]` after the player takes their shot.

---

## 5. P2 — constants refactor (DONE, zero behaviour change)

### What was changed

- `scripts/board.gd:7-13` — `PITCH` / `GOAL_WIDTH` / `CAP_RADIUS` /
  `BALL_RADIUS` / `SLEEP_THRESHOLD` / `CAP_MASS` / `BALL_MASS` now alias
  `Design`. Aliases retained (not deleted) because `turn_manager` reads
  `board.PITCH`. `board.gd:87` uses `Design.GOAL_POST_RADIUS`.
- `scripts/turn_manager.gd:18-20` — geometry reads `Design`.
- **Dead constants removed:** `HALF`, `PITCH_X`, `PITCH_Y`, `HELD_OFFSET`. Each
  had exactly one occurrence in the file — its own declaration.
- `turn_manager.gd:29-37` — the three *different* `+6` margins are now
  `LAUNCH_SPAWN_GAP`, `TAP_TOLERANCE`, `CONTACT_SLOP`; `+12` is
  `CAPTURE_TOLERANCE`; `30.0`/`34.0` are `ATTACH_MIN_REL` /
  `ATTACH_FALLBACK_OFFSET`.
- `turn_manager.gd:39-46` — sweep knobs named (`SWEEP_STEPS`,
  `SWEEP_STEP_RAD`), and `42.0` / `678.0` / `1038.0` become `BALL_BOUND_MIN` /
  `BALL_BOUND_MAX_X` / `BALL_BOUND_MAX_Y`, derived from `Design`.

All values are unchanged. The bounds keep the original, deliberately
conservative wall-thickness + ball-radius margin (42) rather than the tighter
geometric value (32).

### How it was verified

Full suite before and after. **Byte-identical on every case not intentionally
changed:**

| case | value |
| :--- | :--- |
| probe | gap 58.0, overlap 8.0, peak 1115.4 |
| wall_max | min_x 5.01, penetration 26.99, speed 2041.4 |
| tether | 66.00 exact, deviation 0.00, no phase-through |
| tether_moving | 66.00 → 76.34 |
| pass_chain | caught f8, 77.26 / 76.78 |

Only `wall_double` and `forfeit` moved — the two intended fixes. The real game
scene also boots clean with zero script errors or warnings.

---

## 6. New bug — tether orbit degrades when the holder moves (OPEN)

Not in the brief. It contradicts the verified table in §3.

| holder state | orbit radius |
| :--- | :--- |
| parked | **66.00 px** exact, deviation 0.00 |
| gliding | **66.00 → 76.34 px**, monotonic drift |

Isolated in `tether_moving`, which differs from the passing `tether` case in
exactly one way: the holder has velocity. Throughout the drift the sweep reports
`clear=34` — every candidate on the circle is unobstructed — so the sweep and
the blocking logic are **not** the cause.

This is not a corner case. `MOMENTUM_CARRY` gives every receiver velocity, so
after a real completed pass the ball settles ~77px out, not 66 (`pass_chain`:
77.26 at catch, 76.78 after settling).

**Deliberately not fixed.** The tether is §2's do-not-break core with a
documented history of failed approaches, and §5.5 puts changes like this with
the user. Reported with measurements instead of patched on a hunch.

---

## 7. Everything deliberately not done

| Item | Why |
| :--- | :--- |
| P1(b), 27px clipping | Every remedy changes feel or global engine behaviour — §5.5 |
| P3, restitution 0.7 → 0.3 | Significant feel change; the brief says talk first |
| Tether drift (§6 above) | §2 core mechanic, long failure history; needs a decision |
| P4, launch-from-orbit-angle | Parked by the brief |
| P6, cap-facing reset | Brief says **do not implement** |
| Visual verification | No display in this environment; needs xvfb + editor + MCP |

---

## 8. Environment note

The godot-ai MCP bridge is **not** required for physics work and is not used
here. It drives a live editor for screenshots; physics runs headless without it.
The `DESIGN_BRIEF_FOR_CLAUDE.md` work is the part that genuinely needs it.

Setup on a fresh machine: download the Godot 4.7.1 Linux binary, then
`tests/run_all.sh`. The harness lives in the repo, so it survives Codespace
rebuilds; the binary does not.

One environment trap worth knowing: **a GDScript parse error leaves the scene
scriptless, so nothing calls `quit()` and the process hangs forever** rather
than erroring out. `run_all.sh` runs every case under a timeout and writes to a
file, because a pipe loses its buffer on SIGTERM and you see nothing at all.
