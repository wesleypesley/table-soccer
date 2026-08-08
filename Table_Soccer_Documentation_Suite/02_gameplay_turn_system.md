# Gameplay Mechanics & Turn System Specification

*Design reference: Plato Table Soccer — Tactical mode (turn-based). Same gameplay model, P2P networking underneath.*
*Status: Part 1 (core gameplay) IMPLEMENTED. Items marked **[planned]** land in Part 2+.*

## 1. Match Rules & Win Conditions

| Parameter | Setting | Specification Details |
| :--- | :--- | :--- |
| **Win Condition** | First to 5 goals | First player to reach 5 goals wins. **No match clock, no ties, no configurable goal count.** |
| **Turn Clock** | 15 Seconds | Max time per turn to select, aim and fire. |
| **AFK Forfeit Rule** | 3 Strikes | 3 consecutive timeouts (45s total) results in instant forfeit — opponent awarded 5–0 technical win. |
| **Input** | Select-then-pull slingshot | Tap a cap to select (gold ring), drag BACK from it, release to fire. Drag direction = fire direction (slingshot: fire is opposite the pull), pull length = power. One pull = one action. |

## 2. Pre-Match Setup **[planned — Part 2]**

Before the match begins, both players complete:

1. **Select Team** — cosmetic: pick side colors / kit. *(Current build: fixed blue (bottom/P0) vs red (top/P1).)*
2. **Choose Formation** — tactical decision based on who starts with the ball:
   * **Attacking Formation** — used when *you* start with the ball.
   * **Defending Formation** — used when your *opponent* starts with the ball.
   *(Current build: fixed symmetric 2-2-1 per side — GK + 2 DEF + 2 FWD. Formation variants land in Part 2.)*
3. Kickoff player is determined (random or by prior match), then the match starts.

## 3. Match Finite State Machine (FSM)

### 3.1 Implemented FSM (Part 1)

```
       ┌─────────────────┐
       │   MATCH_START   │  (random kickoff, ball at center spot, FREE)
       └────────┬────────┘
                │
┌───────────────▼───────────────┐
│          TURN_START           │◄─────────────────────────────┐
│ (15s clock runs, input open)  │                              │
│  • select cap / aim / fire    │                              │
└───────────────┬───────────────┘                              │
                │ (pull released)                              │
┌───────────────▼───────────────┐                              │
│            FLIGHT             │────── (15s Timeout) ────────┤
│  (input locked, physics sim)  │                              │
│  • cap slides / ball flies    │                              │
│  • capture, pass, goal checks │                              │
└───────────────┬───────────────┘                              │
                │ (all bodies settle)                          │
                │  goal? → score → kickoff (center) ──────────┘
                │  captured? → continue turn (TURN_START)
                │  died free? → possession lost → turn passes ─┘
                ▼
       ┌───────────────┐
       │  MATCH_OVER   │  (first to 5, or 3-strike forfeit)
       └───────────────┘
```

* No Golden Goal — impossible: the match only ends when someone reaches 5 goals.
* No match clock — play continues until the goal target is hit.

### 3.2 Planned FSM Extension (Part 2+)
A dedicated `AIMING` phase (vs `TURN_START`) and explicit `EVALUATE_TURN` state will be added for team-select/formation and richer turn bookkeeping. The Part-1 FSM is intentionally minimal: input is open in `TURN_START`, locked in `FLIGHT`.

## 4. Detailed Rule Mechanics (implemented)

### A. Slingshot Input (select-then-pull)
1. **Select** — tap any of your team's caps. It lights a gold ring (pulsing). Selection is free; switch as much as you want; only a pull+release commits.
2. **Aim** — drag BACK from the selected cap (any direction). A gold preview line shows the resulting fire vector. Pull is clamped to `MAX_PULL` (150px).
3. **Fire** — release. The cap is launched **opposite** the pull (slingshot), with speed on a linear curve `BALL_SPEED_MIN (300) → BALL_SPEED_MAX (1400) px/s` by pull length. A tap with pull < 20px just selects (no fire).
4. **Empty-space tap** — deselects.
5. The trajectory preview shows the resulting vector before release (gold Line2D).

### B. Ball Capture & the Tether (THE core mechanic)
*The ball STICKS to a cap on contact — this is the defining Plato mechanic, not a swipe-the-ball game.*

