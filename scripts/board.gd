extends Node2D
## Board: pitch walls, goals, caps and ball. Physics core per SRS 02 §4.B.

# Geometry and physics feel are NOT redefined here — Design is the single
# source of truth. These aliases exist only so `board.PITCH` and friends keep
# working for external readers (turn_manager reads board.PITCH).
const PITCH := Design.PITCH                    # portrait playfield
const GOAL_WIDTH := Design.GOAL_WIDTH          # centered on top/bottom
const CAP_RADIUS := Design.CAP_RADIUS
const BALL_RADIUS := Design.BALL_RADIUS
const SLEEP_THRESHOLD := Design.SLEEP_THRESHOLD  # px/s per SRS 02 §4.B
const CAP_MASS := Design.CAP_MASS      # caps heavy vs ball — ball barely moves them
const BALL_MASS := Design.BALL_MASS    # light ball: struck by cap, doesn't shove caps

var caps: Array[RigidBody2D] = []
var ball: RigidBody2D
var walls: StaticBody2D

# Formation: 6 caps per side (x, y), 1-2-1-2 — the shape the reference
# screenshot shows. Index 0 of each side is the GOALKEEPER (Design.GK_INDEX),
# which is a physically larger cap. Attacking/Defending variants land here in
# the pre-match step (SRS 02 §2).
#
# Vertical spacing is measured off the reference; the GK sits clear of the wall
# (GK_RADIUS 58 + wall inner face 10 => centre must stay above y = 1012).
const FORMATION_BOTTOM := [
	Vector2(360, 1000),  # GK
	Vector2(258, 857),   # DEF L
	Vector2(462, 857),   # DEF R
	Vector2(360, 723),   # MID
	Vector2(258, 627),   # ATT L
	Vector2(462, 627),   # ATT R
]
const FORMATION_TOP := [
	Vector2(360, 80),    # GK
	Vector2(258, 223),   # DEF L
	Vector2(462, 223),   # DEF R
	Vector2(360, 357),   # MID
	Vector2(258, 453),   # ATT L
	Vector2(462, 453),   # ATT R
]

func _ready() -> void:
	_build_pitch_visual()   # render layer first — behind all physics bodies
	_build_walls()
	_spawn_caps()
	_spawn_ball()
	print("[Board] ready: %d caps, ball at %s" % [caps.size(), ball.position])

# --- construction -----------------------------------------------------------

func _build_pitch_visual() -> void:
	var visual := Node2D.new()
	visual.name = "PitchVisual"
	visual.set_script(load("res://scripts/pitch_draw.gd"))
	add_child(visual)
	# soft drop shadows under all pieces — added before caps/ball so they
	# render beneath; drawn in board space so they don't rotate with pieces.
	var shadows := Node2D.new()
	shadows.name = "ShadowLayer"
	shadows.set_script(load("res://scripts/shadow_layer.gd"))
	add_child(shadows)

