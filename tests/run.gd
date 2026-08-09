extends Node
## Headless physics test suite for TableSoccer.
##
## Protocol (PHYSICS_BRIEF_FOR_CLAUDE.md §6): ONE case per FRESH process, so FSM
## state can never leak between cases. The `--headless` engine steps physics
## normally; only rendering is stubbed.
##
##   godot --headless tests/run.tscn -- <case>
##   tests/run_all.sh                          # every case, one process each
##
## Test-setup rules honoured here:
##  - No ball teleports. Possession is always established through the game's own
##    capture path (`turn_manager._attach_ball`), never by writing ball.position.
##  - Caps may be parked (brief §6.3 explicitly sanctions parking test caps);
##    parked caps are kept >= MIN_PARK_GAP apart so they don't shove neighbours.
##  - Turn timer is pinned high so the FSM can't forfeit mid-case.

const SETTLE_FRAMES := 4
const MIN_PARK_GAP := 100.0            # brief §6.3
const LONG_TIMER := 99999.0

# Wall geometry, derived from tokens — never hardcoded.
# Left wall segment is centred on x=0 with thickness WALL_THICKNESS, so its
# inner face sits at +WALL_THICKNESS/2. A ball resting against it has its
# centre at face + BALL_RADIUS.
const WALL_INNER_FACE_X := Design.WALL_THICKNESS / 2.0                    # 10.0
const BALL_MIN_X := WALL_INNER_FACE_X + Design.BALL_RADIUS                # 32.0
const BALL_ESCAPED_X := -Design.WALL_THICKNESS / 2.0 - Design.BALL_RADIUS # -32.0

var main: Node
var board: Node2D
var tm: Node
var _rows: Array[Array] = []

# --- lifecycle ---------------------------------------------------------------

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var case_name: String = args[0] if args.size() > 0 else "probe"
	await _boot()
	match case_name:
		"probe":        await _case_probe()
		"tether_moving": await _case_tether_moving()
		"wall_max":     await _case_wall_max()
		"wall_double":  await _case_wall_double()
		"tether":       await _case_tether()
		"pass_chain":   await _case_pass_chain()
		"forfeit":      await _case_forfeit()
		_:
			push_error("unknown case: %s" % case_name)
			get_tree().quit(1)
			return
	_report(case_name)

func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	# main.gd builds Board/TurnManager/HUD in _ready(); let the world settle.
	await _step(SETTLE_FRAMES)
	board = main.get_node("Board")
	tm = main.get_node("TurnManager")
	tm.turn_timer = LONG_TIMER
	tm.active_player = 0          # kickoff is randi()%2 — pin it for determinism
	tm._update_team_glow()

