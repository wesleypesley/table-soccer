extends Node
## Turn FSM — Plato Table Soccer pass-chain model.
## Ball is HELD (stuck to a player) or IN_FLIGHT (pass/shot). No free-roll settle.
## Turn = drag/position caps → pass ×N (limit 3/5/∞) → shot.
## Own cap captures ball → turn continues (pass used). Opponent cap → possession lost.

enum State { TURN_START, MOVING, FLIGHT, MATCH_OVER }

const TURN_SECONDS := 15.0
const MAX_TIMEOUTS := 3
const WIN_GOALS := 5
const INF_PASSES := 999

const BALL_SPEED_SCALE := 2.0
const BALL_SPEED_MIN := 300.0
const BALL_SPEED_MAX := 1400.0
const CAP_RADIUS := 44.0
const BALL_RADIUS := 22.0
const CAPTURE_DIST := CAP_RADIUS + BALL_RADIUS      # 66 px — ball sticks on contact
const STOP_THRESHOLD := 8.0                          # px/s — ball stopped = lost ball
const PASS_CONE := 0.5                               # rad (~29°) half-angle for pass targeting
const MAX_PASS_DIST := 500.0
const HELD_OFFSET := Vector2(0, -34)                 # ball sits at holder's "feet" (P0: above cap)
const MAX_PULL := 150.0                           # max slingshot pull-back (px)
const HALF := 540.0                                   # pitch center Y
const PITCH_X := 720.0
const PITCH_Y := 1080.0

var board: Node2D
var state: int = State.TURN_START
var active_player: int = 0                            # 0 = bottom (blue), 1 = top (red)
var score := [0, 0]
var turn_timer: float = TURN_SECONDS
var consecutive_timeouts := [0, 0]
var pass_limit: int = 3                               # match setting: 3 / 5 / INF_PASSES
var passes_left: int = 3

var holder: RigidBody2D = null                        # cap the ball is stuck to
var _selected_cap: RigidBody2D = null                 # currently selected (highlight)
var _cap_base_pos := Vector2.ZERO                     # cap pos when pull started
var _launcher: RigidBody2D = null                     # cap launched this action
var _ball_in_flight := false                          # true when ball was launched
var _pulling := false
var _aim_start := Vector2.ZERO
var _aim_current := Vector2.ZERO
var _preview: Line2D
var _flight_time := 0.0                 # seconds since launch
const MIN_FLIGHT_TIME := 0.3            # ball can't die before the puck makes contact

signal turn_changed(player: int)
signal match_over(winner: int)

func _ready() -> void:
	_preview = Line2D.new()
	_preview.width = 6.0
	_preview.default_color = Color(1, 1, 1, 0.6)
	_preview.visible = false
	board.add_child(_preview)
	_start_match()

func _start_match() -> void:
	active_player = randi() % 2                        # random kickoff
	score = [0, 0]
	consecutive_timeouts = [0, 0]
	passes_left = pass_limit
	_setup_turn(true)
	print("[Match] start — P%d kicks off (pass limit %d)" % [active_player, pass_limit])

func _setup_turn(is_kickoff: bool = false) -> void:
	state = State.TURN_START
	turn_timer = TURN_SECONDS
	passes_left = pass_limit
	_launcher = null
	_ball_in_flight = false
	if _selected_cap != null and is_instance_valid(_selected_cap):
		_selected_cap.get_node("Draw").set("selected", false)
	_selected_cap = null
	if is_kickoff:
		# kickoff / after-goal: ball to center spot, FREE. The kicking player
		# picks it up by dragging a cap onto it (pickup mechanic).
		board.reset_ball(Vector2(board.PITCH.x / 2.0, board.PITCH.y / 2.0))
		holder = null
		board.ball.collision_layer = 1
		board.ball.collision_mask = 1
	else:
		# possession change: ball stays where it stopped, free on the pitch
		holder = null
		board.ball.collision_layer = 1
		board.ball.collision_mask = 1
	turn_changed.emit(active_player)
	print("[Turn] P%d — ball %s" % [active_player, "with cap %d, %d passes" % [board.caps.find(holder), passes_left] if holder else "free on pitch, %d passes" % passes_left])

# --- ball attach / launch ---------------------------------------------------

func _attach_ball(cap: RigidBody2D) -> void:
	holder = cap
	board.ball.collision_layer = 0                      # held ball doesn't collide
	board.ball.collision_mask = 0
	board.ball.linear_velocity = Vector2.ZERO
	board.ball.angular_velocity = 0.0
	# ball at holder's feet, toward the opponent's goal (P0 attacks up, P1 down)
	var side := -1.0 if active_player == 0 else 1.0
	board.ball.position = cap.position + Vector2(0, 34.0 * side)

func _launch_cap(cap: RigidBody2D, pull: Vector2, speed: float) -> void:
	## Slingshot a NON-holder puck (reposition / collect the free ball).
	## Ball isn't launched — it may be collected on contact with this puck.
	_launcher = cap
	_ball_in_flight = false
	var d := pull.normalized()
	cap.apply_central_impulse(d * speed * cap.mass)
	state = State.FLIGHT
	_flight_time = 0.0
	print("[Turn] P%d slingshots cap %d (no ball) dir=%s speed=%.0f" % [active_player, board.caps.find(cap), d, speed])

