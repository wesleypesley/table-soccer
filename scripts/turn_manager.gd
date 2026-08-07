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
const BALL_SPEED_MIN := 500.0
const BALL_SPEED_MAX := 1400.0
const CAP_RADIUS := 44.0
const BALL_RADIUS := 22.0
const CAPTURE_DIST := CAP_RADIUS + BALL_RADIUS      # 66 px — ball sticks on contact
const STOP_THRESHOLD := 8.0                          # px/s — ball stopped = lost ball
const PASS_CONE := 0.5                               # rad (~29°) half-angle for pass targeting
const MAX_PASS_DIST := 500.0
const HELD_OFFSET := Vector2(0, -34)                 # ball sits at holder's "feet"
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
var _dragging_cap: RigidBody2D = null
var _aim_start := Vector2.ZERO
var _aim_current := Vector2.ZERO
var _aiming := false
var _preview: Line2D

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
	var pos: Vector2 = board.ball.position
	if is_kickoff:
		board.reset_ball(Vector2(board.PITCH.x / 2.0, 810.0 if active_player == 0 else 270.0))
		pos = board.ball.position
	holder = _nearest_own_cap(pos)
	_attach_ball(holder)
	turn_changed.emit(active_player)
	print("[Turn] P%d — ball with cap %d, %d passes" % [active_player, board.caps.find(holder), passes_left])

# --- ball attach / launch ---------------------------------------------------

func _attach_ball(cap: RigidBody2D) -> void:
	holder = cap
	board.ball.collision_layer = 0                      # held ball doesn't collide
	board.ball.collision_mask = 0
	board.ball.linear_velocity = Vector2.ZERO
	board.ball.angular_velocity = 0.0
	board.ball.position = cap.position + HELD_OFFSET

func _launch_ball(dir: Vector2, speed: float) -> void:
	var ball: RigidBody2D = board.ball
	ball.position = holder.position + dir.normalized() * (CAPTURE_DIST + 8.0)   # clear of holder
	ball.collision_layer = 1
	ball.collision_mask = 1
	ball.linear_velocity = dir.normalized() * speed      # direct set — no freeze/impulse race
	state = State.FLIGHT
	print("[Turn] P%d launches %s dir=%s speed=%.0f" % [active_player, "pass" if passes_left > 0 else "shot", dir.normalized(), speed])

# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == State.MATCH_OVER or state == State.FLIGHT:
		return
	if event is InputEventMouseButton:
		_handle_press(event.position, event.pressed)
	elif event is InputEventMouseMotion and _aiming:
		_aim_current = event.position
		_update_preview()
	elif event is InputEventScreenTouch:
		_handle_press(event.position, event.pressed)
	elif event is InputEventScreenDrag and _aiming:
		_aim_current = event.position
		_update_preview()

func _handle_press(pos: Vector2, pressed: bool) -> void:
	if pressed:
		var cap := _cap_at(pos)
		if cap != null:
			state = State.MOVING
			_dragging_cap = cap
			_dragging_cap.freeze = true
			print("[Turn] P%d drag cap %d" % [active_player, board.caps.find(cap)])
		else:
			state = State.MOVING
			_aiming = true
			_aim_start = pos
			_aim_current = pos
			_update_preview()
	else:
		if _dragging_cap != null:
			_dragging_cap.freeze = false
			_dragging_cap = null
			state = State.TURN_START
		elif _aiming:
			_aiming = false
			_preview.visible = false
			_resolve_swipe(_aim_start, _aim_current)

# --- turn logic -------------------------------------------------------------

func _process(delta: float) -> void:
	if state == State.MOVING and _dragging_cap != null:
		var p := get_viewport().get_mouse_position()
		var lo := Vector2(CAP_RADIUS + 10, HALF + CAP_RADIUS + 10)
		var hi := Vector2(PITCH_X - CAP_RADIUS - 10, PITCH_Y - CAP_RADIUS - 10)
		if active_player == 1:
			lo.y = CAP_RADIUS + 10
			hi.y = HALF - CAP_RADIUS - 10
		_dragging_cap.position = p.clamp(lo, hi)

	if state == State.TURN_START or state == State.MOVING:
		turn_timer -= delta
		if turn_timer <= 0.0:
			_handle_timeout()