func _build_walls() -> void:
	walls = StaticBody2D.new()
	walls.name = "Walls"
	add_child(walls)

	var half_gap := GOAL_WIDTH / 2.0
	var wall_len := (PITCH.x - GOAL_WIDTH) / 2.0      # 280: flanking segment length
	# Walls are built INNER-FACE-FIRST: the face the ball actually strikes stays
	# exactly where WALL_THICKNESS puts it (x=+10 on the left, y=+10 on top, and
	# so on — identical to the original centred segments), and the body extends
	# outward by WALL_COLLISION_DEPTH into off-pitch space where nothing is drawn.
	# A 20px wall cannot stop a ball covering 89px in one physics step (measured,
	# tests/run.gd wall_double); a deep one can. Only the outward side grew, so
	# every bounce angle and contact point is unchanged.
	var half_t := Design.WALL_THICKNESS / 2.0
	var d := Design.WALL_COLLISION_DEPTH
	# Left/right overshoot the pitch ends by `d` so the corners are sealed too.
	_add_wall_rect(Rect2(half_t - d, -d, d, PITCH.y + d * 2.0))               # left
	_add_wall_rect(Rect2(PITCH.x - half_t, -d, d, PITCH.y + d * 2.0))         # right
	_add_wall_rect(Rect2(0, half_t - d, wall_len, d))                         # top L
	_add_wall_rect(Rect2(PITCH.x - wall_len, half_t - d, wall_len, d))        # top R
	_add_wall_rect(Rect2(0, PITCH.y - half_t, wall_len, d))                   # bottom L
	_add_wall_rect(Rect2(PITCH.x - wall_len, PITCH.y - half_t, wall_len, d))  # bottom R

	# goal posts: 4 static circles at the goal mouth corners
	for px in [PITCH.x / 2 - half_gap, PITCH.x / 2 + half_gap]:
		for py in [0.0, PITCH.y]:
			var post := StaticBody2D.new()
			var pcol := CollisionShape2D.new()
			var pshape := CircleShape2D.new()
			pshape.radius = Design.GOAL_POST_RADIUS
			pcol.shape = pshape
			post.add_child(pcol)
			post.position = Vector2(px, py)
			add_child(post)

	# goal pockets: side + back walls behind each goal mouth so caps and the
	# ball can NEVER leave the table (the 160px mouth is wider than a cap).
	var gx0 := PITCH.x / 2.0 - half_gap
	var gx1 := PITCH.x / 2.0 + half_gap
	var pd := 36.0                       # pocket depth
	var tw := Design.WALL_THICKNESS      # visual pocket wall thickness
	# Same inner-face-first rule as the perimeter: the faces a ball inside the
	# pocket can strike (x=gx0, x=gx1, and the back wall) stay put; the bodies
	# grow outward by `d`. A goal-speed shot must not tunnel out the back.
	var back_top := -(pd - tw)           # top pocket back wall, inner face
	var back_bottom := PITCH.y + pd - tw # bottom pocket back wall, inner face
	var mouth_w := (gx1 - gx0) + d * 2.0
	# top pocket (y < 0)
	_add_wall_rect(Rect2(gx0 - d, -pd, d, pd))
	_add_wall_rect(Rect2(gx1, -pd, d, pd))
	_add_wall_rect(Rect2(gx0 - d, back_top - d, mouth_w, d))
	# bottom pocket (y > PITCH.y)
	_add_wall_rect(Rect2(gx0 - d, PITCH.y, d, pd))
	_add_wall_rect(Rect2(gx1, PITCH.y, d, pd))
	_add_wall_rect(Rect2(gx0 - d, back_bottom, mouth_w, d))

func _add_wall_rect(rect: Rect2) -> void:
	## Add a static wall rectangle to the shared Walls body (board-local coords).
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = rect.position + rect.size / 2.0
	walls.add_child(col)

func _spawn_caps() -> void:
	for i in FORMATION_BOTTOM.size():
		caps.append(_make_cap(FORMATION_BOTTOM[i], Design.CAP_BLUE, Design.CAP_BLUE_INNER,
				i == Design.GK_INDEX))                                  # blue bottom
	for i in FORMATION_TOP.size():
		caps.append(_make_cap(FORMATION_TOP[i], Design.CAP_RED, Design.CAP_RED_INNER,
				i == Design.GK_INDEX))                                  # red top

func cap_radius(cap: Node) -> float:
	## Per-cap collider radius. The GK is bigger, so anything that reasons about
	## contact (capture distance, tether rest length, release rule) must ask the
	## cap rather than assume Design.CAP_RADIUS.
	return float(cap.get_meta("radius", Design.CAP_RADIUS))

func formation_for(index: int) -> Vector2:
	## Home position of cap `index` — used to restore formation at kickoff.
	var per := Design.CAPS_PER_TEAM
	return FORMATION_BOTTOM[index] if index < per else FORMATION_TOP[index - per]

func teleport_body(body: RigidBody2D, local_pos: Vector2) -> void:
	## Hard-move a rigid body to a BOARD-LOCAL position and stop it dead.
	##
	## Two traps, both measured:
	##  1. Writing `body.position` is not enough. For an AWAKE RigidBody2D the
	##     physics server owns the transform and restores its own on the next
	##     step, so the write silently reverts one frame later (a direct write
	##     read back 0.0px error on the same frame and 781.7px four frames on).
	##     It appears to work on a sleeping body, which is what hides the bug.
	##  2. PhysicsServer2D transforms are GLOBAL, while formations and the
	##     centre spot are board-local. Passing a local point straight through
	##     lands every body off by the board offset — exactly (-198, -426) here.
	var global_pos: Vector2 = global_transform * local_pos
	var rid := body.get_rid()
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, global_pos))
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
			Vector2.ZERO)
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.0)
	# Keep the node in sync so the same frame reads back correctly.
	body.global_position = global_pos
	body.rotation = 0.0

