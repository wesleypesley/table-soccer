class_name Design
## Design tokens — single source of truth for the game's look & geometry.
## Every script reads from here; never hardcode a color or a dimension.
## Usage: Design.PITCH, Design.CAP_BLUE, etc.

# --- canvas / layout ---------------------------------------------------------
const CANVAS := Vector2(1080.0, 1920.0)      # design canvas (stretch mode, portrait)

# --- pitch geometry (single source; replaces board.gd / turn_manager.gd dupes) ---
const PITCH := Vector2(720.0, 1080.0)
const GOAL_WIDTH := 160.0                    # centered on top/bottom
const CAP_RADIUS := 44.0
const BALL_RADIUS := 22.0

# --- team composition (matches the Plato reference screenshots) ---------------
## 6 caps per side: 5 outfield + 1 goalkeeper. The GK is genuinely bigger —
## a larger collider and proportionally larger mass, not a visual trick — so it
## really does cover more of the mouth and shrugs off contact.
const CAPS_PER_TEAM := 6
const GK_INDEX := 0                          # first cap of each team is the GK
const GK_RADIUS := 58.0                      # ~1.3x an outfield cap
## Mass scales with area so the GK has the inertia its size implies.
const GK_MASS := 15.0 * (GK_RADIUS * GK_RADIUS) / (CAP_RADIUS * CAP_RADIUS)
const WALL_THICKNESS := 20.0                 # VISUAL rail thickness (pitch_draw)
## PHYSICS-ONLY wall depth. Collision walls keep their inner face exactly where
## WALL_THICKNESS puts it — every bounce is geometrically identical — but extend
## this far OUTWARD, away from the pitch, where nothing is drawn.
## Sized against measured worst-case travel: a wall-rebound double-hit drives the
## ball 89 px in a single physics step (tests/run.gd `wall_double`), which a
## 20 px wall cannot stop. Depth must exceed that plus the ball diameter.
const WALL_COLLISION_DEPTH := 240.0
const GOAL_POST_RADIUS := 14.0
const CAPTURE_DIST := CAP_RADIUS + BALL_RADIUS   # 66 — ball sticks on contact

# --- pitch markings (real football proportions, relative to PITCH) ------------
const CENTER_CIRCLE_R := 94.0                    # 9.15m penalty-arc radius (real)
const PENALTY_AREA_W := 420.0                    # 40.32m wide box
const PENALTY_AREA_D := 170.0                    # 16.5m deep
const GOAL_AREA_W := 190.0                       # 18.32m goal box
const GOAL_AREA_D := 55.0                        # 5.5m deep
const PENALTY_SPOT_D := 113.0                    # 11m from the goal line
const CORNER_ARC_R := 30.0                       # visible corner arc

# --- physics feel ------------------------------------------------------------
const CAP_MASS := 15.0                       # caps heavy vs ball — ball barely moves them
const BALL_MASS := 0.5                       # light ball: struck by cap, doesn't shove caps
const SLEEP_THRESHOLD := 5.0                 # px/s — all-bodies-settled threshold

# --- colors: table (measured from real Plato screenshot) ----------------------
const TABLE_BG := Color("#202124")           # dark charcoal matte canvas
const PITCH_FELT := Color("#436327")         # deep muted green (real Plato felt)
const FELT_APRON := Color("#3a5521")         # darker felt apron ring around pitch
const LINE_WHITE := Color(1, 1, 1, 0.95)     # crisp pitch markings, 2-3px
const WALL_COLOR := Color("#202124")         # dark charcoal containment walls
const WALL_GLOW := Color(1, 1, 1, 0.12)      # inner edge highlight
const GOAL_NET := Color(1, 1, 1, 0.35)       # net crosshatch

# --- wood table frame (real Plato: mottled wood around the felt) --------------
const WOOD_BASE := Color("#7a5230")          # warm tan-brown
const WOOD_DARK := Color("#54371f")          # grain streaks / shadows
const WOOD_LIGHT := Color("#a37a4e")         # grain highlights
const WOOD_KNOT := Color("#3d2a16")          # dark knots

# --- colors: pieces ----------------------------------------------------------
const CAP_BLUE := Color("#4285F4")           # vibrant royal blue (P2)
const CAP_BLUE_INNER := Color("#8ab4f8")     # lighter concentric inner core
const CAP_RED := Color("#E94235")            # high-vis primary red (P1)
const CAP_RED_INNER := Color("#f28b82")      # lighter concentric inner core
const CAP_RING := Color(1, 1, 1, 0.5)        # idle ring on caps
const SELECT_RING := Color("#FBBC05")        # neon yellow-gold selection ring

# --- HUD (Plato top bar: dark panel, score, goals, turn, timer) ---------------
const HUD_BG := Color("#1A1B1E")             # dark header panel (per AI spec)
const HUD_TEXT := Color(1, 1, 1, 0.92)       # primary text
const HUD_DIM := Color(1, 1, 1, 0.5)         # secondary text
const HUD_TIMER := Color("#E94235")          # depleting turn timer bar
const BALL_WHITE := Color(0.95, 0.95, 0.95)
const BALL_DOT := Color(0.15, 0.15, 0.15)