func _step(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _row(label: String, value: Variant) -> void:
	_rows.append([label, value])

func _report(case_name: String) -> void:
	var bar := "=".repeat(58)
	print("\n%s\nCASE: %s\n%s" % [bar, case_name, bar])
	for r in _rows:
		print("  %-26s %s" % [r[0], r[1]])
	print("%s\n" % bar)
	get_tree().quit()

# --- shared helpers ----------------------------------------------------------

func _park(cap: RigidBody2D, pos: Vector2) -> void:
	## Park a test cap. Brief §6.3 sanctions parking caps for setup; we zero the
	## velocity so a parked cap never carries stale momentum into the case.
	cap.position = pos
	cap.linear_velocity = Vector2.ZERO
	cap.angular_velocity = 0.0

func _park_others_away(keep: Array) -> void:
	## Move every cap not in `keep` out to a far corner column so it can't
	## interfere. Spacing >= MIN_PARK_GAP (brief §6.3).
	var slot := 0
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		if keep.has(cap):
			continue
		var col := Design.PITCH.x - Design.CAP_RADIUS - 4.0
		_park(cap, Vector2(col, 80.0 + float(slot) * MIN_PARK_GAP))
		slot += 1

func _blocked_report(holder: RigidBody2D) -> String:
	## Read-only mirror of the tether's candidate test in turn_manager, so a
	## failing orbit can be attributed to a specific blocker or to the bounds
	## clamp instead of guessed at. Kept in the test, not the game code.
	var ball: RigidBody2D = board.ball
	var rel: Vector2 = ball.position - holder.position
	var base_angle := rel.angle()
	var blocked_by_cap := 0
	var blocked_by_bounds := 0
	var clear := 0
	var worst := ""
	for sweep in range(34):
		var a := base_angle
		if sweep > 0:
			var dir_sign := 1.0 if sweep % 2 == 1 else -1.0
			a += dir_sign * (float(sweep) + 1.0) * 0.1
		var cand: Vector2 = holder.position + Vector2.from_angle(a) * Design.CAPTURE_DIST
		var hit := -1
		for i in board.caps.size():
			var c: RigidBody2D = board.caps[i]
			if c == holder:
				continue
			if cand.distance_to(c.position) < Design.CAPTURE_DIST:
				hit = i
				break
		if hit != -1:
			blocked_by_cap += 1
			if worst == "":
				worst = "cap%d" % hit
		elif cand.x < 42.0 or cand.x > 678.0 or cand.y < 42.0 or cand.y > 1038.0:
			blocked_by_bounds += 1
			if worst == "":
				worst = "bounds"
		else:
			clear += 1
	return "clear=%d blk_cap=%d blk_bounds=%d first=%s" % [clear, blocked_by_cap, blocked_by_bounds, worst]

func _capture_with(cap: RigidBody2D) -> void:
	## Establish possession through the REAL capture path. _attach_ball is the
	## same function a completed pass calls; it places the ball on the contact
	## circle itself, so no ball teleport happens in test code.
	tm._attach_ball(cap, Vector2.ZERO)

# --- cases -------------------------------------------------------------------

func _case_probe() -> void:
	## Environment probe: does physics step headless, driven by the real input
	## path? Launches a cap at the free ball via turn_manager._launch_cap.
	var ball: RigidBody2D = board.ball
	var cap: RigidBody2D = board.caps[4]
	var cap_start := cap.position
	var ball_start := ball.position

	tm._launch_cap(cap, ball_start - cap_start, 1000.0)

	var ball_peak := 0.0
	var min_gap := INF
	for i in 240:
		await _step(1)
		ball_peak = maxf(ball_peak, ball.linear_velocity.length())
		min_gap = minf(min_gap, cap.position.distance_to(ball.position))

	_row("initial_gap", "%.1f px" % cap_start.distance_to(ball_start))
	_row("cap_moved", "%.1f px" % cap_start.distance_to(cap.position))
	_row("ball_moved", "%.1f px" % ball_start.distance_to(ball.position))
	_row("ball_peak_speed", "%.1f px/s" % ball_peak)
	_row("min_cap_ball_gap", "%.1f px (contact %.1f)" % [min_gap, Design.CAPTURE_DIST])
	_row("cap_ball_overlap", "%.1f px" % maxf(0.0, Design.CAPTURE_DIST - min_gap))
	_row("PHYSICS_STEPS", "YES" if cap_start.distance_to(cap.position) > 1.0 else "NO")

func _case_wall_max() -> void:
	## P1: maximum-power REAL shot straight at the left wall, with a long runway
	## so the FIRST wall impact is clean (isolated from any later double-hit).
	## Holder is parked on the right side; the puck is slingshot at
	## BALL_SPEED_MAX and physically kicks the ball across the pitch.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	_park_others_away([holder])
	_park(holder, Vector2(Design.PITCH.x - 160.0, Design.PITCH.y / 2.0))
	await _step(2)
	_capture_with(holder)
	await _step(2)

	_row("holder_pos", holder.position)
	_row("ball_pos_after_capture", ball.position)
	tm._launch_puck(Vector2.LEFT, tm.BALL_SPEED_MAX)
	_row("ball_pos_after_launch", ball.position)

	var min_x := INF
	var peak := 0.0
	var speed_at_min := 0.0
	var first_min_x := INF          # min x before the first rebound
	var bounced := false
	var escaped := false
	var trace: Array[String] = []
	var prev_vx := 0.0

	for i in 300:
		await _step(1)
		var x := ball.position.x
		var vx := ball.linear_velocity.x
		var spd := ball.linear_velocity.length()
		peak = maxf(peak, spd)
		if not bounced:
			first_min_x = minf(first_min_x, x)
			if prev_vx < -1.0 and vx > 1.0:
				bounced = true
		prev_vx = vx
		if x < min_x:
			min_x = x
			speed_at_min = spd
		if x < BALL_ESCAPED_X:
			escaped = true
		if x < 120.0 and trace.size() < 10:
			trace.append("f%d x=%.1f vx=%.0f sleep=%s" % [i, x, vx, ball.sleeping])

	_row("launch_speed", "%.1f px/s" % tm.BALL_SPEED_MAX)
	_row("ball_peak_speed", "%.1f px/s" % peak)
	_row("speed_cap", "%.1f px/s" % tm.MAX_BALL_SPEED)
	_row("first_impact_min_x", "%.2f px" % first_min_x)
	_row("overall_min_x", "%.2f px" % min_x)
	_row("expected_min_x", "%.2f px" % BALL_MIN_X)
	_row("first_impact_penetration", "%.2f px" % maxf(0.0, BALL_MIN_X - first_min_x))
	_row("overall_penetration", "%.2f px" % maxf(0.0, BALL_MIN_X - min_x))
	_row("speed_at_min_x", "%.1f px/s" % speed_at_min)
	_row("px_per_frame_at_min", "%.1f" % (speed_at_min / 60.0))
	_row("ESCAPED_PITCH", "YES" if escaped else "NO")
	_row("final_ball_pos", ball.position)
	for t in trace:
		_row("  trace", t)

func _case_wall_double() -> void:
	## P1: the double-hit the MAX_BALL_SPEED comment warns about — the ball
	## rebounds off the wall into the still-advancing puck and is re-kicked.
	## Holder is parked close to the wall so the rebound meets the puck.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	_park_others_away([holder])
	# Close to the wall: puck centre one cap-radius + margin off the face.
	_park(holder, Vector2(WALL_INNER_FACE_X + Design.CAP_RADIUS + Design.CAPTURE_DIST + 20.0,
			Design.PITCH.y / 2.0))
	await _step(2)
	_capture_with(holder)
	await _step(2)

	tm._launch_puck(Vector2.LEFT, tm.BALL_SPEED_MAX)

	var min_x := INF
	var peak := 0.0
	var hits := 0
	var prev_vx := 0.0
	var escaped := false
	var escape_frame := -1
	var escape_pos := Vector2.ZERO
	var peak_frame := -1
	var trace: Array[String] = []

	for i in 300:
		await _step(1)
		var vx := ball.linear_velocity.x
		var spd := ball.linear_velocity.length()
		# sign flip from left-going to right-going = a wall bounce
		if prev_vx < -1.0 and vx > 1.0:
			hits += 1
		prev_vx = vx
		if spd > peak:
			peak = spd
			peak_frame = i
		min_x = minf(min_x, ball.position.x)
		if not escaped and ball.position.x < BALL_ESCAPED_X:
			escaped = true
			escape_frame = i
			escape_pos = ball.position
		if trace.size() < 12 and (ball.position.x < 140.0 or escaped):
			trace.append("f%d x=%.1f vx=%.0f spd=%.0f" % [i, ball.position.x, vx, spd])

	_row("ball_peak_speed", "%.1f px/s" % peak)
	_row("peak_at_frame", peak_frame)
	_row("speed_cap", "%.1f px/s" % tm.MAX_BALL_SPEED)
	_row("peak_EXCEEDS_cap", "YES" if peak > tm.MAX_BALL_SPEED + 1.0 else "NO")
	_row("wall_bounces", hits)
	_row("min_ball_x", "%.2f px" % min_x)
	_row("expected_min_x", "%.2f px" % BALL_MIN_X)
	_row("penetration", "%.2f px" % maxf(0.0, BALL_MIN_X - min_x))
	_row("ESCAPED_PITCH", "YES" if escaped else "NO")
	_row("escape_frame", escape_frame)
	_row("escape_pos", escape_pos)
	_row("final_ball_pos", ball.position)
	for t in trace:
		_row("  trace", t)

func _case_tether() -> void:
	## Regression guard for the core mechanic (brief §2/§3): the held ball
	## orbits at exactly CAPTURE_DIST and never phases through a blocking cap.
	## An opponent cap is rammed at the holder to stress the sweep.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	var mate: RigidBody2D = board.caps[4]           # OWN team, so no release rule
	_park_others_away([holder, mate])
	# Holder is parked clear of the ball spawn: parking a cap ON the ball makes
	# the solver eject it and every measurement after that is noise.
	_park(holder, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0 + 160.0))
	_park(mate, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0 - 200.0))
	await _step(2)
	_capture_with(holder)
	await _step(6)                                  # let the orbit settle

	var d1_settled := ball.position.distance_to(holder.position)
	var d1_min := INF
	var d1_max := 0.0
	var d2_min := INF
	var held_all := true
	var lost_at := -1
	# Teammate ram, tangential (brief §6.4: dead-radial hits slam the ball into
	# the holder). A teammate can't trigger the release rule, so this isolates
	# the tether's blocking/sweep behaviour from possession loss.
	mate.apply_central_impulse(Vector2(0.35, 1.0).normalized() * 1100.0 * mate.mass)

	for i in 150:
		await _step(1)
		if tm.holder == null:
			held_all = false
			lost_at = i
			break
		var d1 := ball.position.distance_to(holder.position)
		d1_min = minf(d1_min, d1)
		d1_max = maxf(d1_max, d1)
		d2_min = minf(d2_min, ball.position.distance_to(mate.position))

	_row("orbit_radius_target", "%.1f px" % Design.CAPTURE_DIST)
	_row("d1_after_settle", "%.2f px" % d1_settled)
	_row("d1_min", "%.2f px" % d1_min)
	_row("d1_max", "%.2f px" % d1_max)
	_row("d1_max_deviation", "%.2f px" % maxf(absf(d1_max - Design.CAPTURE_DIST), absf(d1_min - Design.CAPTURE_DIST)))
	_row("d2_min_vs_mate", "%.2f px" % d2_min)
	_row("phase_through", "YES" if d2_min < Design.CAPTURE_DIST - 1.0 else "NO")
	_row("held_every_frame", "YES" if held_all else "NO (lost at frame %d)" % lost_at)

