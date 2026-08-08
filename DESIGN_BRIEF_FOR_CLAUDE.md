# Design Brief — for Claude (or any AI working on TableSoccer visuals)

You are taking over the **visual/design layer** of a Godot 4.7 table-soccer game that mimics **Plato Table Soccer (Tactical mode)**. The gameplay physics are DONE and verified (see `PHYSICS_BRIEF_FOR_CLAUDE.md` in the same repo). Your job: make the game **look like the real Plato app** — vibrant, polished, with depth — using the design tokens and rendering approach already in place. Do NOT touch gameplay logic, physics, or the tether.

> **THE DESIGN GOAL, ABOVE ALL ELSE:** the finished game must look and feel **as close to the real Plato Table Soccer as possible** — same visual identity, same proportions, same vibe. When you are deciding between two options and one brings the game closer to Plato's look, choose that one, always. The real Plato screenshot (user-provided, measured in §5) is the **visual spec**; the Design tokens in `design.gd` encode it. If you ever find yourself designing something that does not exist in real Plato, stop and ask — it is probably wrong.

---

## 0. The ONE rule: verify every visual change with a screenshot + pixel analysis

You cannot "see" the game, and neither can the user trust a description. Every change MUST be verified by:
1. **Restarting the game fresh** (stop → run) after EVERY change. Visual scripts are `_draw()`-based; hot-reload can show stale frames.
2. Capturing an in-game screenshot via game_eval (`get_viewport().get_texture().get_image()`, save to `user://`, copy it out) — NOT the editor screenshot tool (can return stale frames when the window is backgrounded).
3. **Pixel-sampling the PNG with Python/PIL** — report exact RGB values at key points (felt, wood, cap centers, ring, HUD panel) so "it renders" is a measured fact, not a guess.
4. The user reviews the actual screenshot and gives the final call. **Their eye is the spec.**

Reference screenshots exist: `C:\Users\Admin\TableSoccer\pitch_preview_v11.png` (current state) and the real Plato screenshot the user provided (analyzed in §5).

---

## 1. Project layout & which files are yours

- Project root: `C:\Users\Admin\TableSoccer`
- **Engine:** Godot 4.7.1 (viewport 1080x1920, stretch `canvas_items`, aspect `keep`, MSAA 2D)
- Everything is **procedural** — no external art assets, no editor-placed nodes. All drawing happens in `_draw()`.
- **Files that are YOURS (visuals only):**
  - `scripts/design.gd` — **Design tokens: THE single source of truth.** Colors, geometry, spacing. Change values here, never hardcode.
  - `scripts/pitch_draw.gd` — table: wood frame, felt, grass stripes, FIFA markings, walls, goals.
  - `scripts/cap_disc.gd` — cap token: baked sphere texture + white rim + team glow.
  - `scripts/ball_disc.gd` — ball: baked sphere + pentagon dots.
  - `scripts/cap_draw.gd` — gold selection ring (pulsing).
  - `scripts/shadow_layer.gd` — drop shadows under pieces.
  - `scripts/avatar_draw.gd` — HUD avatar discs.
  - `scripts/hud.gd` — top bar HUD (score, avatars, timer).
- **Files that are NOT yours (leave completely alone):** `board.gd` (physics + spawns visuals — you may only change token-driven colors it reads), `turn_manager.gd` (gameplay FSM — has a `_preview` Line2D and team-glow calls that read Design tokens; do not restructure), `scenes/main.gd` (board centering — fixed).
- Board node is centered at (180,420) in the canvas — all draw code already accounts for this via Design tokens; don't "fix" positions.

---

## 2. The rendering approach — read this twice, it cost us hours

**NO canvas-item shaders. Ever.** We shipped shaders once (`ShaderMaterial` with `shader_type canvas_item`) and every disc rendered **invisible** — `length(VERTEX)` in the fragment stage is NOT local-space distance as expected, so the radial-gradient math produced alpha=0. The ball and caps drew nothing while the plain `_draw()` pitch rendered fine.

**The verified approach — pure `_draw()` + baked ImageTextures:**
- Layered `draw_circle` / `draw_rect` / `draw_arc` for gradients (multiple translucent layers = smooth falloff).
- **Baked `ImageTexture`** for anything expensive or needing a true radial gradient: build a 128×128 `Image` once per color (seeded RNG or math), cache it in a `static var` dictionary, `draw_texture_rect` it. (See `cap_disc.gd _get_token_texture()` — the pattern to copy.)
- `GradientTexture2D` is banned — misuse of `fill_from`/`fill_to` (pixel coords vs UV) produced a pure-white garbage frame.
- MSAA 2D is on (project setting) — lines/circles are already anti-aliased; don't add manual AA.

**If you feel a shader is unavoidable, stop and ask.** Every visual in the real Plato app can be done with layered draws + baked textures.

