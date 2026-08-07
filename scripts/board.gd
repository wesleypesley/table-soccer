extends Node2D
## Board: pitch walls, goals, caps and ball. Physics core per SRS 02 §4.B.

const PITCH := Vector2(720.0, 1080.0)          # portrait playfield
const GOAL_WIDTH := 160.0                      # centered on top/bottom
const CAP_RADIUS := 44.0
const BALL_RADIUS := 22.0
const SLEEP_THRESHOLD := 5.0                   # px/s per SRS 02 §4.B
const CAP_MASS := 5.0
const BALL_MASS := 1.0

var caps: Array[RigidBody2D] = []
var ball: RigidBody2D

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
	_build_walls()
	_spawn_caps()
	_spawn_ball()
	print("[Board] ready: %d caps, ball at %s" % [caps.size(), ball.position])

# --- construction -----------------------------------------------------------

func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	add_child(walls)

	var half_gap := GOAL_WIDTH / 2.0
	var segs := [
		# left, right walls (full height)
		[Vector2(0, PITCH.y / 2), Vector2(20, PITCH.y), 0.0],
		[Vector2(PITCH.x, PITCH.y / 2), Vector2(20, PITCH.y), 0.0],
		# top wall split around goal mouth
		[Vector2(PITCH.x / 2 - half_gap / 2 - 10, 0), Vector2(PITCH.x / 2 - half_gap - 10, 20), 0.0],
		[Vector2(PITCH.x / 2 + half_gap / 2 + 10, 0), Vector2(PITCH.x / 2 + half_gap + 10, 20), 0.0],
		# bottom wall split around goal mouth
		[Vector2(PITCH.x / 2 - half_gap / 2 - 10, PITCH.y), Vector2(PITCH.x / 2 - half_gap - 10, 20), 0.0],
		[Vector2(PITCH.x / 2 + half_gap / 2 + 10, PITCH.y), Vector2(PITCH.x / 2 + half_gap + 10, 20), 0.0],
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

func _spawn_caps() -> void:
	for i in FORMATION_BOTTOM.size():
		caps.append(_make_cap(FORMATION_BOTTOM[i], Color(0.13, 0.55, 0.95)))  # blue bottom
	for i in FORMATION_TOP.size():
		caps.append(_make_cap(FORMATION_TOP[i], Color(0.95, 0.35, 0.30)))     # red top

func _make_cap(pos: Vector2, color: Color) -> RigidBody2D:
	var cap := RigidBody2D.new()
	cap.name = "Cap"
	cap.position = pos
	cap.mass = CAP_MASS
	cap.linear_damp = 4.0        # caps stop quickly (glide feel per SRS 01)
	cap.angular_damp = 4.0
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	mat.bounce = 0.05            # caps barely bounce
	cap.physics_material_override = mat
	var draw := _cap_draw(color)
	cap.add_child(draw)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = CAP_RADIUS
	col.shape = shape
	cap.add_child(col)
	add_child(cap)
	return cap

func _cap_draw(color: Color) -> Node2D:
	var d := Node2D.new()
	d.set_script(load("res://scripts/cap_draw.gd"))
	d.set("cap_color", color)
	return d

func _spawn_ball() -> void:
	ball = RigidBody2D.new()
	ball.name = "Ball"
	ball.position = PITCH / 2.0
	ball.mass = BALL_MASS
	ball.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE  # prevent tunneling at high shot speed
	ball.linear_damp = 0.5       # ball glides (SRS 01: gliding caps/ball)
	ball.angular_damp = 0.5
	var mat := PhysicsMaterial.new()
	mat.friction = 0.8
	mat.bounce = 0.7
	ball.physics_material_override = mat
	var draw := Node2D.new()
	draw.set_script(load("res://scripts/ball_draw.gd"))
	ball.add_child(draw)
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

func is_physics_settled() -> bool:
	if ball.linear_velocity.length() > SLEEP_THRESHOLD:
		return false
	for cap in caps:
		if cap.linear_velocity.length() > SLEEP_THRESHOLD:
			return false
	return true

func _process(_delta: float) -> void:
	# debug: spacebar kicks the ball so physics settle can be observed
	if Input.is_key_pressed(KEY_SPACE) and is_physics_settled():
		ball.apply_central_impulse(Vector2(randf_range(-1, 1), -randf_range(200, 400)))
		print("[Board] debug kick -> ball velocity ", ball.linear_velocity)
	if Input.is_key_pressed(KEY_R):
		ball.position = PITCH / 2.0
		ball.linear_velocity = Vector2.ZERO