func _launch_puck(dir: Vector2, speed: float) -> void:
	## Slingshot the HOLDER PUCK: impulse to the puck, which physically kicks
	## the ball (ball is freed from the holder, placed just ahead of it).
	var ball: RigidBody2D = board.ball
	var d := dir.normalized()
	_launcher = holder
	_ball_in_flight = true
	# free the ball and place it at the puck's striking edge — in FRONT of the
	# puck along the launch direction, with a small gap so the puck's motion
	# closes it and kicks the ball (exact-contact spawn makes the solver jitter)
	ball.collision_layer = 1
	ball.collision_mask = 1
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	ball.position = holder.position + d * (CAPTURE_DIST + 6.0)
	# impulse to the PUCK (impulse = desired velocity × mass). The puck slides
	# forward, collides with the ball, and the ball flies — like real table soccer.
	holder.apply_central_impulse(d * speed * holder.mass)
	state = State.FLIGHT
	_flight_time = 0.0
	print("[Turn] P%d slingshots cap %d dir=%s speed=%.0f" % [active_player, board.caps.find(holder), d, speed])

# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == State.MATCH_OVER or state == State.FLIGHT:
		return
	if event is InputEventMouseButton:
		_handle_press(event.position, event.pressed)
	elif event is InputEventMouseMotion and _pulling:
		_aim_current = event.position
		_update_preview()
	elif event is InputEventScreenTouch:
		_handle_press(event.position, event.pressed)
	elif event is InputEventScreenDrag and _pulling:
		_aim_current = event.position
		_update_preview()

func _handle_press(pos: Vector2, pressed: bool) -> void:
	if pressed:
		var cap := _cap_at(pos)
		if cap != null:
			# SELECT: highlight the puck. Selection is free — switch as much
			# as you want; only a pull+release commits.
			_set_selected(cap)
			state = State.TURN_START
			_cap_base_pos = cap.position
			_pulling = true
			_aim_start = pos
			_aim_current = pos
			print("[Turn] P%d selects cap %d" % [active_player, board.caps.find(cap)])
		else:
			_set_selected(null)     # tap empty space = deselect
	else:
		if _pulling and _selected_cap != null:
			_pulling = false
			var pull := _aim_start - _aim_current      # pull-back vector
			_preview.visible = false
			if pull.length() < 20.0:
				# tap, not a pull — stay selected, nothing committed
				_selected_cap.position = _cap_base_pos
				return
			_fire_pull(pull)
			_set_selected(null)          # shot fired — clear highlight
		else:
			_pulling = false

func _fire_pull(pull: Vector2) -> void:
	## Slingshot the SELECTED puck. If it holds the ball → pass or shot.
	## Otherwise the puck slides; if it strikes the free ball the ball is
	## knocked into flight (physics) — it never sticks to the striker.
	var cap := _selected_cap
	if cap == null:
		return
	if cap == holder:
		var dir := pull.normalized()
		var speed := _pull_speed(pull)
		if passes_left > 0:
			var target := _find_pass_target(dir)
			if target != null:
				_launch_puck(target.position - holder.position, speed)
				return
		_launch_puck(dir, speed)            # no pass target → shot
	else:
		_launch_cap(cap, pull, _pull_speed(pull))

func _pull_speed(pull: Vector2) -> float:
	## Linear power curve: full 150px pull = max speed, small pull = gentle slide.
	var t := clampf(pull.length() / MAX_PULL, 0.0, 1.0)
	return lerpf(BALL_SPEED_MIN, BALL_SPEED_MAX, t)

func _set_selected(cap: RigidBody2D) -> void:
	if _selected_cap != null and is_instance_valid(_selected_cap):
		_selected_cap.get_node("Draw").set("selected", false)
	_selected_cap = cap
	if cap != null:
		cap.get_node("Draw").set("selected", true)

# --- turn logic -------------------------------------------------------------

func _process(delta: float) -> void:
	# pull-back visual: selected puck eases back along the pull vector
	if _pulling and _selected_cap != null:
		var p := get_viewport().get_mouse_position()
		var pull := (_aim_start - p).limit_length(MAX_PULL)
		_selected_cap.position = _cap_base_pos - pull * 0.5   # puck visibly pulls back
		_aim_current = p

	if state == State.TURN_START or state == State.MOVING:
		turn_timer -= delta
		if turn_timer <= 0.0:
			_handle_timeout()


func _find_pass_target(dir: Vector2) -> RigidBody2D:
	var best: RigidBody2D = null
	var best_angle := PASS_CONE
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		var team := 0 if i < 5 else 1
		if team != active_player or cap == holder:
			continue
		var to := cap.position - holder.position
		if to.length() > MAX_PASS_DIST:
			continue
		var angle := absf(dir.angle_to(to.normalized()))
		if angle < best_angle:
			best_angle = angle
			best = cap
	return best

