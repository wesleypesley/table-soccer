# Software Requirements Specification (SRS) Index
## Table Soccer Mobile Game Project (MVP)

### Executive Overview
This document consolidates the complete functional and technical specification suite for the competitive 2D Table Soccer mobile application — fully peer-to-peer, **no central server**. Networking reuses the **offnetic core** (Nostr identity/signaling + WebRTC). No leaderboard or Elo in v1; social features are player search, profile wins, and friend requests.

---

### Specification Modules Index

1. **[Architecture & Tech Stack Spec](./01_architecture_tech_stack.md)**
   * Engine: Godot 4 (2D physics, rigid body caps)
   * UI & OS Shell: Kotlin
   * Networking: offnetic core (Nostr signaling + WebRTC data channels), thin game protocol, no Netfox in v1

2. **[Gameplay & Turn System Spec](./02_gameplay_turn_system.md)**
   * Plato Table Soccer Tactical-style gameplay: turn-based, **select-then-pull slingshot** input.
   * **Ball capture / pass chains (Part 1 core):** ball sticks to a cap on contact (tether orbit at 66px), 3/5/∞ pass limit, striker excluded, release on any opponent touch.
   * First-to-5-goals win condition (no clock, no ties), 15-second turn timer.
   * 3-Strike AFK penalty rule; pre-match formation + team select **[planned — Part 2]**.
   * Active/simultaneous mode deferred (needs real-time networking).
   * **Status: Part 1 (core gameplay + visuals) implemented.**

3. **[Bot AI Spec](./03_bot_ai_spec.md)**
   * Bot = input source in the same match FSM (no ML, no server).
   * 3 tiers: Easy / Hard / Nightmare (noise-controlled difficulty).
   * Decision pipeline: cap selection → candidate shots → physics-sim evaluation.
   * Bot matches never publish kind-1050 (no win inflation).

4. **[Identity, Search & Social Spec](./04_identity_and_search.md)**
   * Immutable identity: Nostr npub (permanent, never changes).
   * Mutable cosmetics: display name + avatar (kind-0 replaceable events, non-unique names).
   * Search: exact npub lookup (direct relay) + display-name search (NIP-50 / nostr.band).
   * Profile: wins count from signed match-result events (kind 1050).
   * Friend requests via encrypted DM; friends list = kind-3 contact list event.

---

### Removed for MVP Scope
* **Elo Rating & Ranking System** (formerly 03) — cut; no ratings in v1.
* **Monthly Leaderboards** (formerly 05) — cut; global leaderboard requires an aggregator.
* **Decentralized Leaderboard Spec** (formerly 06) — cut; search + wins cover v1 social needs.
