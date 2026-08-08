# Gameplay Mechanics & Turn System Specification

*Design reference: Plato Table Soccer — Tactical mode (turn-based). Same gameplay model, P2P networking underneath.*

## 1. Match Rules & Win Conditions

| Parameter | Setting | Specification Details |
| :--- | :--- | :--- |
| **Win Condition** | First to 5 goals | First player to reach 5 goals wins. **No match clock, no ties, no configurable goal count.** |
| **Turn Clock** | 15 Seconds | Max time per turn to aim and fire. |
| **AFK Forfeit Rule** | 3 Strikes | 3 consecutive timeouts (45s) results in instant forfeit. |
| **Input** | Swipe to shoot | Swipe direction = shot angle (θ), swipe speed = shot power (F). One swipe = one action. |

## 2. Pre-Match Setup

Before the match begins, both players complete:

1. **Select Team** — cosmetic: pick side colors / kit.
2. **Choose Formation** — tactical decision based on who starts with the ball:
   * **Attacking Formation** — used when *you* start with the ball.
   * **Defending Formation** — used when your *opponent* starts with the ball.
3. Kickoff player is determined (random or by prior match), then the match starts.

## 3. Match Finite State Machine (FSM)

```
       ┌─────────────────┐
       │   MATCH_START   │ (Team select + formation pick, determine kickoff)
       └────────┬────────┘
                │
┌───────────────▼───────────────┐
│          TURN_START           │◄─────────────────────────────┐
│ (Reset 15s clock, unlock input│                              │
└───────────────┬───────────────┘                              │
                │                                              │
┌───────────────▼───────────────┐                              │
│            AIMING             │─────── (15s Timeout) ──────┐ │
│  (Active player swipes to    │                            │ │
│   aim & fire)                │                            │ │
└───────────────┬───────────────┘                            │ │
                │ (Shot Released)                            │ │
┌───────────────▼───────────────┐                            │ │
│       SIMULATING_PHYSICS      │◄───────────────────────────┘ │
│  (Lock input, wait for stop)  │                              │
└───────────────┬───────────────┘                              │
                │ (All bodies velocity < 5.0 px/s)             │
┌───────────────▼───────────────┐                              │
│         EVALUATE_TURN         │                              │
└───────┬─────────────────┬─────┘                              │
        │ (Goal Scored)   │ (No Goal)                          │
        ▼                 └────────────────────────────────────┤
┌───────────────┐                                              │
│ CHECK_WINNER  ├─────── (Score == N) ─────────────────► MATCH_OVER
└───────┬───────┘                                              │
        │ (Score < N)                                          │
        └──────────────────────────────────────────────────────┘
```

* No Golden Goal — impossible: the match only ends when someone reaches 5 goals.
* No match clock — play continues until the goal target is hit.

## 4. Detailed Rule Mechanics

### A. Swipe Input Mapping
* The active player swipes on the board: **swipe direction** = shot angle (θ), **swipe speed** = shot power (F).
* Swipe can be aimed from the ball or the active player's cap toward the target; the trajectory preview shows the resulting vector before release.
* A low-power swipe toward a teammate's cap = a **pass**; a high-power swipe toward the goal = a **shot**.
* Passing between caps is the core of possession play: "Pass the ball between your players to maintain possession and open up opportunities."

### B. Physics Settling Criteria
Input remains disabled until all 10 player caps and the ball come to a complete rest:
```gdscript
func is_physics_settled() -> bool:
    var SLEEP_THRESHOLD = 5.0 # pixels per second
    if ball.linear_velocity.length() > SLEEP_THRESHOLD:
        return false
    for cap in all_caps:
        if cap.linear_velocity.length() > SLEEP_THRESHOLD:
            return false
    return true
```

### C. Timeout & AFK Enforcement Rule
1. If the 15-second turn clock hits `0.0` without input:
   * The turn immediately ends.
   * Player forfeits their shot attempt.
   * `consecutive_timeouts` counter increments by +1.
2. If `consecutive_timeouts == 3`:
   * Match ends immediately.
   * Opponent is awarded an instant 5–0 technical victory.
   * Forfeiting player's opponent records a win (kind 1050 with `f:"true"`); the forfeiting player does not.

### D. Win & Rematch
* First player to reach 5 goals wins immediately at `CHECK_WINNER`.
* Post-match: winner publishes kind-1050 result event; both players offered a rematch (same formations re-picked).

---

## 5. Deferred Items (not in v1)

* **Active / Simultaneous Mode** (Plato's "Active" game mode — both players act at the same time). Requires real-time state sync and input prediction — re-evaluate Netfox-class networking if this is ever added. Tactical mode is the v1 scope.
