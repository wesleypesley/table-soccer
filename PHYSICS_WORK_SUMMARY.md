# Physics Brief — Work Summary

> **⚠️ SUPERSEDED IN PART — read this first.**
> This document describes work done against `PHYSICS_BRIEF_FOR_CLAUDE.md`, which
> was **removed from the repo** in `3d96773`; the current brief is
> `How the game should look and feel/Design & Gameplay Physics rule.md`.
> Since PR #1 merged, `turn_manager.gd` has been substantially rewritten
> (2026-08-11): the sweep-based tether is now a **spring**
> (`TETHER_STIFFNESS` / `TETHER_DAMPING`), `MAX_BALL_SPEED` and
> `HELD_BALL_SPEED` were removed in favour of CCD, the striker follow-through
> brake was removed, and `MOMENTUM_CARRY` became a real impulse.
>
> **Still accurate:** §4 (P7 forfeit, both fixes in place), §5 (P2 refactor),
> §7 (goal pocket — re-verified on current master), and §2's wall-depth fix
> (`WALL_COLLISION_DEPTH` survives; the ball is still contained).
> **Stale:** §6's tether numbers describe the old implementation. See §12 for
> measurements taken against current master.

---

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

Three bugs were found that are **not** in the brief's list. One is fixed
(cumulative timeout counter); two are open and need a decision — the tether
drift (§6) and the goal pocket (§7). Open decisions are collected in §11.

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

## 7. New bug — the goal pocket cannot fit the ball (OPEN)

Not in the brief. Found while measuring P3, and it is a live bug at the current
`bounce = 0.7`.

`detect_goal()` requires the ball **centre** to reach `y < 0`. But the pocket's
clear depth is `pd(36) − tw(20) = **16px**`, while the ball radius is **22px**.
A ball at rest inside the goal therefore sits at **y = +6.0** — it physically
cannot get behind the goal line and stay there.

Goals only register during the transient frame in which the ball is
*penetrating the pocket's back wall*:

| shot power | ball peak | min ball y | scored? |
| ---: | ---: | ---: | :--- |
| 1400 | 2303 | −20.08 | YES |
| 1100 | 1810 | −3.51 | YES (2–3px margin) |
| 900 | 1481 | −2.41 | YES (2–3px margin) |
| 700 | 1152 | **+1.65** | **NO** |

**A soft shot that rolls into the goal and stops does not count.** Scoring
currently depends on a solver artefact, with a 2–3px margin at mid power.

Reproduce: `godot --headless tests/run.tscn -- goal 700`

Not fixed — see §11, question 1.

---

## 8. P3 — restitution 0.7 → 0.3, measured (AWAITING DECISION)

Measured by temporarily setting `bounce = 0.3`, running the full suite, then
reverting. The brief predicted "shots die faster, rebounds weaker". It is more
than that: **the puck-to-ball kick is itself a restitution event**, so lowering
the ball's bounce weakens every shot at the source.

| | 0.7 | 0.3 |
| :--- | ---: | ---: |
| ball peak off the kick | 2303.1 | **1771.1** (−23%) |
| pass completes | yes (f8) | yes (f10) |
| capture / tether orbit | 66.00 | 66.00 |
| goal from 634px | scores | **fails** |
| double-hit peak | 3211.8 (over clamp) | 1795.1 (under clamp) |

Capture and passing survive unharmed. Two notes that matter for the decision:

- The goal failure at 0.3 is **not** caused by restitution directly — it lowers
  impact speed, which drops penetration below the accidental threshold in §7.
  Fixing §7 changes this row, and probably makes 0.3 much cheaper than it looks.
- 0.3 would independently have suppressed the P1/P5 escape: peak energy in the
  double-hit falls below `MAX_BALL_SPEED` entirely.

---

## 9. Everything deliberately not done

| Item | Why |
| :--- | :--- |
| P1(b), 27px clipping | Every remedy changes feel or global engine behaviour — §5.5 |
| P3, restitution 0.7 → 0.3 | Significant feel change; the brief says talk first |
| Tether drift (§6 above) | §2 core mechanic, long failure history; needs a decision |
| P4, launch-from-orbit-angle | Parked by the brief |
| P6, cap-facing reset | Brief says **do not implement** |
| Visual verification | No display in this environment; needs xvfb + editor + MCP |

---

## 10. Environment note

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

---

## 11. Open decisions — questions for the user

Four things are blocked on a decision. None should be made unilaterally: each
either changes game feel, changes visible geometry, or touches the §2 core.

### Q1 — Goal pocket: how should scoring be fixed? *(recommended first)*

The ball cannot fit behind the goal line (§7).

- **(a) Deepen the pocket** so clear depth > `BALL_RADIUS`. Geometrically
  correct and keeps `detect_goal`'s documented "centre crosses the line" rule.
  Changes **visible** goal depth, so per brief §5.1 it needs a `Design` token
  that the renderer follows — `pitch_draw.gd:147-148` currently hardcodes
  `pd = 36.0` / `tw = 20.0`, duplicating the physics values.
- **(b) Loosen `detect_goal()`** to fire on the ball's leading edge instead of
  its centre. No visual change, but it redefines what a goal is.

Recommended first because it is a plain gameplay bug in normal play, **and its
answer changes the answer to Q2.**

### Q2 — P3: apply restitution 0.3?

Data in §8. Worth deciding **after** Q1, since the goal row is the main cost and
Q1 changes it.

### Q3 — P1's remaining 27px clipping: which remedy?