func _update_preview() -> void:
	_preview.visible = true
	_preview.clear_points()
	var cap := _selected_cap
	if cap == null:
		return
	# slingshot: pull-back vector reversed = launch direction (from the puck)
	var dir := _aim_start - _aim_current
	if dir.length() < 20.0:
		return
	if cap == holder:
		if passes_left > 0:
			var target := _find_pass_target(dir.normalized())
			if target != null:
				_preview.default_color = Color(0.4, 1, 0.5, 0.8)   # green = pass
				_preview.add_point(cap.position)
				_preview.add_point(target.position)
				return
	_preview.default_color = Color(1, 1, 1, 0.6)               # white = shot / slide
	var speed := _pull_speed(dir)
	_preview.add_point(cap.position)
	_preview.add_point(cap.position + dir.normalized() * (speed * 0.25))

# --- flight / capture -------------------------------------------------------

func _physics_process(delta: float) -> void:
	var ball: RigidBody2D = board.ball
	if state != State.FLIGHT:
		# glue held ball to holder (no freeze — collisions are off while held)
		if holder != null:
			var side := -1.0 if active_player == 0 else 1.0
			ball.position = holder.position + Vector2(0, 34.0 * side)
			ball.linear_velocity = Vector2.ZERO
			ball.angular_velocity = 0.0
		return
	_flight_time += delta

	if not _ball_in_flight:
		# cap-only launch (no ball): the puck slides. If it strikes the FREE
		# ball, the ball is knocked into flight (pure physics — no stick).
		# If the puck dies without touching the ball → whiff, possession lost.
		if _launcher != null and holder == null \
				and _launcher.position.distance_to(ball.position) < CAPTURE_DIST + 12.0:
			_ball_in_flight = true
			print("[Turn] P%d cap %d strikes the ball" % [active_player, board.caps.find(_launcher)])
			return
		if _launcher != null and _launcher.linear_velocity.length() < STOP_THRESHOLD \
				and _flight_time > MIN_FLIGHT_TIME:
			_lose_possession()
		return

	# goal?
	var scorer: int = board.detect_goal()
	if scorer != -1:
		_on_goal(scorer)
		return
	# stick ONLY on own-teammate contact (with passes left), EXCEPT the striker
	# (the cap that launched/kicked — ball can't pass to the cap that hit it).
	# Opponent/wall contact is pure physics — the ball bounces and keeps flying.
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		if cap == holder or cap == _launcher:
			continue
		if cap.position.distance_to(ball.position) < CAPTURE_DIST + 12.0:
			var team := 0 if i < 5 else 1
			if team == active_player and passes_left > 0:
				passes_left -= 1
				_attach_ball(cap)
				state = State.TURN_START
				turn_timer = TURN_SECONDS
				print("[Turn] P%d pass complete → cap %d (%d passes left)" % [active_player, i, passes_left])
				return
			# opponent (or own cap with no passes left): physics bounce only
			return
	# ball died without being captured → stays where it stopped, turn passes
	# (min flight time: the puck needs a moment to make contact and kick it)
	if _flight_time > MIN_FLIGHT_TIME and ball.linear_velocity.length() < STOP_THRESHOLD:
		_lose_possession()

func _lose_possession() -> void:
	# Ball stays exactly where it stopped — no reset, no teleport, no stick.
	holder = null
	print("[Turn] P%d lost ball — it rests at %s" % [active_player, board.ball.position])
	_pass_turn()

func _on_goal(scorer: int) -> void:
	score[scorer] += 1
	print("[Match] GOAL! P%d scores — %d-%d" % [scorer, score[0], score[1]])
	if score[scorer] >= WIN_GOALS:
		_end_match(scorer, false)
		return
	active_player = 1 - scorer               # conceding player kicks off
	passes_left = pass_limit
	_setup_turn(true)
	print("[Turn] P%d kicks off after goal" % active_player)

func _pass_turn() -> void:
	active_player = 1 - active_player
	_setup_turn()

# --- timeout / forfeit ------------------------------------------------------

func _handle_timeout() -> void:
	consecutive_timeouts[active_player] += 1
	print("[Turn] P%d timeout #%d — shot forfeited" % [active_player, consecutive_timeouts[active_player]])
	if consecutive_timeouts[active_player] >= MAX_TIMEOUTS:
		var winner := 1 - active_player
		score[winner] = WIN_GOALS
		_end_match(winner, true)
	else:
		_pass_turn()

func _end_match(winner: int, forfeit: bool) -> void:
	state = State.MATCH_OVER
	print("[Match] P%d wins%s — final %d-%d" % [winner, " (forfeit)" if forfeit else "", score[0], score[1]])
	match_over.emit(winner)

# --- helpers ----------------------------------------------------------------

func _cap_at(pos: Vector2) -> RigidBody2D:
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		var team := 0 if i < 5 else 1
		if team != active_player:
			continue
		if cap.position.distance_to(pos) <= CAP_RADIUS + 6.0:
			return cap
	return null

func _nearest_own_cap(pos: Vector2) -> RigidBody2D:
	var best: RigidBody2D = null
	var best_d := INF
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		var team := 0 if i < 5 else 1
		if team != active_player:
			continue
		var d := cap.position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = cap
	return best
