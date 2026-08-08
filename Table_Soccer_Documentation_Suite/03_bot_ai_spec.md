# Bot AI Specification

## 1. Overview

The AI opponent is **not a separate system** — it is an input source inside the same match FSM as a human player:

```
Human player:  touch input            →  (capId, θ, F)
Bot player:    decideShot(gameState)  →  (capId, θ, F)
```

* Bot matches run **locally** — no networking, no relays, no server.
* Same FSM, same physics, same win conditions as player-vs-player matches.
* **No machine learning, no training data.** Pure deterministic logic + the game's own physics simulation.

---

## 2. Difficulty Tiers

| Tier | Noise (angle/force) | Cap selection | Candidate pool |
| :--- | :--- | :--- | :--- |
| **Easy** | High | Sometimes random | Picks any reasonable shot |
| **Hard** | Small | Always best-positioned | Picks from top 5 candidates |
| **Nightmare** | Zero | Always best-positioned | Always the single best candidate |

* Nightmare plays *perfect table soccer* — near-unbeatable by design. It is a bragging-rights mode, not a ladder.
* No unlock gating — all 3 tiers available from day one.

---

## 3. Decision Pipeline (per turn)

1. **Cap selection** — choose the cap closest to the ball / best positioned for the current objective (attack if ball on opponent half, clear if ball near own goal).
2. **Candidate generation** — produce 20–50 candidate shot vectors (θ, F) covering: direct goal shots, passes to advancing caps, clears, and edge angles.
3. **Evaluation** — run each candidate through the **real physics simulation** (same code as a human's shot) and score the resulting end-state.
4. **Selection** — pick the highest-scoring candidate (with tier noise applied).

### Scoring function (draft)

```
Goal scored                    → +1000
Ball closer to opponent goal   → +proximity bonus
Ball left in own half          → penalty
Ball rebound to opponent's cap → penalty
Ball out of play               → heavy penalty
```

---

## 4. Match Integration

| Aspect | Behavior |
| :--- | :--- |
| Match creation | Same match flow, bot registered as the opponent input source |
| Turn timing | Bot "thinks" within the 15s turn clock (fast, sub-second) |
| Physics | Host-side sim, identical to human matches |
| **Win counting** | **Bot matches do NOT publish kind-1050 events** — bot wins must never inflate profile win counts |
| Match history | Local-only record (device storage), not relay events |

---

## 5. Implementation Notes

* Bot logic: ~150–250 lines (cap selection + candidate generation + evaluation).
* Reuses the match FSM end-to-end — the cheapest feature in the project.
* Difficulty tuning = one afternoon of playtesting against the noise parameters.

---

## 6. Deferred Decisions (decide at build time)

* Whether Nightmare gets a tiny "blink" (small noise every ~10th shot) so a great player can occasionally score — or stays literally unbeatable.
* Exact scoring weights for the evaluation function.
* Whether bot matches appear in any player-facing history UI.