func _case_tether_moving() -> void:
	## Isolates the pass_chain anomaly: same tether, same clear circle, but the
	## HOLDER is gliding instead of parked. Nothing else differs from _case_tether.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	_park_others_away([holder])
	_park(holder, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0 + 160.0))
	await _step(2)
	_capture_with(holder)
	await _step(6)

	var r_parked := ball.position.distance_to(holder.position)

	# Push the holder along +x. No collision involved — pure glide.
	holder.apply_central_impulse(Vector2.RIGHT * 600.0 * holder.mass)

	var trace: Array[String] = []
	var r_max := 0.0
	for i in 30:
		await _step(1)
		var r := ball.position.distance_to(holder.position)
		r_max = maxf(r_max, r)
		if i % 3 == 0:
			trace.append("f%d r=%.2f v_hold=%.0f %s" % [i, r, holder.linear_velocity.length(), _blocked_report(holder)])

	_row("orbit_target", "%.2f px" % Design.CAPTURE_DIST)
	_row("radius_holder_parked", "%.2f px" % r_parked)
	_row("radius_max_while_moving", "%.2f px" % r_max)
	_row("radius_final", "%.2f px" % ball.position.distance_to(holder.position))
	_row("DEGRADES_WHEN_MOVING", "YES" if r_max > Design.CAPTURE_DIST + 1.0 else "NO")
	for t in trace:
		_row("  trace", t)