func reset_formation() -> void:
	## Return every cap to its formation spot, at rest (after a goal both teams
	## reform before the kickoff).
	for i in caps.size():
		teleport_body(caps[i], formation_for(i))

func _make_cap(pos: Vector2, color: Color, inner: Color, is_gk: bool = false) -> RigidBody2D:
	var radius: float = Design.GK_RADIUS if is_gk else CAP_RADIUS
	var cap := RigidBody2D.new()
	cap.name = "Goalkeeper" if is_gk else "Cap"
	cap.position = pos
	# The GK's size is REAL: bigger collider, and mass scaled by area so it also
	# carries the inertia that size implies (Design.GK_MASS).
	cap.set_meta("radius", radius)
	cap.set_meta("is_gk", is_gk)
	cap.mass = Design.GK_MASS if is_gk else CAP_MASS
	cap.linear_damp = 1.0        # caps glide: total travel ≈ launch speed (px)
	cap.angular_damp = 2.0
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	mat.bounce = 0.05            # caps barely bounce
	cap.physics_material_override = mat
	# contact monitoring: the facing swing needs get_colliding_bodies() to
	# tell a wall (StaticBody2D — give up) from a cap (RigidBody2D — shove it);
	# the capture rule uses the same contact list — ball must TOUCH the man
	# to be caught (no distance-magnet). 8 slots: scrums touch ball + walls
	# + several caps in one step.
	cap.contact_monitor = true
	cap.max_contacts_reported = 8
	# glossy token disc (gradient shader) — below the ring
	var disc := Node2D.new()
	disc.name = "Disc"
	disc.set_script(load("res://scripts/cap_disc.gd"))
	disc.set("base_color", color)
	disc.set("inner_color", inner)
	cap.add_child(disc)
	# selection ring node — kept ABOVE the disc via z_index so the disc's
	# gradient shader never shades the gold ring. Named "Draw" because
	# turn_manager toggles `selected` on cap.get_node("Draw").
	var ring := Node2D.new()
	ring.name = "Draw"
	ring.z_index = 1
	ring.set_script(load("res://scripts/cap_draw.gd"))
	cap.add_child(ring)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	col.shape = shape
	cap.add_child(col)
	add_child(cap)
	return cap

func _spawn_ball() -> void:
	ball = RigidBody2D.new()
	ball.name = "Ball"
	ball.position = PITCH / 2.0
	ball.mass = BALL_MASS
	ball.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE  # prevent tunneling at high shot speed
	ball.contact_monitor = true        # detect opponent touches on the held ball (release rule)
	ball.max_contacts_reported = 8
	ball.linear_damp = 0.5       # ball glides (SRS 01: gliding caps/ball)
	ball.angular_damp = 0.5
	var mat := PhysicsMaterial.new()
	mat.friction = 0.8
	mat.bounce = 0.7
	ball.physics_material_override = mat
	var disc := Node2D.new()
	disc.set_script(load("res://scripts/ball_disc.gd"))
	ball.add_child(disc)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = BALL_RADIUS
	col.shape = shape
	ball.add_child(col)
	add_child(ball)

# --- physics settle (SRS 02 §4.B) -------------------------------------------

# --- goal detection / reset ------------------------------------------------

func detect_goal() -> int:
	## Returns the scoring player (0 = bottom/blue scores top goal, 1 = top/red
	## scores bottom goal), or -1 if the ball isn't fully across a goal line.
	if ball.position.y < 0.0 and absf(ball.position.x - PITCH.x / 2.0) < GOAL_WIDTH / 2.0:
		return 0
	if ball.position.y > PITCH.y and absf(ball.position.x - PITCH.x / 2.0) < GOAL_WIDTH / 2.0:
		return 1
	return -1

func reset_ball(pos: Vector2 = PITCH / 2.0) -> void:
	# Same server-authoritative teleport as the caps: a goal resets the ball
	# while it is travelling fast, i.e. very much awake.
	teleport_body(ball, pos)
	ball.collision_layer = 1       # a reset ball is always FREE — restore collisions
	ball.collision_mask = 1        # (a held ball has layer 0 and would ghost through walls)

func is_physics_settled() -> bool:
	if ball.linear_velocity.length() > SLEEP_THRESHOLD:
		return false
	for cap in caps:
		if cap.linear_velocity.length() > SLEEP_THRESHOLD:
			return false
	return true

func _process(_delta: float) -> void:
	pass  # debug scaffolding removed — no R/SPACE hacks in live play