---

## 3. Current design state (verified, don't regress)

| Element | Current implementation | Verified |
| :--- | :--- | :--- |
| **Palette** | Measured from real Plato screenshot → `design.gd` tokens (felt `#436327`, wood `#7a5230`, blue `#4285F4`, red `#E94235`, gold `#FBBC05`, HUD `#1A1B1E`) | ✓ pixel-sampled |
| **Table frame** | Procedural mottled wood: seeded RNG streaks + knots, full-canvas behind felt | ✓ |
| **Felt** | Grass-noise tile (baked, seeded) + alternating mow stripes (~8%) + top-light falloff | ✓ |
| **Markings** | FIFA proportions: center circle 94px, penalty area 420×170, goal area 190×55, penalty spots 113px, D-arcs, corner arcs | ✓ |
| **Caps** | Baked sphere texture (radial gradient, dark rim → light upper-left) + white rim ring 4px + inner core + specular + **pulsing team glow** (whole active team) + gold selection ring (pulse tween) | ✓ |
| **Ball** | Baked sphere + 3 pentagon dots + specular | ✓ |
| **Shadows** | Multi-layer dark ellipses under caps+ball, board-space (don't rotate with pieces) | ✓ |
| **Goals** | Dark pocket + net crosshatch + wall frame + lit posts + goal-line edge | ✓ |
| **HUD** | Top bar: dark rounded panel, P0/P1 avatar discs (gold ring on active), score "0 - 0", "Goals to win: 5", turn label, thin red timer bar | ✓ |
| **Centering/aspect** | Board centered in canvas; `keep` aspect letterboxes on odd windows; clear color = TABLE_BG | ✓ |

---

## 4. Design task list (priority order)

### D1. HUD polish — biggest remaining gap vs the real Plato screenshot
Current HUD works but is plain: text is the default Godot font, avatars are placeholder "P0"/"P1" letters on colored discs, no player names.
- Real Plato has: **circular avatar images** (photo or icon), **player display names**, score in the center, "Goals to win: X", a **turn indicator pill** ("Your Turn"), and a thin timer bar.
- Since we have no photo assets: build **procedural avatars** (team-colored disc + white ring + a simple generated face/initials — the initials placeholder is acceptable for now, or ask the user for avatar images).
- Consider a **Godot Theme** (`.tres`) or per-widget `add_theme_*_override` for consistent typography: font sizes, weights, colors from tokens. Keep it token-driven (HUD_* constants exist).
- **Safe area:** use `DisplayServer.get_display_safe_area()` so the top bar doesn't collide with phone notches/status bars. Currently the HUD is hard-positioned at y=0..150 — on a notched phone it will sit under the status bar.
- Keep `root.mouse_filter = MOUSE_FILTER_IGNORE` so the HUD never steals game input.

### D2. Cap size — agreed direction, NOT yet applied (touches physics, coordinate with physics brief)
- User said "the caps are too big and they don't feel right." Measured real Plato: cap ≈ 10.2% of field width; ours = 88px/720 = 12.2%. **Target: CAP_RADIUS 44 → ~34** (68px = 9.4%).
- ⚠️ This changes `CAPTURE_DIST` (66 → 50), tether orbit, release thresholds, and visual scaling — it is NOT a visual-only change. **Coordinate with the physics work first** (or do the token change + visual re-scale, then have the physics brief's test suite re-verify). Do not shrink visuals without shrinking colliders — they must match.

### D3. Depth & "alive" feel — juice pass (sounds are deferred, these are visual only)
- **Screen shake** on hard hits/goals: `Camera2D` + a few lines (offset decays each frame). Built-in, no assets.
- **Impact particles**: `GPUParticles2D` burst when the cap strikes the ball / ball hits the wall. Built-in.
- **Ball trail**: fading trail while in flight (Line2D or particles).
- **Selection feedback**: the gold ring pulses already; add a subtle **scale tween** on the selected cap ("lift" feel).
- **Goal flash**: brief overlay flash + score pop animation on `_on_goal`.
- All of these are Godot built-in nodes — **no asset packs, no shaders**. Keep them subtle; Plato is crisp, not chaotic.

### D4. Menu / pre-match screens **[planned — Part 2, design ahead]**
Not in the current build (match starts immediately), but the docs specify: team select (cosmetic colors), formation pick (attacking/defending), kickoff determination. If you build any screens: use the same token palette + wood/felt motifs, portrait layout, and Design-driven spacing. **Ask before building** — it may land in Part 2 with the turn FSM work.

### D5. Anything in the real screenshot we haven't matched (audit against §5)
Do a visual diff of our `pitch_preview_v11.png` against the real Plato screenshot (analyze both with PIL, compare: felt tone, cap ring prominence, wall/frame look, HUD layout, ball size/pattern). List concrete deltas and propose fixes. **Do NOT add** bleachers/crowd, corner flags, or icons on caps — the real screenshot doesn't have them (a previous AI hallucinated these from a different reference; the user rejected them).

---

## 5. The real Plato reference (measured, not guessed)

User provided a real screenshot (`Screenshot_2026-08-08-17-27-46-88_...jpg`, 1264×2780). Measurements extracted with PIL:
- **Felt:** deep muted green ≈ `#436327` (NOT the bright `#34A853` we started with).
- **Table frame:** mottled wood — tans/browns (`#7a5230` base, lighter `#a37a4e`, darker `#54371f`, knots `#3d2a16`), textured grain, NOT flat charcoal.
- **Caps:** solid team color (blue `#4285F4` / red `#E94235`) with a **crisp white ring**, ~10.2% of field width; ball white, ~40-50% of cap diameter.
- **Pitch:** full portrait layout; white lines crisp on the deep felt; center circle + penalty boxes; goal mouth at top/bottom center.
- **Top HUD:** player avatars + score + turn info on a dark bar.
- **Bottom:** chat/UI strip (out of scope for the board).

Google AI Overview research (authoritative): 9:16 portrait; pitch 70-75% of canvas height; cap 8-10% of field width; ball 40-50% of cap diameter; white lines alpha ~0.95 at 2-3px; active ring neon gold `#FBBC05`; UI panels `#1A1B1E`. All already applied in `design.gd` — keep them.

---

## 6. Constraints (hard rules)

1. **No canvas-item shaders** (§2). No `GradientTexture2D`. Pure `_draw()` + baked `ImageTexture`.
2. **Everything token-driven** — read `design.gd`; never hardcode a color/geometry value in a draw script. User's words: "keep it modular so that we dont fuck up." New values you introduce belong in `design.gd` with a comment.
3. **Do not touch gameplay files** (`turn_manager.gd`, `board.gd` physics, `main.gd` layout). You may edit token colors that they consume.
4. **No asset packs** — procedural only (Kenney CC0 packs are reserved for sounds/fonts later, sounds are deferred).
5. **Screens are portrait** — design for 1080×1920 at `keep` aspect; never assume the full canvas is visible on odd windows (letterbox handles it).
6. **Match the real Plato** — when in doubt, measure the reference screenshot with PIL before inventing.
7. **Don't add what's not in the reference** (no bleachers, no corner flags, no cap icons).
8. **Talk before big changes** — visual direction changes (palette swaps, layout rework) go to the user first. They review every screenshot and have strong opinions (in a good way — their calls are the spec).

---

## 6.5 Verification protocol (mandatory, per change)

```gdscript
# via godot-ai: editor_manage op=game_eval — ONE eval per fresh run
await get_tree().create_timer(0.3).timeout
var img = get_viewport().get_texture().get_image()
img.save_png("user://design_check.png")
# sample the exact pixels you changed — return RGB values
return {"felt": str(img.get_pixel(...)), "cap": str(img.get_pixel(...)), ...}
```
Then copy `user://design_check.png` out (app_userdata dir: `C:\Users\Admin\AppData\Roaming\Godot\app_userdata\Table Soccer\`) and PIL-analyze it. **Board coords → image pixels: image = canvas/2** (canvas 1080×1920 → image 540×960 at 0.5 scale); board coords → canvas = board + (180,420); so image = (board + (180,420)) * 0.5. Screenshot scale math has bitten us before — verify your mapping with a known element (e.g., a cap center) before trusting samples.

---

## 7. Known visual history (don't repeat)

- **Shaders → invisible discs** (§2) — the biggest time sink. Never again.
- **`GradientTexture2D` fill_from/fill_to misuse → white screen.** Banned.
- **Bright `#34A853` felt → user: "plain and bland"** — the real Plato felt is deep `#436327`; palette was re-measured from the user's screenshot.
- **Hard-edged translucent circles for "spotlight" → looked like smudges** — layered alpha needs enough steps/softness; when in doubt, bake it.
- **`var draw` shadowed CanvasItem's `draw` signal** → warning; name draw nodes `disc`/`visual`.
- **Full-width "penalty boxes" → user: "that's not a soccer pitch"** — real FIFA proportions only.
- **Board at origin → pitch in top corner on landscape windows** — fixed by centering (180,420) + `keep` aspect; don't regress.
- Claude's `flick_soccer` (separate folder, different simpler game) has reusable techniques (grass tile, baked sphere) already mined into this project. Its HUD was bare default widgets — do NOT copy that part.

---

## 8. When you're done

Report per task: (1) what you changed (file + token/draw), (2) the pixel-measured result, (3) screenshot path for the user, (4) what you deliberately skipped and why. The user reviews every visual change personally — your screenshot is the deliverable.
