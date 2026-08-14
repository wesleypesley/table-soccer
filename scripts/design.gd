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

# --- colors: table -----------------------------------------------------------
# Pixel-sampled from the reference gameplay screenshot, not eyeballed.
# The old PITCH_FELT (#436327) turned out to be almost exactly the reference's
# BACKGROUND grass (#45652A) — the pitch itself is far brighter than that, which
# is why the build read so dull next to the reference.
const TABLE_BG := Color("#202124")           # matte canvas behind everything
const GRASS_BG := Color("#45652A")           # ground the table sits on (sampled)
const PITCH_FELT := Color("#6FA337")         # bright mid-pitch turf (sampled)
const FELT_EDGE := Color("#3B5726")          # ends of the pitch — vertical vignette
const FELT_APRON := Color("#3a5521")         # darker felt apron ring around pitch
const MOW_CONTRAST := 0.10                   # light/dark alternation of the mow bands
const LINE_WHITE := Color(1, 1, 1, 0.95)     # crisp pitch markings, 2-3px
const RAIL_SILVER := Color("#B3ACB6")        # beveled perimeter rail (sampled)
const WALL_COLOR := Color("#B3ACB6")         # rails read silver, not charcoal
const WALL_GLOW := Color(1, 1, 1, 0.12)      # inner edge highlight
const GOAL_NET := Color(1, 1, 1, 0.72)       # net mesh
const GOAL_FRAME := Color("#F2F4F7")         # white goal frame (posts + crossbar)
const GOAL_INTERIOR := Color("#20301A")       # dark ground behind the white mesh
const GOAL_DEPTH := 62.0                     # how far the net stands off the line
## Corner flags — red at the top end, cyan at the bottom, as in the reference.
const FLAG_TOP := Color("#E2413B")
const FLAG_BOTTOM := Color("#33C6E8")
const FLAG_POLE := Color("#E8E8EA")
const FLAG_HEIGHT := 34.0
## Active-team halo: a bright cyan ring around every cap of the side to move.
const TEAM_HALO := Color("#7FE7FF")
## Metallic rim around each cap token.
const CAP_RIM := Color("#C9CCD4")
const CAP_RIM_DARK := Color("#6E7481")

# --- crowd stands (both touchlines) ------------------------------------------
## Dark base with bright confetti speckle: the sampled histogram is dominated by
## dark browns/greys, with the colourful spectators a minority of pixels.
const STAND_BASE := Color("#3A2A20")
const STAND_SHADE := Color("#241a14")
const STAND_FRAME := Color("#8d8d95")
const STAND_WIDTH := 58.0                    # scaled from the reference ratio
const STAND_GAP := 42.0                      # clear space between rail and stand
const STAND_CONFETTI: Array[Color] = [
	Color("#e04a4a"), Color("#f2c14b"), Color("#4aa3e0"), Color("#e8e8ea"),
	Color("#57c078"), Color("#d96fb0"), Color("#f08a3c"), Color("#8b6bd9"),
]

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
const HUD_PILL := Color("#2C8BF0")           # "Your Turn" pill (reference blue)
const HUD_ONLINE := Color("#4CD964")         # online dot next to a player name
const HUD_CHIP := Color("#2A2C31")           # round back / menu chips
const HUD_TIMER_TRACK := Color(1, 1, 1, 0.14)
const PLAYER_NAMES := ["Player 1", "Player 2"]
const BALL_WHITE := Color(0.95, 0.95, 0.95)
const BALL_DOT := Color(0.15, 0.15, 0.15)