Ball centre reaches x=5.01 where contact geometry says 32.0 (§2). Options, each
with a cost: raise `physics_ticks_per_second` 60 → 120 (halves per-frame travel,
doubles physics CPU, subtly shifts damping); tune solver contact bias (global
engine behaviour); or lower `MAX_BALL_SPEED` (direct feel change).

### Q4 — Tether drift: fix it, or accept it?

Orbit holds 66.00 exactly when parked but drifts to 76.34 while the holder
glides (§6), so the ball sits ~77px out after every real pass. Fixing it means
touching the §2 core mechanic, which has a documented history of failed
approaches. Accepting it means updating §3 of the brief, since the "66px orbit"
invariant is only true for a stationary holder.

---

## 12. Re-measured against current master (f2874c3)

Run after PR #1 merged and `turn_manager.gd` was rewritten. Suite is green;
these are the values that moved.

| case | before (PR #1) | current master | note |
| :--- | ---: | ---: | :--- |
| probe cap/ball overlap | 8.0 | **14.3** | no speed clamp |
| wall_max overall penetration | 26.99 | **38.36** | no speed clamp; first impact unchanged at 26.99 |
| wall_double escape | contained | **contained** | deep wall still holds, peak 3211.8 |
| tether (parked) | 66.00 | **66.00** | spring holds exactly |
| tether_moving drift | 76.34 | **71.01** | spring improved it; not eliminated |
| goal | scores | **scores** | pocket bug (§7) unchanged |
| forfeit | 5-0, counter resets | **5-0, counter resets** | both fixes intact |

### New regression — the striker crushes the ball into the receiver

`pass_chain` now ends with the ball **inside its own holder**: settled radius
**19.75px**, minimum **17.37px**, against a cap radius of 44 and a contact
distance of 66.

The trace shows the spring behaving correctly and then being overpowered:

```
f0..f9   r 77.21 -> 67.44   smooth spring convergence toward 66
f9       d_passer=128       striker closing
f10      r 51.67            collapse in ONE frame; v_hold 162 -> 335
f13      r 34.13            BALL_INSIDE_HOLDER trips
f19      r 19.75            caps ~88 apart = touching, ball trapped between
```

The striker coasts into the receiver and squeezes the ball into it. The
ball/holder collision exception means nothing physically stops this — the
removed follow-through brake was what previously kept the striker off the
receiver (its own comment said "so it can't cannonball into the receiver").

Guarded by `BALL_INSIDE_HOLDER` in `pass_chain` so it cannot regress silently.
**Not fixed here:** the brake removal was a deliberate, user-confirmed feel
change (`8d076db`), and the tether was rewritten the same day — fixing this
means touching a subsystem under active revision, so it needs a decision.

Also fixed in this pass: `_park_others_away` used to park spare caps in a
column at x=672, directly in the drift path of a receiver shoved by
`MOMENTUM_CARRY`. The receiver coasted into a parked **opponent**, the release
rule fired, and `pass_chain` reported a completed pass whose possession had
already been lost (`passes_after 3`, `holder_is_receiver NO`). Spares now park
in the top-left corner, clear of every case's action.

---

## 13. Implementing the current brief (6-a-side, bigger GK, kickoff, facing)

Work against `How the game should look and feel/Design & Gameplay Physics rule.md`
after studying the two reference screenshots. Suite extended to 11 cases, all green.

**Read off the reference, not invented:** every formation thumbnail sums to six
(1-3-2, 1-2-3, 1-4-1, 1-2-1-2), and the HUD reads **"Goals to win: 3"**, so
`WIN_GOALS` moved 5 → 3. The in-play shot shows a 1-2-1-2 shape, which is what
`FORMATION_BOTTOM` / `FORMATION_TOP` now encode.

| brief item | status | evidence |
| :--- | :--- | :--- |
| 6 caps per team | done | `formation`: 12 caps, 6/side, no overlaps |
| GK genuinely bigger | done | `gk`: radius 58 vs 44, collider matches, mass 26.1 vs 15, contact ring 80 vs 66 |
| Kickoff reforms both teams | done | `kickoff`: formation error 0.0px, ball on the centre spot, conceder kicks off |
| Holder faces the goal | done | `_face_target_goal` each tether frame |
| Everything wired (networking) | **not done** | out of scope here |
| Crowd sound | **not done** | no audio in this environment |
| Visual identity (stands, crests, nets, flags) | **not done** | needs a display — see below |

### Two bugs this uncovered

**Position writes on an awake RigidBody2D silently revert.** `reset_formation`
looked correct and did nothing: a direct `cap.position = ...` read back 0.0px
error on the same frame and **781.7px four frames later**, because the physics
server owns the transform and restores its own. It appears to work on a
*sleeping* body, which is exactly what hid it. Both `reset_formation` and
`reset_ball` now go through `PhysicsServer2D.body_set_state`. `reset_ball` had
the same latent bug and resets a ball that is travelling fast.

**PhysicsServer2D transforms are global; formations are board-local.** The first
fix put every cap off by exactly `(-198, -426)` — the board offset. `teleport_body`
now converts through `global_transform`.

### Not done, and why

The visual half of the brief — stadium crowd stands down both touchlines, club
crests on the caps, real goal nets, corner flags, the cyan active-team halo —
is not attempted. The brief asks for it to be built by eye in the 2D editor with
screenshots, and this environment has no display. Doing it blind is guesswork,
and the brief's own rule is to work from the video and screenshots visually.
That work needs the Godot editor + MCP bridge on a machine with a display.

The video itself was not watched: no `ffmpeg` here to extract frames, and the
`.mp4` cannot be read directly. Everything above comes from the two screenshots.
