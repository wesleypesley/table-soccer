# User Identity, Search & Social Specification

## 1. Identity Model

### 1.1 Immutable Identity Key (npub)
* **Format:** Nostr `npub` public key (bech32, ~63 chars, always starts `npub1`), generated on first app launch.
* **Properties:** Permanently assigned, globally unique, **never changes**. It is the passport number — everything (wins, friend list, match events, friend requests) is keyed to it.
* **Usage:** Search by exact ID, match-result event signing, friend requests, profile lookup.

### 1.2 Mutable Cosmetics (Display Name + Avatar)
* **Format:** Display name 3–16 chars (alphanumeric + underscore, profanity-filtered), avatar image.
* **Properties:** **Non-unique** (multiple "Saleh" allowed), fully customizable anytime.
* **Persistence:** Profiles are **kind-0 replaceable events** — editing publishes a new signed kind-0; relays keep only the **latest** per npub. Everyone's app fetches the latest → always sees current name/avatar.
* **Who can change a profile:** ONLY the player holding the private key. Relays, other players, and the developer cannot forge a kind-0 event. The relay is storage, not authority.

### 1.3 Core Design Rule
**Never store a name where an npub should be.**
Names and avatars are cosmetic display data — re-fetched, never trusted as identity. All stored references (friends list, match events, search results) use npubs. Renames and avatar changes therefore never break wins, friendships, or matches — behavior mirrors WhatsApp contact photo changes.

---

## 2. Player Search

Two search paths, one search bar. The app auto-detects input type:

### 2.1 Exact Player ID Lookup (Primary)
* User pastes an `npub1...` string (or scans a QR code).
* App queries any relay directly: `REQ {"kinds":[0], "authors":["<npub>"]}`.
* Returns the **exact single profile** instantly. No index required — works always, even if name search fails.

### 2.2 Display Name Search (Secondary)
* User types a name (e.g., "Saleh").
* App queries **nostr.band** (NIP-50 search relay, pre-built index of profiles from all known relays): `REQ {"kinds":[0], "search":"saleh", "limit":20}`.
* Returns a **ranked list** of matching profiles — names are non-unique, so multiple hits are expected.

### 2.3 Search Result Row
Each result shows: avatar, display name, short npub suffix (e.g., `Saleh_Striker …k5s2`), and wins count. The **Add/Challenge action targets the npub, never the name**.

### 2.4 Disambiguation UX
* Name query returns exactly 1 profile → show it directly.
* Multiple profiles → show the list; user picks by avatar / npub suffix / wins.
* This is the entire anti-impersonation surface: npub suffixes cannot be faked.

---

## 3. Player Profile

Profile view (own or any searched player) shows:
* Display name + avatar (latest kind-0)
* npub suffix (copyable full npub / shareable QR)
* **Wins count** — see §4.

---

## 4. Match Result Event (kind 1050) & Wins

### 4.1 Event Schema
```
{
  "kind": 1050,
  "pubkey": <winner_npub>,
  "created_at": <unix_seconds>,
  "tags": [
    ["p", <loser_npub>],
    ["e", <match_session_id>],
    ["s", "4-2"],
    ["f", "false"]        // "true" = technical forfeit (AFK)
  ],
  "content": "{\"mode\":\"1v1\",\"game_version\":\"1.0.0\"}"
}
```

### 4.2 Rules
* Winner publishes after `MATCH_OVER`. **No confirmation event required** — single signature (forfeits are single-sig by necessity).
* **No Elo, no ratings anywhere.** The event records the fact; wins are derived by counting.

### 4.3 Wins Count (client-side, deterministic)
* Wins = count of kind-1050 events where `pubkey` (author) = player's npub.
* **Count by distinct session id (`e` tag), never by event id** — prevents double-counting the same match republished with a fresh event id.
* Both players' apps and any third-party app compute the identical number from the same events.

---

## 5. Friend Requests & Friends List

1. **Add (+ button):** App sends an encrypted DM (NIP-44 via offnetic's existing DM path) with a friend-request payload to the target npub.
2. **Accept:** Recipient accepts; **both npubs** are written into a **kind-3 contact list event** (NIP-02 — the standard Nostr "friends list").
3. **Result:** Friends list = npubs + cached display data (name/avatar snapshot at add-time). Survives renames, syncs across the player's devices, and is readable by any Nostr app.

### 5.1 Optional UX (v1.1)
* If a friend's current kind-0 name differs from the cached snapshot, show a small "renamed" marker.

---

## 6. Edge Cases

| Case | Behavior |
| :--- | :--- |
| Player renames / changes avatar | Nothing breaks — npub unchanged, wins intact, friends intact. Search index may briefly show the old name (minutes/hours); tapping the result fetches the correct current profile by npub. |
| Impersonation (someone copies a friend's name) | Non-unique names allowed; disambiguate via npub suffix + avatar. No name claim system in v1. |
| Relay keeps stale kind-0 | Harmless — app queries a relay pool; player republishes to all relays. |
| Duplicate names in search | Expected — list UI with disambiguation (§2.4). |
| Double-published match result | Wins counted by session id (`e` tag), so the same match never counts twice. |
