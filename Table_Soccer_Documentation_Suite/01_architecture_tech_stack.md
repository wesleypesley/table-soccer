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
* **Physics Model:**
  * Sub-stepping enabled for rigid body collisions.
  * Friction (`linear_damp`, `angular_damp`) configured for realistic cap gliding on turf surfaces.
  * Pure 2D top-down perspective using orthographic rendering with high-resolution vector/pre-rendered sprites, drop shadows, and visual glows.
* **Build Size:** Optimized lightweight export template (~30 MB to 50 MB total APK size).

### B. Nostr Protocol (Decentralized Signaling & Matchmaking)
* **Role:** Handles peer discovery, room creation, invitation exchanges, and match signaling without requiring a centralized game server.
* **Implementation:**
  * Players publish NIP-01 / NIP-04 / NIP-44 encrypted events containing session descriptors and WebRTC offer/answer SDP payloads.
  * Decentralized relay networks ensure 100% uptime without server maintenance costs.

### C. WebRTC (Direct Peer-to-Peer Transport)
* **Role:** Ultra-low latency binary data channel between connected devices.
* **Data Transmitted:** Shot vector forces $(\theta, F)$, turn state signals, match result events (kind 1050), and sync ticks.

### D. Offnetic Core (Networking — Reused, Not Rebuilt)
* **Role:** All networking lives in the **offnetic Kotlin core**, reused as-is: Nostr identity (npub keypair), relay pool management, NIP-44 encrypted DMs, WebRTC PeerConnection/ICE, NAT traversal, and reconnection logic.
* **Game transport:** A thin game protocol over **WebRTC DataChannels** (new code path — offnetic uses media tracks today):
  * Reliable channel: turn state, shot vectors (θ, F), settle confirmations, match result.
  * Unreliable channel (optional): live tick updates for spectators/feel.
* **Physics authority:** One peer per match runs the Godot sim; the other sends inputs and renders. No cross-device physics determinism required (single sim → nothing to disagree about).
* **No Netfox in v1.** Netfox is built for continuous real-time sync (prediction/rollback) — dead weight for a turn-based game with a settle-then-evaluate loop. Revisit only if 2v2/real-time simultaneous play is added later.

### E. Kotlin (Native Android UI & Application Shell)
* **Role:** Manages native system overlays, platform performance settings, push notifications, local storage (EncryptedSharedPreferences / SQLite), and user settings dashboard.