* **Capture distance:** `CAPTURE_DIST = CAP_RADIUS(44) + BALL_RADIUS(22) = 66px` — ball sticks when a cap comes within contact range.
* **Tether orbit:** the held ball stays a **REAL physics body** orbiting its holder at 66px. Each frame:
  * The ball is projected back onto the 66px contact circle (hard constraint — never through the holder).
  * Only the **radial** velocity component is cancelled; the **tangential** part survives = the orbit (a shove becomes a swing, not a drag-away).
  * If the direct orbit point is blocked (another cap / wall), the target is **swept around the full circle** in small alternating steps to the nearest clear point — the ball slides around blockers with a real rebound, then returns to orbit (no phase-through, no decoupling).
  * `HELD_BALL_SPEED (1500)` cap guarantees the ball can't move far enough per frame to skip past a cap's collision shape.
* **Collision exception:** the held ball never collides with its own holder (that's what the tether replaces). It DOES collide with every other cap and wall — so any hit swings it around the tether.
* **Release rule:** ANY opponent touch of the HOLDER **or** of the BALL breaks the tether — possession is lost immediately (turn passes). Teammate or wall contact just orbits.
* **Momentum carry:** the arriving ball shoves the receiver — cap + ball glide together (0.15 carry, feel-tuned).

### C. Pass Chains (3 / 5 / ∞)
* Possession play is a **pass chain**: the ball sticks only to **your own team's** caps, one catch per pass.
* `pass_limit` is a match setting: **3 / 5 / ∞** passes per turn (default 3).
* **Striker exclusion:** the ball can never stick to the cap that just launched/kicked it — no self-pass. 
* After the chain is spent (no passes left), further own-team contact is a **pure physics bounce** — you must shoot.
* Opponent contact is always pure physics — the ball bounces and keeps flying.
* Catching a pass resets the turn timer (`TURN_SECONDS`) — the chain continues.

### D. Physics Settling & Turn Resolution
Input stays locked (`FLIGHT`) until the turn resolves:
```gdscript
# every FLIGHT frame, in priority order:
# 1. strike check — launcher closes the gap and kicks the free ball
# 2. goal check — ball center crossed the goal line within GOAL_WIDTH?
# 3. capture check — ball within 66px of an own cap (passes left, not the striker)?
# 4. die check — ball velocity < STOP_THRESHOLD after MIN_FLIGHT_TIME:
#      captured → turn continues (TURN_START)
#      free     → possession lost, turn passes
```
* **Goal:** `detect_goal()` — ball center `y < 0` (top goal) or `y > PITCH.y` (bottom goal) within `GOAL_WIDTH` of center → score, then kickoff from center spot (ball FREE; the kicking player collects it by dragging a cap onto it).
* **Speed clamps:** `MAX_BALL_SPEED (2600)` prevents wall-tunnel double-hits (43px/frame < wall+ball); held-ball clamp prevents phase-through.

### E. Goal Pockets & Containment
* Each goal mouth (160px wide, wider than a cap at 88px) is backed by a **pocket**: side + back walls (20px thick, 36px deep) behind the goal line.
* Caps and the ball can NEVER leave the table — they bounce inside the net pocket and come back out. (Prevents the escape bug where a cap flicked into the mouth flew off the pitch forever.)
* Goal posts (14px radius circles) sit at the mouth corners.

### F. Timeout & AFK Enforcement Rule
1. If the 15-second turn clock hits `0.0` without input:
   * The turn immediately ends.
   * Player forfeits their shot attempt.
   * `consecutive_timeouts` counter increments by +1.
2. If `consecutive_timeouts == 3`:
   * Match ends immediately.
   * Opponent is awarded an instant 5–0 technical victory.
   * Forfeiting player's opponent records a win (kind 1050 with `f:"true"`); the forfeiting player does not.

### G. Win & Rematch
* First player to reach 5 goals wins immediately.
* Post-match: winner publishes kind-1050 result event (networking, Part 4); both players offered a rematch (same formations re-picked) **[planned]**.

---

## 5. Implemented vs Deferred (Part 1 status)

**Implemented (Part 1 — current build):** capture/stick + tether orbit, pass chains 3/5/∞, slingshot input, goal pockets, first-to-5, 15s clock, 3-strike forfeit, speed clamps, board centering + keep-aspect rendering.

**Deferred:**
* **Team select / formation pick / full pre-match flow** — Part 2 (fixed 2-2-1 formation in the current build).
* **Active / Simultaneous Mode** (Plato's "Active" game mode — both players act at the same time) — requires real-time state sync and input prediction; re-evaluate Netfox-class networking if ever added. Tactical mode is the v1 scope.
* **Sounds, juice (particles/shake)** — post-design pass.
