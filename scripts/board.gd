extends Node2D
## Board: pitch walls, goals, caps and ball. Physics core per SRS 02 §4.B.

const PITCH := Vector2(720.0, 1080.0)          # portrait playfield
const GOAL_WIDTH := 160.0                      # centered on top/bottom
const CAP_RADIUS := 44.0
const BALL_RADIUS := 22.0
const SLEEP_THRESHOLD := 5.0                   # px/s per SRS 02 §4.B
const CAP_MASS := 15.0                 # caps heavy vs ball — ball barely moves them
const BALL_MASS := 0.5                  # light ball: struck by cap, doesn't shove caps

var caps: Array[RigidBody2D] = []
var ball: RigidBody2D
var walls: StaticBody2D

# Formation: 5 caps per side (x, y) — default balanced. Attacking/Defending
# variants land here in the pre-match step (SRS 02 §2).
const FORMATION_BOTTOM := [
	Vector2(360, 1010),  # GK
	Vector2(200, 940),   # DEF L
	Vector2(520, 940),   # DEF R
	Vector2(140, 830),   # ATT L
	Vector2(580, 830),   # ATT R
]
const FORMATION_TOP := [
	Vector2(360, 70),    # GK
	Vector2(200, 140),   # DEF L
	Vector2(520, 140),   # DEF R
	Vector2(140, 250),   # ATT L
	Vector2(580, 250),   # ATT R
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
	var segs := [
		# left, right walls (full height)
		[Vector2(0, PITCH.y / 2), Vector2(20, PITCH.y), 0.0],
		[Vector2(PITCH.x, PITCH.y / 2), Vector2(20, PITCH.y), 0.0],
		# top wall split around goal mouth: [0..280] and [440..720]
		[Vector2(wall_len / 2.0, 0), Vector2(wall_len, 20), 0.0],
		[Vector2(PITCH.x - wall_len / 2.0, 0), Vector2(wall_len, 20), 0.0],
		# bottom wall split around goal mouth
		[Vector2(wall_len / 2.0, PITCH.y), Vector2(wall_len, 20), 0.0],
		[Vector2(PITCH.x - wall_len / 2.0, PITCH.y), Vector2(wall_len, 20), 0.0],
	]
	for s in segs:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(s[1].x, s[1].y)
		var col := CollisionShape2D.new()
		col.shape = rect
		col.position = Vector2(s[0].x, s[0].y)
		walls.add_child(col)

	# goal posts: 4 static circles at the goal mouth corners
	for px in [PITCH.x / 2 - half_gap, PITCH.x / 2 + half_gap]:
		for py in [0.0, PITCH.y]:
			var post := StaticBody2D.new()
			var pcol := CollisionShape2D.new()
			var pshape := CircleShape2D.new()
			pshape.radius = 14.0
			pcol.shape = pshape
			post.add_child(pcol)
			post.position = Vector2(px, py)
			add_child(post)

	# goal pockets: side + back walls behind each goal mouth so caps and the
	# ball can NEVER leave the table (the 160px mouth is wider than a cap).
	var gx0 := PITCH.x / 2.0 - half_gap
	var gx1 := PITCH.x / 2.0 + half_gap
	var pd := 36.0     # pocket depth
	var tw := 20.0     # wall thickness
	# top pocket (y < 0)
	_add_wall_rect(Rect2(gx0 - tw, -pd, tw, pd))
	_add_wall_rect(Rect2(gx1, -pd, tw, pd))
	_add_wall_rect(Rect2(gx0 - tw, -pd, (gx1 - gx0) + tw * 2.0, tw))
	# bottom pocket (y > PITCH.y)
	_add_wall_rect(Rect2(gx0 - tw, PITCH.y, tw, pd))
	_add_wall_rect(Rect2(gx1, PITCH.y, tw, pd))
	_add_wall_rect(Rect2(gx0 - tw, PITCH.y + pd - tw, (gx1 - gx0) + tw * 2.0, tw))

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
		caps.append(_make_cap(FORMATION_BOTTOM[i], Design.CAP_BLUE, Design.CAP_BLUE_INNER))  # blue bottom
	for i in FORMATION_TOP.size():
		caps.append(_make_cap(FORMATION_TOP[i], Design.CAP_RED, Design.CAP_RED_INNER))     # red top

func _make_cap(pos: Vector2, color: Color, inner: Color) -> RigidBody2D:
	var cap := RigidBody2D.new()
	cap.name = "Cap"
	cap.position = pos
	cap.mass = CAP_MASS
	cap.linear_damp = 1.0        # caps glide: total travel ≈ launch speed (px)
	cap.angular_damp = 2.0
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	mat.bounce = 0.05            # caps barely bounce
	cap.physics_material_override = mat
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
	shape.radius = CAP_RADIUS
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
	ball.position = pos
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
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
