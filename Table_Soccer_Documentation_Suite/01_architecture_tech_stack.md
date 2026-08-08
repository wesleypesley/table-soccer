# Technical Architecture & Stack Specification

## 1. System Architecture Overview
The application is a lightweight, competitive 2D table soccer mobile game designed for peer-to-peer (P2P) real-time and turn-based gameplay. The architecture splits responsibilities cleanly between rendering/physics (Godot 4), networking/P2P connectivity (Nostr + WebRTC via the offnetic core), and native OS integration/UI (Kotlin).

```
┌─────────────────────────────────────────────────────────┐
│                   Kotlin Native Layer                   │
│  (OS Bindings, UI Framework, Storage & Auth,           │
│   Offnetic Core: Nostr identity/signaling + WebRTC)    │
└───────────────────────────┬─────────────────────────────┘
                            │ (thin event bridge)
┌───────────────────────────▼─────────────────────────────┐
│                 Godot 4 Game Engine                     │
│      (2D Physics, RigidBody Caps, Render Pipeline)      │
└─────────────────────────────────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
┌───────────▼───────────┐       ┌───────────▼───────────┐
│     Nostr Relay       │       │    WebRTC P2P         │
│ (Signaling, profiles, │       │ (Game Data Channels:  │
│  DMs, match events)   │       │  shots, turn state)   │
└───────────────────────┘       └───────────────────────┘
```

---

## 2. Component Stack Breakdown

### A. Godot 4 (Game Engine & 2D Physics Core)
* **Role:** Handles 2D pitch rendering, custom cap physics (`RigidBody2D`), particle effects, vector trajectory previews, and local simulation.
* **Physics Model (implemented):**
  * `RigidBody2D` caps (mass 15) + ball (mass 0.5), `linear_damp` gliding, physics material friction/bounce.
  * Ball uses `continuous_cd` (cast shape) against wall tunneling; `contact_monitor` for the release rule.
  * **Tether system** (Part 1 core): the held ball is a real body projected onto the 66px contact circle each frame (radial velocity cancelled, tangential kept = orbit); blocked orbit points resolved by a full-circle sweep; collision exception with the holder only. Release on ANY opponent touch of holder or ball.
* **Rendering (implemented):**
  * **Pure `_draw()` canvas rendering — no canvas-item shaders.** Shader experiment rendered discs invisible (VERTEX isn't local-space in the fragment stage); layered `draw_circle`/`draw_rect`/`draw_arc` + baked `ImageTexture`s are the verified approach.
  * Sphere-shaded tokens via baked 128×128 radial-gradient textures (2 bakes cached per team).
  * Grass-noise tile + mowed stripes, wood-grain frame, FIFA markings, goal pockets — all procedural, zero external assets.
  * MSAA 2D enabled (project setting) for crisp vector edges.
* **Board centering & aspect:** board node centered in the 1080×1920 canvas (offset 180,420); input converted with `board.to_local()`. Project uses `keep` aspect so the full table is always visible (letterboxed on odd windows).
* **Build Size:** Optimized lightweight export template (~30 MB to 50 MB total APK size).

### A2. Design Token System (`scripts/design.gd`)
Single source of truth for all geometry, physics and color — every script reads from it (no scattered hardcoded values that break on different screen sizes):
* **Geometry:** CANVAS 1080×1920, PITCH 720×1080, CAP_RADIUS 44, BALL_RADIUS 22, WALL_THICKNESS 20, GOAL_WIDTH 160, CAPTURE_DIST 66 (= 44+22), pocket depth.
* **Physics feel:** CAP_MASS 15, BALL_MASS 0.5, damp values, speed clamps (MAX_BALL_SPEED 2600 tunnel guard, HELD_BALL_SPEED 1500 phase-through guard).
* **Palette:** measured from the real Plato screenshot — deep felt `#436327`, wood frame `#7a5230`, team blue `#4285F4` / red `#E94235`, selection gold `#FBBC05`, HUD `#1A1B1E`.
* **Pitch markings:** real football proportions (penalty area 420×170, goal area 190×55, spot 113px, arcs, corner arcs).

### B. Nostr Protocol (Decentralized Signaling & Matchmaking)
* **Role:** Handles peer discovery, room creation, invitation exchanges, and match signaling without requiring a centralized game server.
* **Implementation:**
  * Players publish NIP-01 / NIP-04 / NIP-44 encrypted events containing session descriptors and WebRTC offer/answer SDP payloads.
  * Decentralized relay networks ensure 100% uptime without server maintenance costs.

### C. WebRTC (Direct Peer-to-Peer Transport)
* **Role:** Ultra-low latency binary data channel between connected devices.
* **Data Transmitted:** Shot pull vectors (capId, direction, power), turn state signals, match result events (kind 1050), and sync ticks.

### D. Offnetic Core (Networking — Reused, Not Rebuilt)
* **Role:** All networking lives in the **offnetic Kotlin core**, reused as-is: Nostr identity (npub keypair), relay pool management, NIP-44 encrypted DMs, WebRTC PeerConnection/ICE, NAT traversal, and reconnection logic.
* **Game transport:** A thin game protocol over **WebRTC DataChannels** (new code path — offnetic uses media tracks today):
  * Reliable channel: turn state, shot pull vectors (capId, direction, power), settle confirmations, match result.
  * Unreliable channel (optional): live tick updates for spectators/feel.
* **Physics authority:** One peer per match runs the Godot sim; the other sends inputs and renders. No cross-device physics determinism required (single sim → nothing to disagree about).
* **No Netfox in v1.** Netfox is built for continuous real-time sync (prediction/rollback) — dead weight for a turn-based game with a settle-then-evaluate loop. Revisit only if 2v2/real-time simultaneous play is added later.

### E. Kotlin (Native Android UI & Application Shell)
* **Role:** Manages native system overlays, platform performance settings, push notifications, local storage (EncryptedSharedPreferences / SQLite), and user settings dashboard.

---

## 3. Implemented Part-1 File Layout (Godot)

```
project.godot          viewport 1080x1920, canvas_items stretch, keep aspect, MSAA 2D
scenes/main.gd         root Node2D: builds Board (centered), TurnManager, HUD
scripts/design.gd      Design tokens — geometry, physics feel, palette, markings
scripts/board.gd       physics core: pitch walls + goal pockets, 10 caps, ball;
                       spawns visuals, shadows; detect_goal()/reset_ball()
scripts/turn_manager.gd  match FSM (TURN_START/FLIGHT/MATCH_OVER), slingshot
                       input, tether orbit + full-circle sweep, pass chains,
                       capture/release rules, timeout/forfeit, team glow
scripts/pitch_draw.gd  wood frame + grass tile + FIFA markings + goals (pure _draw)
scripts/cap_disc.gd    baked sphere token texture + team glow (pure _draw)
scripts/ball_disc.gd   baked sphere ball (pure _draw)
scripts/cap_draw.gd    pulsing gold selection ring
scripts/shadow_layer.gd  world-space drop shadows (board space)
scripts/avatar_draw.gd HUD avatar discs
scripts/hud.gd         top bar: avatars, score, goals-to-win, turn, timer bar
```

* **Scene construction is fully procedural** — no hand-placed editor nodes; everything is built in `_ready()` from the Design tokens (keeps geometry in one place, no scene-file drift).
* **Known duplication:** `turn_manager.gd` still redefines CAP_RADIUS/BALL_RADIUS/PITCH (legacy); the constants refactor (board.gd as single geometry source) is queued.