func _case_pass_chain() -> void:
	## Regression guard: a real pass completes, decrements passes_left, and the
	## receiver becomes holder at the correct orbit radius.
	var ball: RigidBody2D = board.ball
	var passer: RigidBody2D = board.caps[3]
	var receiver: RigidBody2D = board.caps[4]
	_park_others_away([passer, receiver])
	_park(passer, Vector2(200.0, Design.PITCH.y / 2.0))
	_park(receiver, Vector2(200.0 + 320.0, Design.PITCH.y / 2.0))
	await _step(2)
	_capture_with(passer)
	await _step(2)

	var passes_before: int = tm.passes_left
	tm._launch_puck(receiver.position - passer.position, 900.0)

	var caught := false
	var caught_at := -1
	for i in 240:
		await _step(1)
		if tm.holder == receiver:
			caught = true
			caught_at = i
			break

	var radius_at_catch := 0.0
	var radius_settled := 0.0
	var trace: Array[String] = []
	if caught:
		radius_at_catch = ball.position.distance_to(receiver.position)
		for i in 20:                    # watch the tether pull it onto the circle
			await _step(1)
			trace.append("f%d r=%.2f v_hold=%.0f %s d_passer=%.0f" % [
				i,
				ball.position.distance_to(receiver.position),
				receiver.linear_velocity.length(),
				_blocked_report(receiver),
				passer.position.distance_to(receiver.position)])
		radius_settled = ball.position.distance_to(receiver.position)

	_row("passes_before", passes_before)
	_row("passes_after", tm.passes_left)
	_row("pass_completed", "YES" if caught else "NO")
	_row("caught_at_frame", caught_at)
	_row("holder_is_receiver", "YES" if tm.holder == receiver else "NO")
	_row("orbit_target", "%.2f px" % Design.CAPTURE_DIST)
	_row("radius_at_catch", "%.2f px" % radius_at_catch)
	_row("radius_after_settle", "%.2f px" % radius_settled)
	_row("fsm_state", tm.state)
	for t in trace:
		_row("  trace", t)

