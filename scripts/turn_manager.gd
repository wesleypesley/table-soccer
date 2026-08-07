extends Node
## Turn FSM per SRS 02 §3 (Plato Tactical model, Option B).
## Turn = move caps (drag) → shoot (swipe) → settle → evaluate → next turn.

enum State { MATCH_START, TURN_START, MOVING, AIMING, SIMULATING, EVALUATE, MATCH_OVER }

const TURN_SECONDS := 15.0
const MAX_TIMEOUTS := 3
const WIN_GOALS := 5
const SHOT_POWER_SCALE := 0.15      # swipe px/s → impulse units
const SHOT_POWER_MIN := 100.0
const SHOT_POWER_MAX := 900.0
const CAP_RADIUS := 44.0
const HALF := 540.0                 # pitch center Y
const PITCH_X := 720.0
const PITCH_Y := 1080.0

var board: Node2D
var state: int = State.MATCH_START
var active_player: int = 0          # 0 = bottom (blue), 1 = top (red)
var score := [0, 0]
var turn_timer: float = TURN_SECONDS
var consecutive_timeouts := [0, 0]
var is_first_turn := true

var _dragging_cap: RigidBody2D = null
var _aim_start := Vector2.ZERO
var _aim_current := Vector2.ZERO
var _aiming := false
var _preview: Line2D
var _sim_time := 0.0                 # seconds in SIMULATING state
const MIN_SETTLE_TIME := 0.15        # shot can't settle instantly (physics step ordering)

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
	active_player = randi() % 2     # kickoff random (SRS 02 §2.3)
	state = State.TURN_START
	turn_timer = TURN_SECONDS
	print("[Turn] match start — player %d kicks off" % active_player)
	turn_changed.emit(active_player)

# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == State.MATCH_OVER or state == State.SIMULATING or state == State.EVALUATE:
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
	print("[Turn] press @%s pressed=%s state=%d" % [pos, pressed, state])
	if pressed:
		# touch on own cap → drag it; anywhere else → aim a shot
		var cap := _cap_at(pos)
		if cap != null:
			state = State.MOVING
			_dragging_cap = cap
			_dragging_cap.freeze = true
			print("[Turn] P%d drag cap" % active_player)
		else:
			state = State.AIMING
			_aiming = true
			_aim_start = pos
			_aim_current = pos
			_update_preview()
	else:
		if _dragging_cap != null:
			_dragging_cap.freeze = false
			_dragging_cap = null
			state = State.MOVING   # may drag another cap, or swipe to shoot
		elif _aiming:
			_aiming = false
			_preview.visible = false
			_fire_shot(_aim_start, _aim_current)

# --- move -------------------------------------------------------------------

func _process(_delta: float) -> void:
	if state == State.MOVING and _dragging_cap != null:
		# pointer-follow drag, clamped to own half and inside walls
		var p := get_viewport().get_mouse_position()
		var lo := Vector2(CAP_RADIUS + 10, HALF + CAP_RADIUS + 10)
		var hi := Vector2(PITCH_X - CAP_RADIUS - 10, PITCH_Y - CAP_RADIUS - 10)
		if active_player == 1:     # top player stays above the center line
			lo.y = CAP_RADIUS + 10
			hi.y = HALF - CAP_RADIUS - 10
		_dragging_cap.position = p.clamp(lo, hi)

	if state == State.TURN_START or state == State.MOVING or state == State.AIMING:
		turn_timer -= _delta
		if turn_timer <= 0.0:
			_handle_timeout()

# --- shoot ------------------------------------------------------------------

func _fire_shot(start: Vector2, end: Vector2) -> void:
	var dir := end - start
	if dir.length() < 10.0:
		state = State.MOVING      # tap, not a swipe — no shot
		return
	var power := clampf(dir.length() * SHOT_POWER_SCALE, SHOT_POWER_MIN, SHOT_POWER_MAX)
	board.ball.apply_central_impulse(dir.normalized() * power)
	state = State.SIMULATING
	_sim_time = 0.0
	print("[Turn] P%d shot dir=%s power=%.0f" % [active_player, dir.normalized(), power])

func _update_preview() -> void:
	_preview.visible = true
	_preview.clear_points()
	var dir := _aim_current - _aim_start
	if dir.length() < 10.0:
		return
	var power := clampf(dir.length() * SHOT_POWER_SCALE, SHOT_POWER_MIN, SHOT_POWER_MAX)
	_preview.add_point(board.ball.position)
	_preview.add_point(board.ball.position + dir.normalized() * (power * 0.35))

# --- settle / evaluate ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.SIMULATING:
		_sim_time += delta
		if _sim_time > MIN_SETTLE_TIME and board.is_physics_settled():
			state = State.EVALUATE
			_evaluate_turn()

func _evaluate_turn() -> void:
	var scorer: int = board.detect_goal()
	if scorer != -1:
		score[scorer] += 1
		print("[Match] GOAL! P%d scores — %d-%d" % [scorer, score[0], score[1]])
		if score[scorer] >= WIN_GOALS:
			_end_match(scorer, false)
			return
		# conceding player kicks off from own half center (SRS 02 §3)
		active_player = 1 - scorer
		board.reset_ball(Vector2(board.PITCH.x / 2.0, 810.0 if active_player == 0 else 270.0))
		state = State.TURN_START
		turn_timer = TURN_SECONDS
		turn_changed.emit(active_player)
		print("[Turn] P%d kicks off after goal" % active_player)
	else:
		print("[Turn] P%d turn over — ball settled at %s" % [active_player, board.ball.position])
		_pass_turn()

func _pass_turn() -> void:
	active_player = 1 - active_player
	is_first_turn = false
	state = State.TURN_START
	turn_timer = TURN_SECONDS
	turn_changed.emit(active_player)

# --- timeout / forfeit (SRS 02 §4.C) -----------------------------------------

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