func _resolve_swipe(start: Vector2, end: Vector2) -> void:
	var dir := end - start
	if dir.length() < 20.0:
		state = State.TURN_START        # tap, not a swipe
		return
	var speed := clampf(dir.length() * BALL_SPEED_SCALE, BALL_SPEED_MIN, BALL_SPEED_MAX)
	if passes_left > 0:
		var target := _find_pass_target(dir.normalized())
		if target != null:
			_launch_ball(target.position - holder.position, speed)
			return
	_launch_ball(dir, speed)            # no pass target → shot

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
	if holder == null:
		return
	var dir := _aim_current - _aim_start
	if dir.length() < 20.0:
		return
	if passes_left > 0:
		var target := _find_pass_target(dir.normalized())
		if target != null:
			_preview.default_color = Color(0.4, 1, 0.5, 0.8)   # green = pass
			_preview.add_point(holder.position)
			_preview.add_point(target.position)
			return
	_preview.default_color = Color(1, 1, 1, 0.6)               # white = shot
	var speed := clampf(dir.length() * BALL_SPEED_SCALE, BALL_SPEED_MIN, BALL_SPEED_MAX)
	_preview.add_point(holder.position)
	_preview.add_point(holder.position + dir.normalized() * (speed * 0.25))

# --- flight / capture -------------------------------------------------------

func _physics_process(delta: float) -> void:
	var ball: RigidBody2D = board.ball
	if state != State.FLIGHT:
		# glue held ball to holder (no freeze — collisions are off while held)
		if holder != null:
			ball.position = holder.position + HELD_OFFSET
			ball.linear_velocity = Vector2.ZERO
			ball.angular_velocity = 0.0
		return
	# goal?
	var scorer: int = board.detect_goal()
	if scorer != -1:
		_on_goal(scorer)
		return
	# stick to a cap on contact
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		if cap == holder:
			continue
		if cap.position.distance_to(ball.position) < CAPTURE_DIST:
			var team := 0 if i < 5 else 1
			if team == active_player and passes_left > 0:
				# own capture → possession continues, pass consumed
				passes_left -= 1
				_attach_ball(cap)
				state = State.TURN_START
				turn_timer = TURN_SECONDS
				print("[Turn] P%d pass complete → cap %d (%d passes left)" % [active_player, i, passes_left])
			else:
				# opponent touch (or own touch with no passes left) → lost ball
				_lose_possession(cap)
			return
	# ball died without being captured → lost ball
	if ball.linear_velocity.length() < STOP_THRESHOLD:
		_lose_possession(null)

func _lose_possession(cap: RigidBody2D) -> void:
	if cap != null:
		var team := 0 if board.caps.find(cap) < 5 else 1
		print("[Turn] P%d lost ball to %s cap %d" % [active_player, "own" if team == active_player else "opponent", board.caps.find(cap)])
		_attach_ball(cap)
		# if opponent touched, they get possession; if own cap with 0 passes, opponent turn
		if team != active_player:
			_pass_turn()
		else:
			_pass_turn()
	else:
		print("[Turn] P%d ball died — possession lost" % active_player)
		_pass_turn()

func _on_goal(scorer: int) -> void:
	score[scorer] += 1
	print("[Match] GOAL! P%d scores — %d-%d" % [scorer, score[0], score[1]])
	if score[scorer] >= WIN_GOALS:
		_end_match(scorer, false)
		return
	active_player = 1 - scorer               # conceding player kicks off
	passes_left = pass_limit
	board.reset_ball(Vector2(board.PITCH.x / 2.0, 810.0 if active_player == 0 else 270.0))
	_setup_turn()
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