func _case_forfeit() -> void:
	## P7: 3-strike forfeit final score. The turn timer is driven by _process,
	## which gates on get_window().has_focus() — unreliable headless — so the
	## timeout handler is called directly. That IS the real handler; only the
	## clock is bypassed.
	# Turns alternate on every timeout, so P0 (who starts) reaches MAX_TIMEOUTS
	# first and is the forfeiting LOSER. Give the loser real goals — that is
	# exactly the "5-x" case the brief asks about.
	tm.score = [2, 0]
	var loser := 0

	# Sub-check: is `consecutive_timeouts` actually consecutive? Time out once,
	# then complete a normal turn, and see whether the counter clears.
	tm._handle_timeout()
	var after_one: Array = (tm.consecutive_timeouts as Array).duplicate()
	tm.active_player = loser
	tm._setup_turn()                       # a normal turn boundary
	var after_normal_turn: Array = (tm.consecutive_timeouts as Array).duplicate()

	tm.consecutive_timeouts = [0, 0]       # reset for the clean forfeit run
	tm.active_player = loser
	tm.state = tm.State.TURN_START

	var timeouts := 0
	var guard := 0
	while tm.state != tm.State.MATCH_OVER and guard < 20:
		tm._handle_timeout()
		timeouts += 1
		guard += 1
		await _step(1)

	_row("loser", "P%d" % loser)
	_row("loser_goals_before", 2)
	_row("timeouts_to_forfeit", timeouts)
	_row("consecutive_timeouts", tm.consecutive_timeouts)
	_row("final_score", tm.score)
	_row("expected_by_brief", "5-0 (loser zeroed)")
	_row("SHOWS_5_0", "YES" if tm.score[loser] == 0 else "NO (shows 5-%d)" % tm.score[loser])
	_row("state_is_MATCH_OVER", "YES" if tm.state == tm.State.MATCH_OVER else "NO")
	_row("--- consecutive check ---", "")
	_row("after_one_timeout", after_one)
	_row("after_a_normal_turn", after_normal_turn)
	_row("COUNTER_RESETS", "YES" if after_normal_turn[loser] == 0 else "NO (stays %d)" % after_normal_turn[loser])
